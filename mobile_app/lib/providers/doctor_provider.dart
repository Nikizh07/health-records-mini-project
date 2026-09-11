import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'appointment_provider.dart';
import 'auth_provider.dart';

/// Filter state for selected date in Doctor's view (defaults to today)
final doctorSelectedDateProvider = StateProvider.autoDispose<DateTime>((ref) {
  return DateTime.now();
});

/// Filter state for appointment status in Doctor's view (null = All)
final doctorStatusFilterProvider = StateProvider.autoDispose<String?>((ref) {
  return null;
});

/// Fetches appointments for the logged-in doctor on the selected date
final doctorTodayAppointmentsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  // ponytail: 10s polling while the queue is open; swap for FCM/websocket push if load matters.
  final poll = Timer(const Duration(seconds: 10), ref.invalidateSelf);
  ref.onDispose(poll.cancel);

  final token = ref.watch(authTokenProvider);
  if (token == null) throw Exception('User is not authenticated.');

  final selectedDate = ref.watch(doctorSelectedDateProvider);
  final status = ref.watch(doctorStatusFilterProvider);
  final service = ref.watch(appointmentServiceProvider);

  // Format date as YYYY-MM-DD
  final year = selectedDate.year.toString().padLeft(4, '0');
  final month = selectedDate.month.toString().padLeft(2, '0');
  final day = selectedDate.day.toString().padLeft(2, '0');
  final dateStr = '$year-$month-$day';

  return service.getDoctorAppointments(
    idToken: token,
    date: dateStr,
    status: status,
  );
});
