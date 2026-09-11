import 'dart:convert';
import 'dart:typed_data';
import 'package:hive_flutter/hive_flutter.dart';

/// Lightweight local storage service using Hive.
/// Caches API responses with timestamps for offline-first support.
class LocalCacheService {
  static const String _boxName = 'offline_health_cache';
  static const String _recordsPrefix = 'records_';
  static const String _appointmentsPrefix = 'appointments_';

  static Box? _box;

  /// Initializes Hive and opens the persistent storage box.
  /// Called in main() during app startup.
  /// [inMemory] is for tests: no disk, no path_provider plugin.
  static Future<void> init({bool inMemory = false}) async {
    if (inMemory) {
      _box = await Hive.openBox(_boxName, bytes: Uint8List(0));
      return;
    }
    await Hive.initFlutter();
    _box = await Hive.openBox(_boxName);
  }

  static Box get _activeBox {
    if (_box == null || !_box!.isOpen) {
      throw Exception('LocalCacheService has not been initialized. Call LocalCacheService.init() in main().');
    }
    return _box!;
  }

  // ─────────────────────────────────────────────────────────────
  // HEALTH RECORDS CACHING
  // ─────────────────────────────────────────────────────────────

  /// Cache medical records for a specific patient with a timestamp.
  static Future<void> saveRecords(String patientId, List<Map<String, dynamic>> records) async {
    final payload = {
      'data': records,
      'timestamp': DateTime.now().toIso8601String(),
    };
    await _activeBox.put('$_recordsPrefix$patientId', jsonEncode(payload));
  }

  /// Retrieve cached medical records and the last-updated timestamp.
  static Map<String, dynamic>? getRecords(String patientId) {
    final raw = _activeBox.get('$_recordsPrefix$patientId');
    if (raw == null) return null;

    try {
      final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
      final list = (decoded['data'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      final timestamp = DateTime.tryParse(decoded['timestamp']?.toString() ?? '');

      return {
        'data': list,
        'timestamp': timestamp,
      };
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // PROFILE CACHING (lets a signed-in user reopen the app offline)
  // ─────────────────────────────────────────────────────────────

  static const String _profileKey = 'profile';

  static Future<void> saveProfile(Map<String, dynamic> profile) =>
      _activeBox.put(_profileKey, jsonEncode(profile));

  static Map<String, dynamic>? getProfile() {
    final raw = _activeBox.get(_profileKey);
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw as String) as Map);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearProfile() => _activeBox.delete(_profileKey);

  // ─────────────────────────────────────────────────────────────
  // APPOINTMENTS CACHING
  // ─────────────────────────────────────────────────────────────

  /// Cache appointments for a patient with a timestamp.
  static Future<void> saveAppointments(String patientId, List<Map<String, dynamic>> appointments) async {
    final payload = {
      'data': appointments,
      'timestamp': DateTime.now().toIso8601String(),
    };
    await _activeBox.put('$_appointmentsPrefix$patientId', jsonEncode(payload));
  }

  /// Retrieve cached appointments and the last-updated timestamp.
  static Map<String, dynamic>? getAppointments(String patientId) {
    final raw = _activeBox.get('$_appointmentsPrefix$patientId');
    if (raw == null) return null;

    try {
      final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
      final list = (decoded['data'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      final timestamp = DateTime.tryParse(decoded['timestamp']?.toString() ?? '');

      return {
        'data': list,
        'timestamp': timestamp,
      };
    } catch (_) {
      return null;
    }
  }
}
