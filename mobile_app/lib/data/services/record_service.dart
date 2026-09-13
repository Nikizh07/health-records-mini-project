import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import '../../core/errors/api_exception.dart';

class RecordService {
  final Dio _dio;

  RecordService({Dio? dio})
      : _dio = dio ?? createApiClient();

  /// Fetch full medical history for a patient via GET /api/records/patient/:patientId
  Future<List<Map<String, dynamic>>> getPatientRecords({
    required String idToken,
    required String patientId,
  }) async {
    try {
      final response = await _dio.get(
        '/records/patient/$patientId',
        options: Options(
          headers: {
            'Authorization': 'Bearer $idToken',
          },
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

  /// Fetch a single medical record detail via GET /api/records/:id
  Future<Map<String, dynamic>> getRecordById({
    required String idToken,
    required String recordId,
  }) async {
    try {
      final response = await _dio.get(
        '/records/$recordId',
        options: Options(
          headers: {
            'Authorization': 'Bearer $idToken',
          },
        ),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data'] as Map<String, dynamic>;
      }
      throw ApiException('Record not found.', statusCode: 404);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Create a new medical record with nested prescriptions via POST /api/records
  Future<Map<String, dynamic>> createMedicalRecord({
    required String idToken,
    required String patientId,
    String? doctorId,
    String? appointmentId,
    String? visitDate,
    required String diagnosis,
    String? notes,
    List<Map<String, String>>? prescriptions,
    String? checkId,
    String? overrideReason,
  }) async {
    try {
      final payload = <String, dynamic>{
        'patient_id': patientId,
        'diagnosis': diagnosis,
        if (doctorId != null && doctorId.isNotEmpty) 'doctor_id': doctorId,
        if (appointmentId != null && appointmentId.isNotEmpty) 'appointment_id': appointmentId,
        if (visitDate != null && visitDate.isNotEmpty) 'visit_date': visitDate,
        'notes': ?notes,
        if (prescriptions != null && prescriptions.isNotEmpty) 'prescriptions': prescriptions,
        // Links the save to the pre-flight interaction check. The server reads
        // the conflicts back from that row, so it rejects the save unless a
        // reason accompanies a check that actually found something.
        if (checkId != null && checkId.isNotEmpty) 'check_id': checkId,
        if (overrideReason != null && overrideReason.isNotEmpty)
          'override_reason': overrideReason,
      };

      final response = await _dio.post(
        '/records',
        data: payload,
        options: Options(
          headers: {
            'Authorization': 'Bearer $idToken',
          },
        ),
      );

      if ((response.statusCode == 200 || response.statusCode == 201) &&
          response.data['success'] == true) {
        return response.data['data'] as Map<String, dynamic>;
      }
      throw ApiException(response.data['message']?.toString() ?? 'Failed to create medical record.');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Pre-flight drug interaction check via POST /api/records/interaction-check.
  ///
  /// Compares the prescriptions about to be written against everything the
  /// patient is still taking at any clinic, plus the drugs in this same list.
  ///
  /// Returns `{ check_id, conflicts, ai_available }`. Each conflict carries a
  /// `scope`: `EXISTING` (names `clinic_name` and `prescribed_on`) or
  /// `SAME_VISIT` (both null — neither drug has been dispensed yet).
  Future<Map<String, dynamic>> checkDrugInteractions({
    required String idToken,
    required String patientId,
    required List<Map<String, String>> prescriptions,
  }) async {
    try {
      final response = await _dio.post(
        '/records/interaction-check',
        data: {
          'patient_id': patientId,
          'prescriptions': prescriptions,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $idToken',
          },
        ),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return Map<String, dynamic>.from(response.data['data'] as Map);
      }
      throw ApiException(
        response.data['message']?.toString() ?? 'Interaction check failed.',
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
