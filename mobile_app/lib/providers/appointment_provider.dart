import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../core/models/cached_result.dart';
import '../data/services/appointment_service.dart';
import '../data/services/local_cache_service.dart';
import 'auth_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Service provider (mirrors patientServiceProvider pattern)
// ─────────────────────────────────────────────────────────────────────────────

final appointmentServiceProvider = Provider<AppointmentService>((ref) {
  return AppointmentService();
});

// ─────────────────────────────────────────────────────────────────────────────
// Geolocation & FutureProviders
// ─────────────────────────────────────────────────────────────────────────────

/// Fetches the user's current GPS position if permission is granted.
/// Returns null if location service is disabled, permissions are denied, or on error/timeout.
final userLocationProvider = FutureProvider.autoDispose<Position?>((ref) async {
  try {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return null;
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 5),
      ),
    );
  } catch (e) {
    // If location lookup fails for any reason (timeout, emulator without GPS, etc.), gracefully return null
    return null;
  }
});

/// Fetches all clinics from GET /api/clinics.
/// If user GPS location is available, calculates the distance to each clinic
/// and sorts the list nearest-first. If location is unavailable or permission is denied,
/// returns the standard unsorted list with distance_km = null.
final clinicsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final token = ref.watch(authTokenProvider);
  if (token == null) throw Exception('Not authenticated.');

  final service = ref.watch(appointmentServiceProvider);
  final rawClinics = await service.getClinics(idToken: token);

  final userPosition = await ref.watch(userLocationProvider.future);

  final enrichedClinics = rawClinics.map((clinic) {
    final copy = Map<String, dynamic>.from(clinic);
    final lat = (copy['latitude'] as num?)?.toDouble();
    final lng = (copy['longitude'] as num?)?.toDouble();

    if (userPosition != null && lat != null && lng != null) {
      final distanceInMeters = Geolocator.distanceBetween(
        userPosition.latitude,
        userPosition.longitude,
        lat,
        lng,
      );
      copy['distance_km'] = distanceInMeters / 1000.0;
    } else {
      copy['distance_km'] = null;
    }
    return copy;
  }).toList();

  if (userPosition != null) {
    enrichedClinics.sort((a, b) {
      final distA = a['distance_km'] as double?;
      final distB = b['distance_km'] as double?;
      if (distA != null && distB != null) {
        return distA.compareTo(distB);
      }
      if (distA != null) return -1;
      if (distB != null) return 1;
      return 0;
    });
  }

  return enrichedClinics;
});

/// Fetches doctors for the currently-selected clinic.
/// It watches bookingNotifierProvider to know which clinic was chosen.
/// When the user changes their clinic selection, Riverpod automatically
/// re-runs this provider to fetch the new doctor list — no manual refresh.
final doctorsForClinicProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final token = ref.watch(authTokenProvider);
  if (token == null) throw Exception('Not authenticated.');

  final selectedClinic =
      ref.watch(bookingNotifierProvider).selectedClinic;
  if (selectedClinic == null) return [];

  final clinicId = selectedClinic['id']?.toString() ?? '';
  if (clinicId.isEmpty) return [];

  final service = ref.watch(appointmentServiceProvider);
  return service.getDoctors(idToken: token, clinicId: clinicId);
});

