import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/admin_service.dart';
import 'auth_provider.dart';

final adminServiceProvider = Provider<AdminService>((ref) {
  return AdminService();
});

/// Fetches the full directory of registered doctors for Admin
final adminDoctorsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final token = ref.watch(authTokenProvider);
  if (token == null) throw Exception('User is not authenticated.');

  final service = ref.watch(adminServiceProvider);
  return service.getAllDoctors(idToken: token);
});

/// Fetches clinics for Admin management
final adminClinicsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final token = ref.watch(authTokenProvider);
  if (token == null) throw Exception('User is not authenticated.');

  final service = ref.watch(adminServiceProvider);
  return service.getAllClinics(idToken: token);
});
