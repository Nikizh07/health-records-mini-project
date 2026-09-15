import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import '../../core/errors/api_exception.dart';

class AdminService {
  final Dio _dio;

  AdminService({Dio? dio})
      : _dio = dio ?? createApiClient();

  // ---------------------------------------------------------------------------
  // CLINICS (GET /api/clinics, PUT /api/clinics/:id)
  // ---------------------------------------------------------------------------

  /// Fetch all clinics
  Future<List<Map<String, dynamic>>> getAllClinics({
    required String idToken,
  }) async {
    try {
      final response = await _dio.get(
        '/clinics',
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final List<dynamic> data = response.data['data'] ?? [];
        return data.map((e) => e as Map<String, dynamic>).toList();
      }
      return [];
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Update clinic details via PUT /api/clinics/:id
  Future<Map<String, dynamic>> updateClinic({
    required String idToken,
    required String clinicId,
    String? name,
    String? location,
    String? contactNumber,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final payload = <String, dynamic>{};
      if (name != null && name.trim().isNotEmpty) payload['name'] = name.trim();
      if (location != null && location.trim().isNotEmpty) payload['location'] = location.trim();
      if (contactNumber != null && contactNumber.trim().isNotEmpty) {
        payload['contact_number'] = contactNumber.trim();
      }
      if (latitude != null) payload['latitude'] = latitude;
      if (longitude != null) payload['longitude'] = longitude;

      final response = await _dio.put(
        '/clinics/$clinicId',
        data: payload,
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data'] as Map<String, dynamic>;
      }
      throw ApiException(response.data['message']?.toString() ?? 'Failed to update clinic.');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