/// Fetches all appointments for the logged-in patient from GET /api/appointments/me.
/// Falls back to Hive offline cache when network is unavailable.
final myAppointmentsProvider =
    FutureProvider.autoDispose<CachedResult<List<Map<String, dynamic>>>>((ref) async {
  final authState = ref.watch(authNotifierProvider);
  final token = authState.idToken;
  final patientId = authState.patientProfile?['id']?.toString() ??
      authState.patientProfile?['health_id']?.toString();

  if (patientId == null || patientId.isEmpty) {
    return const CachedResult(data: [], isOffline: false);
  }

  if (token == null) {
    final cached = LocalCacheService.getAppointments(patientId);
    if (cached != null) {
      return CachedResult(
        data: cached['data'] as List<Map<String, dynamic>>,
        isOffline: true,
        lastUpdated: cached['timestamp'] as DateTime?,
      );
    }
    throw Exception('Not authenticated.');
  }

  final service = ref.watch(appointmentServiceProvider);

  try {
    final liveAppointments = await service.getMyAppointments(idToken: token);
    await LocalCacheService.saveAppointments(patientId, liveAppointments);
    return CachedResult(
      data: liveAppointments,
      isOffline: false,
      lastUpdated: DateTime.now(),
    );
  } catch (e) {
    final cached = LocalCacheService.getAppointments(patientId);
    if (cached != null) {
      return CachedResult(
        data: cached['data'] as List<Map<String, dynamic>>,
        isOffline: true,
        lastUpdated: cached['timestamp'] as DateTime?,
      );
    }
    rethrow;
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// BookingState — the single source of truth for the wizard
// ─────────────────────────────────────────────────────────────────────────────

/// The status of the booking submission itself (Step 4 confirm action).
enum BookingStatus {
  idle,       // nothing happening
  loading,    // POST /api/appointments in flight
  success,    // 201 Created — show success dialog
  slotTaken,  // 409 Conflict — show "slot taken" warning
  error,      // any other network/server error
}

class BookingState {
  final int currentStep;
  final Map<String, dynamic>? selectedClinic;
  final Map<String, dynamic>? selectedDoctor;
  final DateTime? selectedDateTime;
  final BookingStatus status;
  final String? errorMessage;

  /// Filled once the booking succeeds. Can be used to display a reference
  /// number if your backend returns one (e.g., appointment['id']).
  final Map<String, dynamic>? confirmedBooking;

  const BookingState({
    this.currentStep = 0,
    this.selectedClinic,
    this.selectedDoctor,
    this.selectedDateTime,
    this.status = BookingStatus.idle,
    this.errorMessage,
    this.confirmedBooking,
  });

  BookingState copyWith({
    int? currentStep,
    Map<String, dynamic>? selectedClinic,
    Map<String, dynamic>? selectedDoctor,
    DateTime? selectedDateTime,
    BookingStatus? status,
    String? errorMessage,
    Map<String, dynamic>? confirmedBooking,
    bool clearDoctor = false,
    bool clearDateTime = false,
    bool clearError = false,
    bool clearConfirmed = false,
  }) {
    return BookingState(
      currentStep: currentStep ?? this.currentStep,
      selectedClinic: selectedClinic ?? this.selectedClinic,
      // When a new clinic is chosen we wipe the previously chosen doctor
      selectedDoctor: clearDoctor ? null : (selectedDoctor ?? this.selectedDoctor),
      selectedDateTime: clearDateTime ? null : (selectedDateTime ?? this.selectedDateTime),
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      confirmedBooking: clearConfirmed ? null : (confirmedBooking ?? this.confirmedBooking),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BookingNotifier — controls wizard step transitions and the submit action
// ─────────────────────────────────────────────────────────────────────────────

class BookingNotifier extends StateNotifier<BookingState> {
  final AppointmentService _service;
  final Ref _ref;

  BookingNotifier(this._service, this._ref) : super(const BookingState());

  // ── Step 0 → 1: Clinic chosen ─────────────────────────────────────────────

  void selectClinic(Map<String, dynamic> clinic) {
    state = state.copyWith(
      selectedClinic: clinic,
      currentStep: 1,
      // Wipe doctor and time when clinic changes so stale data isn't submitted
      clearDoctor: true,
      clearDateTime: true,
      clearError: true,
    );
  }

  // ── Step 1 → 2: Doctor chosen ─────────────────────────────────────────────

  void selectDoctor(Map<String, dynamic> doctor) {
    state = state.copyWith(
      selectedDoctor: doctor,
      currentStep: 2,
      clearDateTime: true,
      clearError: true,
    );
  }

  // ── Step 2: Date/time updated (doesn't advance step automatically) ─────────

  void selectDateTime(DateTime dt) {
    state = state.copyWith(selectedDateTime: dt, clearError: true);
  }

  // ── Step 2 → 3: User taps "Continue" after picking both date and time ──────

  void proceedToConfirm() {
    if (state.selectedDateTime == null) return;
    state = state.copyWith(currentStep: 3, clearError: true);
  }

  // ── Step 3: Submit the booking ────────────────────────────────────────────

  Future<void> confirmBooking() async {
    final token = _ref.read(authTokenProvider);
    if (token == null) {
      state = state.copyWith(
        status: BookingStatus.error,
        errorMessage: 'You are not authenticated. Please log in again.',
      );
      return;
    }

    final doctorId = state.selectedDoctor?['id']?.toString();
    final clinicId = state.selectedClinic?['id']?.toString();
    final dt = state.selectedDateTime;

    if (doctorId == null || clinicId == null || dt == null) {
      state = state.copyWith(
        status: BookingStatus.error,
        errorMessage: 'Incomplete selection — please go back and try again.',
      );
      return;
    }

    // Convert the local DateTime to UTC ISO-8601 (e.g. "2026-09-05T05:00:00.000Z")
    final slotTime = dt.toUtc().toIso8601String();

    state = state.copyWith(status: BookingStatus.loading, clearError: true);

    try {
      final result = await _service.bookAppointment(
        idToken: token,
        doctorId: doctorId,
        clinicId: clinicId,
        slotTime: slotTime,
      );
      state = state.copyWith(
        status: BookingStatus.success,
        confirmedBooking: result,
      );
      _ref.invalidate(myAppointmentsProvider);
    } on SlotTakenException {
      // 409 Conflict — specific, actionable message
      state = state.copyWith(
        status: BookingStatus.slotTaken,
        errorMessage:
            'This slot is already taken — please go back and choose a different time.',
      );
    } catch (e) {
      state = state.copyWith(
        status: BookingStatus.error,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  // ── Navigation helpers ─────────────────────────────────────────────────────

  /// Go back one step. Clears the submission status so any error/success
  /// banners disappear when re-entering a step.
  void goBack() {
    if (state.currentStep > 0) {
      state = state.copyWith(
        currentStep: state.currentStep - 1,
        status: BookingStatus.idle,
        clearError: true,
      );
    }
  }

  /// Completely reset the wizard (called after a successful booking so the
  /// next time the user opens the screen it starts fresh from step 0).
  void reset() {
    state = const BookingState();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Global provider
// ─────────────────────────────────────────────────────────────────────────────

// autoDispose: leaving the wizard mid-way must not resume a stale booking next time.
final bookingNotifierProvider =
    StateNotifierProvider.autoDispose<BookingNotifier, BookingState>((ref) {
  final service = ref.watch(appointmentServiceProvider);
  return BookingNotifier(service, ref);
});
