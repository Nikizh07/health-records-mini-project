import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/utils/poll.dart';
import '../data/services/consent_service.dart';
import 'auth_provider.dart';

final consentServiceProvider = Provider<ConsentService>((ref) => ConsentService());

String _token(Ref ref) {
  final token = ref.watch(authTokenProvider);
  if (token == null) throw Exception('User is not authenticated.');
  return token;
}

/// Requests waiting for the patient's answer. ConsentPopupHost watches this on
/// every signed-in page, so it is the one poll that is always running — it
/// stops with the browser tab (schedulePoll).
/// ponytail: 10 s polling, as the queue does; swap for FCM push if it costs too much.
final pendingConsentsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  schedulePoll(ref);
  return ref.watch(consentServiceProvider).pending(idToken: _token(ref));
});

/// One request the doctor is waiting on. Faster poll: someone is watching it.
final consentStatusProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, consentId) async {
  schedulePoll(ref, const Duration(seconds: 3));
  return ref.watch(consentServiceProvider).get(idToken: _token(ref), consentId: consentId);
});

/// The patient's own grants and access history (privacy screen).
final myConsentsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(consentServiceProvider).mine(idToken: _token(ref));
});

/// Clinic (or platform) access log, for audit:read.
final accessAuditProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(consentServiceProvider).accessAudit(idToken: _token(ref));
});
