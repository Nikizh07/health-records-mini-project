import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/models/cached_result.dart';
import '../data/services/local_cache_service.dart';
import '../data/services/record_service.dart';
import 'auth_provider.dart';

final recordServiceProvider = Provider<RecordService>((ref) {
  return RecordService();
});

/// Fetches medical history for the currently logged-in patient with offline caching fallback.
final patientRecordsProvider =
    FutureProvider.autoDispose<CachedResult<List<Map<String, dynamic>>>>((ref) async {
  // ponytail: 10s polling so new doctor records show up; push later if needed.
  final poll = Timer(const Duration(seconds: 10), ref.invalidateSelf);
  ref.onDispose(poll.cancel);

  final authState = ref.watch(authNotifierProvider);
  final token = authState.idToken;
  final patientId = authState.patientProfile?['id']?.toString() ??
      authState.patientProfile?['health_id']?.toString();

  if (patientId == null || patientId.isEmpty) {
    return const CachedResult(data: [], isOffline: false);
  }

  // 1. If not authenticated online, check offline cache
  if (token == null) {
    final cached = LocalCacheService.getRecords(patientId);
    if (cached != null) {
      return CachedResult(
        data: cached['data'] as List<Map<String, dynamic>>,
        isOffline: true,
        lastUpdated: cached['timestamp'] as DateTime?,
      );
    }
    return const CachedResult(data: [], isOffline: false);
  }

  final recordService = ref.watch(recordServiceProvider);

  try {
    // 2. Attempt live API fetch
    final liveRecords = await recordService.getPatientRecords(
      idToken: token,
      patientId: patientId,
    );

    // 3. Cache to local Hive storage
    await LocalCacheService.saveRecords(patientId, liveRecords);

    return CachedResult(
      data: liveRecords,
      isOffline: false,
      lastUpdated: DateTime.now(),
    );
  } catch (e) {
    // 4. On network error / timeout, fall back to offline cache
    final cached = LocalCacheService.getRecords(patientId);
    if (cached != null) {
      return CachedResult(
        data: cached['data'] as List<Map<String, dynamic>>,
        isOffline: true,
        lastUpdated: cached['timestamp'] as DateTime?,
      );
    }

    // If no cached data exists, rethrow so UI displays friendly AppErrorView
    rethrow;
  }
});

/// Fetches a single record by ID (if not passed in router extra)
final singleRecordProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, recordId) async {
  final authState = ref.watch(authNotifierProvider);
  final token = authState.idToken;

  if (token == null) {
    throw Exception('User is not authenticated.');
  }

  final recordService = ref.watch(recordServiceProvider);
  return await recordService.getRecordById(
    idToken: token,
    recordId: recordId,
  );
});
