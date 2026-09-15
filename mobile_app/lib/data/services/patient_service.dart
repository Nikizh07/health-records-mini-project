import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import '../../core/errors/api_exception.dart';

class PatientService {
  final Dio _dio;

  PatientService({Dio? dio})
      : _dio = dio ?? createApiClient();

  /// Calls GET /api/patients/me with the Firebase ID token in Authorization header.
  /// Returns the profile map if found. On 404 (no profile yet) returns only
  /// `{'next': 'REGISTER' | 'CLAIM' | 'VERIFY_EMAIL' | 'STAFF_APPLY'}` from the backend.
  Future<Map<String, dynamic>?> getMyProfile(String idToken) async {
    try {
      final response = await _dio.get(
        '/patients/me',
        options: Options(
          headers: {
            'Authorization': 'Bearer $idToken',
          },
        ),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data'] as Map<String, dynamic>;
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        final data = e.response?.data;
        return {'next': (data is Map ? data['next'] : null) ?? 'REGISTER'};
      }
      throw ApiException.fromDioException(e);
    }
  }

  /// Calls POST /api/patients to register a new patient profile.
  Future<Map<String, dynamic>> createPatient({
    required String idToken,
    required String name,
    required String dob, // Format: YYYY-MM-DD
    required String gender, // 'Male', 'Female', 'Other'
    required String languagePref,
    String? phone,
  }) async {
    try {
      final response = await _dio.post(
        '/patients',
        data: {
          'name': name,
          'dob': dob,
          'gender': gender,
          'language_pref': languagePref,
          'phone': ?phone,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $idToken',
          },
        ),
      );

      if (response.statusCode == 201 && response.data['success'] == true) {
        return response.data['data'] as Map<String, dynamic>;
      }
      throw ApiException(response.data['message']?.toString() ?? 'Failed to register patient');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /api/patients/claim: links a clinic-registered profile to this phone
  /// sign-in when [dob] (YYYY-MM-DD) matches. Returns the profile.
  Future<Map<String, dynamic>> claimPatient({required String idToken, required String dob}) async {
    try {
      final response = await _dio.post(
        '/patients/claim',
        data: {'dob': dob},
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );
      return response.data['data'] as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Calls PUT /api/patients/:id to update editable profile fields.
  /// Only non-null arguments are sent — the backend does partial updates.
  Future<Map<String, dynamic>> updatePatient({
    required String idToken,
    required String patientId,
    String? name,
    String? dob,       // Format: YYYY-MM-DD
    String? gender,    // 'Male' | 'Female' | 'Other'
    String? languagePref,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (dob != null) body['dob'] = dob;
    if (gender != null) body['gender'] = gender;
    if (languagePref != null) body['language_pref'] = languagePref;

    try {
      final response = await _dio.put(
        '/patients/$patientId',
        data: body,
        options: Options(
          headers: {'Authorization': 'Bearer $idToken'},
        ),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data'] as Map<String, dynamic>;
      }
      throw ApiException(response.data['message']?.toString() ?? 'Failed to update profile');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Search patients by partial name or Health ID via GET /api/patients/search?q=`query`
  /// Returns up to 10 matches. Requires DOCTOR or ADMIN role token.
  /// Each result: { id, name, health_id, phone, gender, dob }
  Future<List<Map<String, dynamic>>> searchPatients({
    required String idToken,
    required String query,
  }) async {
    try {
      final response = await _dio.get(
        '/patients/search',
        queryParameters: {'q': query},
        options: Options(
          headers: {'Authorization': 'Bearer $idToken'},
        ),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final List<dynamic> dataList = response.data['data'] ?? [];
        return dataList.map((item) => item as Map<String, dynamic>).toList();
      }
      return [];
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
