import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/admin_service.dart';
import '../data/services/staff_service.dart';
import 'auth_provider.dart';

final adminServiceProvider = Provider<AdminService>((ref) {
  return AdminService();
});

final staffServiceProvider = Provider<StaffService>((ref) => StaffService());

/// Staff accounts the caller manages (own clinic for a clinic admin).
final staffListProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final token = ref.watch(authTokenProvider);
  if (token == null) throw Exception('User is not authenticated.');
  return ref.watch(staffServiceProvider).listStaff(idToken: token);
});

final staffInvitesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final token = ref.watch(authTokenProvider);
  if (token == null) throw Exception('User is not authenticated.');
  return ref.watch(staffServiceProvider).listInvites(idToken: token);
});

/// Fetches clinics for Admin management
final adminClinicsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final token = ref.watch(authTokenProvider);
  if (token == null) throw Exception('User is not authenticated.');

  final service = ref.watch(adminServiceProvider);
  return service.getAllClinics(idToken: token);
});
