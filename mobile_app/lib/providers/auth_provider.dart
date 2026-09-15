import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/errors/api_exception.dart';
import '../data/services/auth_service.dart';
import '../data/services/local_cache_service.dart';
import '../data/services/patient_service.dart';
import '../data/services/secure_storage_service.dart';

enum AuthStatus {
  restoring, // checking for a saved session on app start
  initial,
  otpSending,
  otpSent,
  verifying,
  authenticated,
  needsRegistration,
  error,
}

class AuthState {
  final AuthStatus status;
  final String? phoneNumber;
  final String? verificationId;
  final String? idToken;
  final Map<String, dynamic>? patientProfile;
  final String? errorMessage;

  const AuthState({
    this.status = AuthStatus.initial,
    this.phoneNumber,
    this.verificationId,
    this.idToken,
    this.patientProfile,
    this.errorMessage,
  });

  bool get isLoading =>
      status == AuthStatus.otpSending || status == AuthStatus.verifying;

  bool get isAuthenticated =>
      status == AuthStatus.authenticated && idToken != null;

  /// PATIENT / DOCTOR / ADMIN, from the backend profile payload.
  String get role => ((patientProfile?['user'] as Map?)?['role'] ??
          patientProfile?['role'] ??
          'PATIENT')
      .toString()
      .toUpperCase();

  /// Permissions from the backend's table (backend/config/permissions.js),
  /// sent in /patients/me. Empty for PENDING or DISABLED accounts.
  bool can(String permission) =>
      (patientProfile?['permissions'] as List?)?.contains(permission) ?? false;

