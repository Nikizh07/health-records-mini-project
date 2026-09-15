import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/constants/app_constants.dart';

/// Service responsible for persisting sensitive authentication credentials
/// securely at rest using platform-level hardware security modules:
/// - Android: EncryptedSharedPreferences backed by Android Keystore (AES-256)
/// - iOS: Apple Keychain Services backed by Secure Enclave
class SecureStorageService {
  final FlutterSecureStorage _storage;

  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
              ),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  static const String _tokenKey = AppConstants.authTokenKey;
  static const String _phoneKey = 'user_phone_number';
  static const String _patientIntentKey = 'signed_in_as_patient';

  /// Securely write the Firebase JWT ID Token
  Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  /// Retrieve the stored Firebase JWT ID Token
  Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  /// Remove the stored token on logout
  Future<void> deleteToken() async {
    await _storage.delete(key: _tokenKey);
  }

  /// Securely write the authenticated phone number
  Future<void> savePhoneNumber(String phoneNumber) async {
    await _storage.write(key: _phoneKey, value: phoneNumber);
  }

  /// Retrieve the stored phone number
  Future<String?> getPhoneNumber() async {
    return await _storage.read(key: _phoneKey);
  }

  /// Whether the user chose the patient side for a Google / email sign-in, so a
  /// restart still asks them to link a phone rather than apply as staff.
  Future<void> savePatientIntent(bool asPatient) async {
    await _storage.write(key: _patientIntentKey, value: asPatient ? '1' : null);
  }

  Future<bool> getPatientIntent() async => await _storage.read(key: _patientIntentKey) == '1';

  /// Clear all securely stored credentials
  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
