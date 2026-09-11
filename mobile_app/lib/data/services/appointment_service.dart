import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import '../../core/errors/api_exception.dart';

/// Thrown when POST /api/appointments returns HTTP 409 Conflict,
/// meaning another patient has already booked that doctor + slot_time.
class SlotTakenException implements Exception {
  final String message;
  const SlotTakenException(
      [this.message = 'This slot is already taken by another patient.']);

  @override
  String toString() => message;
}

class AppointmentService {
  final Dio _dio;

  AppointmentService({Dio? dio})
      : _dio = dio ?? createApiClient();

  // ---------------------------------------------------------------------------
  // GET /api/clinics
  // ---------------------------------------------------------------------------

  /// Returns every clinic the backend knows about.
  Future<List<Map<String, dynamic>>> getClinics({
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

  // ---------------------------------------------------------------------------
  // GET /api/doctors?clinic_id={clinicId}
  // ---------------------------------------------------------------------------

  /// Returns all doctors belonging to [clinicId].
  Future<List<Map<String, dynamic>>> getDoctors({
    required String idToken,
    required String clinicId,
  }) async {
    try {
      final response = await _dio.get(
        '/doctors',
        queryParameters: {'clinic_id': clinicId},
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

  // ---------------------------------------------------------------------------
  // POST /api/appointments
  // ---------------------------------------------------------------------------

  /// Books an appointment and returns the created appointment object.
  /// Throws [SlotTakenException] on HTTP 409 Conflict.
  Future<Map<String, dynamic>> bookAppointment({
    required String idToken,
    required String doctorId,
    required String clinicId,
    required String slotTime, // ISO-8601 formatted DateTime
  }) async {
    try {
      final response = await _dio.post(
        '/appointments',
        data: {
          'doctor_id': doctorId,
          'clinic_id': clinicId,
          'slot_time': slotTime,
        },
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );

      if ((response.statusCode == 200 || response.statusCode == 201) &&
          response.data['success'] == true) {
        return response.data['data'] as Map<String, dynamic>;
      }
      throw ApiException(response.data['message']?.toString() ?? 'Booking failed.');
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        throw const SlotTakenException();
      }
      throw ApiException.fromDioException(e);
    }
  }

  /// Doctor/admin creates an on-the-spot (walk-in) appointment for a patient.
  /// The backend defaults the doctor to the caller, the clinic to theirs and
  /// the time to now, and marks it confirmed.
  Future<Map<String, dynamic>> createWalkIn({
    required String idToken,
    required String patientId,
  }) async {
    try {
      final response = await _dio.post(
        '/appointments',
        data: {'patient_id': patientId},
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );

      if ((response.statusCode == 200 || response.statusCode == 201) &&
          response.data['success'] == true) {
        return response.data['data'] as Map<String, dynamic>;
      }
      throw ApiException(response.data['message']?.toString() ?? 'Could not add walk-in.');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  // ---------------------------------------------------------------------------
  // GET /api/appointments (Doctor & Admin view)
  // ---------------------------------------------------------------------------

  /// Returns appointments filtered by [doctorId], [date] (YYYY-MM-DD), and/or [status].
  Future<List<Map<String, dynamic>>> getDoctorAppointments({
    required String idToken,
    String? doctorId,
    String? clinicId,
    String? date,
    String? status,
  }) async {
    try {
      final queryParams = <String, dynamic>{};
      if (doctorId != null && doctorId.isNotEmpty) queryParams['doctor_id'] = doctorId;
      if (clinicId != null && clinicId.isNotEmpty) queryParams['clinic_id'] = clinicId;
      if (date != null && date.isNotEmpty) queryParams['date'] = date;
      if (status != null && status.isNotEmpty) queryParams['status'] = status;

      final response = await _dio.get(
        '/appointments',
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
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

  // ---------------------------------------------------------------------------
  // GET /api/appointments/me
  // ---------------------------------------------------------------------------

  /// Returns all appointments for the authenticated patient.
  Future<List<Map<String, dynamic>>> getMyAppointments({
    required String idToken,
    String? status,
  }) async {
    try {
      final response = await _dio.get(
        '/appointments/me',
        queryParameters: status != null ? {'status': status} : null,
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

  // ---------------------------------------------------------------------------
  // PUT /api/appointments/:id (Reschedule)
  // ---------------------------------------------------------------------------

  /// Reschedules an appointment with a new [slotTime] (ISO-8601 string).
  Future<Map<String, dynamic>> rescheduleAppointment({
    required String idToken,
    required String appointmentId,
    required String slotTime,
  }) async {
    try {
      final response = await _dio.put(
        '/appointments/$appointmentId',
        data: {
          'slot_time': slotTime,
        },
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data'] as Map<String, dynamic>;
      }
      throw ApiException(response.data['message']?.toString() ?? 'Reschedule failed.');
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        throw const SlotTakenException();
      }
      throw ApiException.fromDioException(e);
    }
  }

  // ---------------------------------------------------------------------------
  // PATCH /api/appointments/:id/cancel
  // ---------------------------------------------------------------------------

  /// Cancels an appointment (soft-cancel, status becomes 'cancelled').
  Future<Map<String, dynamic>> cancelAppointment({
    required String idToken,
    required String appointmentId,
  }) async {
    try {
      final response = await _dio.patch(
        '/appointments/$appointmentId/cancel',
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data'] as Map<String, dynamic>;
      }
      throw ApiException(response.data['message']?.toString() ?? 'Cancellation failed.');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
