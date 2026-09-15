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
  needsPhoneLink, // patient signed in with Google / email: add a verified phone
  needsClaim, // a clinic registered this phone: confirm date of birth
  needsEmailVerification, // email sign-up, link not clicked yet
  needsStaffApplication, // verified email, no invite: apply as a doctor
  pendingApproval, // applied, waiting for a clinic admin
  error,
}

/// Status for a GET /patients/me result: a profile, or `{'next': ...}` on 404.
/// [needsPhone]: a patient-side sign-in whose Firebase user has no phone yet.
AuthStatus statusForProfile(Map<String, dynamic>? profile, {bool needsPhone = false}) => switch (profile) {
      {'next': _} when needsPhone => AuthStatus.needsPhoneLink,
      {'next': 'CLAIM'} => AuthStatus.needsClaim,
      {'next': 'VERIFY_EMAIL'} => AuthStatus.needsEmailVerification,
      {'next': 'STAFF_APPLY'} => AuthStatus.needsStaffApplication,
      null || {'next': _} => AuthStatus.needsRegistration,
      {'status': 'PENDING'} => AuthStatus.pendingApproval,
      _ => AuthStatus.authenticated,
    };

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

  /// The page this session belongs on, or null while signing in.
  String? get route => switch (status) {
        AuthStatus.authenticated => '/',
        AuthStatus.needsRegistration => '/register',
        AuthStatus.needsPhoneLink => '/link-phone',
        AuthStatus.needsClaim => '/claim',
        AuthStatus.needsEmailVerification => '/verify-email',
        AuthStatus.needsStaffApplication || AuthStatus.pendingApproval => '/staff-apply',
        _ => null,
      };

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

  /// Chose the patient side for a Google / email sign-in (kept in storage).
  bool _asPatient = false;

  /// The OTP being sent / verified adds a phone to the signed-in user.
  bool _linking = false;

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
      _asPatient = await _secureStorage.getPatientIntent();

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
      await _applyProfile(await _patientService.getMyProfile(token));
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
        status: statusForProfile(cached),
        idToken: token,
        phoneNumber: phone,
        patientProfile: cached,
      );
    } else {
      state = const AuthState();
    }
  }

  /// Step 3: Trigger OTP dispatch via Firebase. [link] adds the phone to the
  /// signed-in Google / email user; a resend keeps the previous mode.
  Future<void> sendOtp(String rawPhone, {bool? link}) async {
    _linking = link ?? _linking;
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
        link: _linking,
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
        link: _linking,
      );

      await _onAuthSuccess();
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.code == 'credential-already-in-use' || e.code == 'account-exists-with-different-credential'
            ? 'This number already has an account. Sign out and sign in with the phone number instead.'
            : e.message ?? 'Invalid OTP code.',
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

      await _applyProfile(await _patientService.getMyProfile(token));
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  /// Routes a GET /patients/me result. Only real profiles are cached.
  Future<void> _applyProfile(Map<String, dynamic>? profile) async {
    final phone = _authService.currentUser?.phoneNumber;
    final status = statusForProfile(profile, needsPhone: _asPatient && (phone == null || phone.isEmpty));
    if (profile == null || profile.containsKey('next')) {
      // No profile: drop any old one (e.g. a rejected application's).
      state = AuthState(status: status, idToken: state.idToken, phoneNumber: state.phoneNumber);
      return;
    }
    await LocalCacheService.saveProfile(profile);
    state = state.copyWith(status: status, patientProfile: profile);
  }

  /// Email/password (sign-up when [create]) or Google. Staff go on to invite /
  /// application; patients ([asPatient]) go on to link a phone. Only staff need
  /// a verified email, so only they get the verification email.
  Future<void> signInWithEmail(String email, String password, {bool create = false, bool asPatient = false}) =>
      _signIn(asPatient, () async {
        if (!create) {
          await _authService.signInWithEmail(email.trim(), password);
        } else {
          await _authService.signUpWithEmail(email.trim(), password);
          if (!asPatient) await _authService.sendEmailVerification();
        }
      });

  Future<void> signInWithGoogle({bool asPatient = false}) => _signIn(asPatient, _authService.signInWithGoogle);

  Future<void> _signIn(bool asPatient, Future<void> Function() signIn) async {
    state = state.copyWith(status: AuthStatus.verifying);
    try {
      _asPatient = asPatient;
      await _secureStorage.savePatientIntent(asPatient);
      await signIn();
      await _onAuthSuccess();
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.message ?? 'Sign-in failed (${e.code}).',
      );
    }
  }

  Future<void> sendPasswordReset(String email) => _authService.sendPasswordReset(email.trim());

  Future<void> resendEmailVerification() => _authService.sendEmailVerification();

  /// Re-reads the Firebase user and the backend profile: after clicking the
  /// verification link, or to see whether an application was approved.
  Future<void> recheck() async {
    try {
      await _authService.reloadUser();
    } catch (_) {
      // Offline: _onAuthSuccess reports it.
    }
    await _onAuthSuccess();
  }

  /// Link a clinic-registered profile by date of birth (YYYY-MM-DD).
  Future<void> claimProfile(String dob) async {
    state = state.copyWith(status: AuthStatus.verifying);
    try {
      await _applyProfile(await _patientService.claimPatient(idToken: state.idToken ?? '', dob: dob));
    } catch (e) {
      state = state.copyWith(status: AuthStatus.error, errorMessage: e.toString());
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
    _asPatient = false;
    _linking = false;
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

      await _applyProfile(await _patientService.getMyProfile(token));
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
