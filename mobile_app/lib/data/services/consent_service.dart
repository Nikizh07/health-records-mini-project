import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import '../../core/errors/api_exception.dart';

/// Patient consent API (/api/consents + /api/audit/access,
/// AUTH_RBAC_CONSENT_PLAN.md Phase 7).
class ConsentService {
  final Dio _dio;

  ConsentService({Dio? dio}) : _dio = dio ?? createApiClient();

  Future<dynamic> _call(String method, String path, String idToken, {Object? data}) async {
    try {
      final response = await _dio.request(
        path,
        data: data,
        options: Options(method: method, headers: {'Authorization': 'Bearer $idToken'}),
      );
      return response.data['data'];
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  static List<Map<String, dynamic>> _list(dynamic data) =>
      [for (final e in (data as List? ?? const [])) e as Map<String, dynamic>];

  // ── Doctor ────────────────────────────────────────────────

  /// Asks the patient for access. The request waits 10 minutes.
  Future<Map<String, dynamic>> request({required String idToken, required String patientId}) async =>
      await _call('POST', '/consents', idToken, data: {'patient_id': patientId}) as Map<String, dynamic>;

  /// Polls one of the doctor's own requests.
  Future<Map<String, dynamic>> get({required String idToken, required String consentId}) async =>
      await _call('GET', '/consents/$consentId', idToken) as Map<String, dynamic>;

  /// Redeems the patient's 6-digit share code. Wrong code → 403 with
  /// attempts_left in the message; 5 wrong → 423.
  Future<Map<String, dynamic>> redeem({
    required String idToken,
    required String patientId,
    required String code,
  }) async =>
      await _call('POST', '/consents/redeem', idToken, data: {'patient_id': patientId, 'code': code})
          as Map<String, dynamic>;

  /// Emergency access: a reason of at least 20 characters, 4-hour grant,
  /// flagged to the patient and the clinic.
  Future<Map<String, dynamic>> emergency({
    required String idToken,
    required String patientId,
    required String reason,
  }) async =>
      await _call('POST', '/consents/emergency', idToken, data: {'patient_id': patientId, 'reason': reason})
          as Map<String, dynamic>;

  // ── Patient ───────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> pending({required String idToken}) async =>
      _list(await _call('GET', '/consents/pending', idToken));

  Future<void> respond({required String idToken, required String consentId, required bool approve}) =>
      _call('POST', '/consents/$consentId/respond', idToken, data: {'approve': approve});

  /// Returns { id, code, expires_at }. The code is shown once.
  Future<Map<String, dynamic>> createShareCode({required String idToken}) async =>
      await _call('POST', '/consents/share-code', idToken) as Map<String, dynamic>;

  /// { consents: [...], access_log: [...] }.
  Future<Map<String, dynamic>> mine({required String idToken}) async =>
      await _call('GET', '/consents/mine', idToken) as Map<String, dynamic>;

  Future<void> revoke({required String idToken, required String consentId}) =>
      _call('POST', '/consents/$consentId/revoke', idToken);

  // ── audit:read ────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> accessAudit({required String idToken}) async =>
      _list(await _call('GET', '/audit/access', idToken));
}