  AuthState copyWith({
    AuthStatus? status,
    String? phoneNumber,
    String? verificationId,
    String? idToken,
    Map<String, dynamic>? patientProfile,
    String? errorMessage,
  }) {
    return AuthState(
      status: status ?? this.status,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      verificationId: verificationId ?? this.verificationId,
      idToken: idToken ?? this.idToken,
      patientProfile: patientProfile ?? this.patientProfile,
      errorMessage: errorMessage,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;
  final PatientService _patientService;
  final SecureStorageService _secureStorage;

  AuthNotifier(this._authService, this._patientService, this._secureStorage)
      : super(const AuthState(status: AuthStatus.restoring)) {
    restoreSession();
  }

  /// Attempts to restore a previous session from Secure Storage and Firebase on app boot.
  /// Only an explicit 401/403 ends the session; network failures keep it
  /// (using the cached profile) so the offline cache stays usable.
  Future<void> restoreSession() async {
    String? token;
    String? phone;
    try {
      // 1. Prefer a token from the live Firebase user (refreshes if expired)
      final currentUser = _authService.currentUser;
      // Anonymous (guest) users report '' rather than null.
      final firebasePhone = currentUser?.phoneNumber;
      phone = (firebasePhone == null || firebasePhone.isEmpty) ? null : firebasePhone;
      if (currentUser != null) {
        try {
          token = await _authService.getIdToken();
        } catch (_) {
          // Offline and token expired — fall back to the stored one below.
        }
      }

      // 2. Fall back to encrypted secure storage
      token ??= await _secureStorage.getToken();
      phone ??= await _secureStorage.getPhoneNumber();

      if (token == null || token.isEmpty) {
        state = const AuthState();
        return;
      }

      // 3. Keep secure storage synchronized
      await _secureStorage.saveToken(token);
      if (phone != null && phone.isNotEmpty) {
        await _secureStorage.savePhoneNumber(phone);
      }
      state = state.copyWith(idToken: token, phoneNumber: phone);

      // 4. Validate session by fetching user profile
      final profile = await _patientService.getMyProfile(token);
      if (profile != null) {
        await LocalCacheService.saveProfile(profile);
        state = state.copyWith(
          status: AuthStatus.authenticated,
          patientProfile: profile,
        );
      } else {
        state = state.copyWith(status: AuthStatus.needsRegistration);
      }
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        await _secureStorage.clearAll();
        await LocalCacheService.clearProfile();
        state = const AuthState();
      } else {
        _restoreFromCache(token, phone);
      }
    } catch (_) {
      _restoreFromCache(token, phone);
    }
  }

  /// Server unreachable during restore: stay signed in with the cached profile.
  void _restoreFromCache(String? token, String? phone) {
    final cached = LocalCacheService.getProfile();
    if (token != null && cached != null) {
      state = AuthState(
        status: AuthStatus.authenticated,
        idToken: token,
        phoneNumber: phone,
        patientProfile: cached,
      );
    } else {
      state = const AuthState();
    }
  }

  /// Step 3: Trigger OTP dispatch via Firebase
  Future<void> sendOtp(String rawPhone) async {
    // Standardize to E.164 format (+91 for India if not specified)
    String formattedPhone = rawPhone.trim();
    if (!formattedPhone.startsWith('+')) {
      formattedPhone = '+91$formattedPhone';
    }

    state = state.copyWith(
      status: AuthStatus.otpSending,
      phoneNumber: formattedPhone,
      errorMessage: null,
    );

    try {
      await _authService.sendOtp(
        phoneNumber: formattedPhone,
        onCodeSent: (verificationId) {
          state = state.copyWith(
            status: AuthStatus.otpSent,
            verificationId: verificationId,
          );
        },
        onVerificationFailed: (error) {
          state = state.copyWith(
            status: AuthStatus.error,
            errorMessage: error.message ?? 'Verification failed (${error.code})',
          );
        },
        onAutoVerify: (credential) async {
          // If auto-retrieved on mobile
          await _onAuthSuccess();
        },
      );
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Step 5: Verify 6-digit OTP and check patient profile
  Future<void> verifyOtp(String smsCode) async {
    state = state.copyWith(
      status: AuthStatus.verifying,
      errorMessage: null,
    );

    try {
      await _authService.verifyOtp(
        smsCode: smsCode.trim(),
        verificationId: state.verificationId,
      );

      await _onAuthSuccess();
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.message ?? 'Invalid OTP code.',
      );
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Handles token retrieval, secure storage persistence, and backend profile check
  Future<void> _onAuthSuccess() async {
    try {
      final token = await _authService.getIdToken(forceRefresh: true);
      if (token == null) {
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: 'Failed to retrieve Firebase ID token.',
        );
        return;
      }

      // Persist token and phone in hardware-backed encrypted storage
      await _secureStorage.saveToken(token);
      if (state.phoneNumber != null) {
        await _secureStorage.savePhoneNumber(state.phoneNumber!);
      }

      state = state.copyWith(idToken: token);

      // Call GET /api/patients/me
      final profile = await _patientService.getMyProfile(token);

      if (profile != null) {
        // Patient profile exists -> go to Dashboard
        await LocalCacheService.saveProfile(profile);
        state = state.copyWith(
          status: AuthStatus.authenticated,
          patientProfile: profile,
        );
      } else {
        // 404 Not Found -> Patient needs registration
        state = state.copyWith(
          status: AuthStatus.needsRegistration,
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  /// Complete patient registration via POST /api/patients
  Future<bool> registerPatient({
    required String name,
    required String dob,
    required String gender,
    required String languagePref,
  }) async {
    if (state.idToken == null) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'User not authenticated with Firebase.',
      );
      return false;
    }

    state = state.copyWith(
      status: AuthStatus.verifying,
      errorMessage: null,
    );

    try {
      final newProfile = await _patientService.createPatient(
        idToken: state.idToken!,
        name: name,
        dob: dob,
        gender: gender,
        languagePref: languagePref,
        phone: state.phoneNumber,
      );

      await LocalCacheService.saveProfile(newProfile);
      state = state.copyWith(
        status: AuthStatus.authenticated,
        patientProfile: newProfile,
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
      return false;
    }
  }

  /// Update editable patient profile fields via PUT /api/patients/:id.
  /// Patches the in-memory patientProfile so the dashboard updates immediately.
  Future<void> updateProfile({
    String? name,
    String? dob,
    String? gender,
    String? languagePref,
  }) async {
    if (state.idToken == null) throw Exception('Not authenticated');

    final currentProfile = state.patientProfile;
    if (currentProfile == null) throw Exception('Profile not loaded');

    final patientId = currentProfile['id']?.toString() ?? '';
    if (patientId.isEmpty) throw Exception('Patient ID missing');

    final updated = await _patientService.updatePatient(
      idToken: state.idToken!,
      patientId: patientId,
      name: name,
      dob: dob,
      gender: gender,
      languagePref: languagePref,
    );

    // Merge updated fields into the existing profile map so other fields are preserved
    final merged = Map<String, dynamic>.from(currentProfile)..addAll(updated);
    await LocalCacheService.saveProfile(merged);
    state = state.copyWith(patientProfile: merged);
  }

  /// Sign out and purge secure storage credentials
  Future<void> signOut() async {
    await _secureStorage.clearAll();
    await LocalCacheService.clearProfile();
    await _authService.signOut();
    state = const AuthState();
  }

  /// Guest sign-in (temporary anonymous authentication)
  /// Creates a guest session without phone verification
  Future<void> signInAsGuest() async {
    state = state.copyWith(
      status: AuthStatus.verifying,
      errorMessage: null,
    );

    try {
      // Sign in anonymously via Firebase
      await _authService.signInAsGuest();

      // Get the Firebase token
      final token = await _authService.getIdToken(forceRefresh: true);
      if (token == null) {
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: 'Failed to create guest session.',
        );
        return;
      }

      // Store guest token
      await _secureStorage.saveToken(token);
      await _secureStorage.savePhoneNumber('guest'); // Mark as guest user

      state = state.copyWith(
        idToken: token,
        phoneNumber: 'guest',
      );

      // Try to fetch profile, if none exists, redirect to registration
      final profile = await _patientService.getMyProfile(token);

      if (profile != null) {
        await LocalCacheService.saveProfile(profile);
        state = state.copyWith(
          status: AuthStatus.authenticated,
          patientProfile: profile,
        );
      } else {
        // Guest needs to create profile
        state = state.copyWith(
          status: AuthStatus.needsRegistration,
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'Guest sign-in failed: ${e.toString()}',
      );
    }
  }
}

// Global Providers
final authServiceProvider = Provider<AuthService>((ref) => AuthService());
final patientServiceProvider = Provider<PatientService>((ref) => PatientService());
final secureStorageServiceProvider = Provider<SecureStorageService>((ref) => SecureStorageService());

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  final patientService = ref.watch(patientServiceProvider);
  final secureStorage = ref.watch(secureStorageServiceProvider);
  return AuthNotifier(authService, patientService, secureStorage);
});

// Helper provider for convenient token access in other providers
final authTokenProvider = Provider<String?>((ref) {
  return ref.watch(authNotifierProvider).idToken;
});
