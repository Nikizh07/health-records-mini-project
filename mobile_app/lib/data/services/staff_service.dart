import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import '../../core/errors/api_exception.dart';

/// Staff onboarding API (/api/staff, AUTH_RBAC_CONSENT_PLAN.md Phase 3).
class StaffService {
  final Dio _dio;

  StaffService({Dio? dio}) : _dio = dio ?? createApiClient();

  Future<dynamic> _call(String method, String path, String idToken, {Object? data, Map<String, dynamic>? query}) async {
    try {
      final response = await _dio.request(
        path,
        data: data,
        queryParameters: query,
        options: Options(method: method, headers: {'Authorization': 'Bearer $idToken'}),
      );
      return response.data['data'];
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  static List<Map<String, dynamic>> _list(dynamic data) =>
      [for (final e in (data as List? ?? const [])) e as Map<String, dynamic>];

  /// Staff accounts; [status] is ACTIVE, PENDING or DISABLED.
  Future<List<Map<String, dynamic>>> listStaff({required String idToken, String? status}) async =>
      _list(await _call('GET', '/staff', idToken, query: {'status': ?status}));

  Future<List<Map<String, dynamic>>> listInvites({required String idToken}) async =>
      _list(await _call('GET', '/staff/invites', idToken));

  /// [invite]: role, name, email and/or phone, specialization (doctor),
  /// clinic_id (platform admin; a clinic admin's own clinic otherwise).
  Future<void> createInvite({required String idToken, required Map<String, dynamic> invite}) =>
      _call('POST', '/staff/invites', idToken, data: invite);

  /// [application]: name, specialization, registration_number,
  /// registration_council, clinic_id.
  Future<void> apply({required String idToken, required Map<String, dynamic> application}) =>
      _call('POST', '/staff/applications', idToken, data: application);

  /// [action] is approve, reject or disable.
  Future<void> act({required String idToken, required String userId, required String action}) =>
      _call('POST', '/staff/$userId/$action', idToken);
}
