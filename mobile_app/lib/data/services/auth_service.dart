import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Service class encapsulating Firebase Phone Authentication for both Web and Mobile.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Web confirmation result holder
  ConfirmationResult? _webConfirmationResult;

  // Mobile verification ID holder
  String? _mobileVerificationId;
  int? _mobileResendToken;

  AuthService();

  /// Returns the currently authenticated Firebase user
  User? get currentUser => _auth.currentUser;

  /// Retrieves the latest Firebase JWT ID Token for API requests
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    return await _auth.currentUser?.getIdToken(forceRefresh);
  }

  /// Sends an OTP to the given [phoneNumber] (e.g. "+919876543210").
  ///
  /// On Web: Uses [signInWithPhoneNumber] with standard SMS OTP flow.
  /// On Mobile: Uses [verifyPhoneNumber].
  /// With [link], the phone is added to the signed-in (Google / email) user
  /// instead of signing in: patients need a verified phone.
  Future<void> sendOtp({
    required String phoneNumber,
    bool link = false,
    required Function(String verificationId) onCodeSent,
    required Function(FirebaseAuthException error) onVerificationFailed,
    required Function(PhoneAuthCredential credential) onAutoVerify,
  }) async {
    if (kIsWeb) {
      try {
        _webConfirmationResult = link
            ? await _auth.currentUser!.linkWithPhoneNumber(phoneNumber)
            : await _auth.signInWithPhoneNumber(phoneNumber);
        onCodeSent(_webConfirmationResult?.verificationId ?? 'web_verification');
      } on FirebaseAuthException catch (e) {
        onVerificationFailed(e);
      } catch (e) {
        onVerificationFailed(
          FirebaseAuthException(
            code: 'unknown_error',
            message: e.toString(),
          ),
        );
      }
    } else {
      // Mobile (Android / iOS) Phone Auth
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          link
              ? await _auth.currentUser!.linkWithCredential(credential)
              : await _auth.signInWithCredential(credential);
          onAutoVerify(credential);
        },
        verificationFailed: onVerificationFailed,
        codeSent: (String verificationId, int? resendToken) {
          _mobileVerificationId = verificationId;
          _mobileResendToken = resendToken;
          onCodeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _mobileVerificationId = verificationId;
        },
        forceResendingToken: _mobileResendToken,
      );
    }
  }

  /// Verifies the entered 6-digit [smsCode].
  Future<UserCredential> verifyOtp({
    required String smsCode,
    String? verificationId,
    bool link = false,
  }) async {
    if (kIsWeb) {
      if (_webConfirmationResult == null) {
        throw FirebaseAuthException(
          code: 'no_confirmation_result',
          message: 'Please request a new OTP first.',
        );
      }
      return await _webConfirmationResult!.confirm(smsCode);
    } else {
      final id = verificationId ?? _mobileVerificationId;
      if (id == null) {
        throw FirebaseAuthException(
          code: 'no_verification_id',
          message: 'Verification ID not found. Please resend the code.',
        );
      }
      final credential = PhoneAuthProvider.credential(
        verificationId: id,
        smsCode: smsCode,
      );
      return link
          ? await _auth.currentUser!.linkWithCredential(credential)
          : await _auth.signInWithCredential(credential);
    }
  }

  /// Signs the user out from Firebase Auth
  Future<void> signOut() async {
    _webConfirmationResult = null;
    _mobileVerificationId = null;
    await _auth.signOut();
  }

  /// Guest sign-in (anonymous authentication)
  /// This bypasses phone verification temporarily for testing/demo purposes
  Future<UserCredential> signInAsGuest() async {
    return await _auth.signInAnonymously();
  }

  // Email/password and Google sign-in (staff, and patients who then link a
  // phone). Both providers are enabled in the Firebase console; Google on
  // Android also needs the app's SHA-1.

  Future<UserCredential> signInWithEmail(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

  Future<UserCredential> signUpWithEmail(String email, String password) =>
      _auth.createUserWithEmailAndPassword(email: email, password: password);

  Future<void> sendEmailVerification() async => _auth.currentUser?.sendEmailVerification();

  Future<void> sendPasswordReset(String email) => _auth.sendPasswordResetEmail(email: email);

  Future<UserCredential> signInWithGoogle() => kIsWeb
      ? _auth.signInWithPopup(GoogleAuthProvider())
      : _auth.signInWithProvider(GoogleAuthProvider());

  /// Picks up `emailVerified` after the user clicks the link in the email.
  Future<void> reloadUser() async => _auth.currentUser?.reload();
}
