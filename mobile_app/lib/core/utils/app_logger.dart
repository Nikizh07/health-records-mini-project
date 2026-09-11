import 'package:flutter/foundation.dart';

/// A centralized, release-safe logger for the app.
///
/// Why this exists:
/// - `print()` and `debugPrint()` output to the device console even in release builds.
///   On Android this means `adb logcat` can expose JWT tokens, phone numbers, and
///   health record data to anyone with a USB cable — a serious security risk for
///   a health app handling sensitive migrant worker data.
///
/// - This wrapper gates ALL logging behind [kDebugMode], which evaluates to `false`
///   at compile time in `--release` builds. The Dart tree-shaker then eliminates
///   the log bodies entirely from the production binary — zero overhead, zero leaks.
///
/// Usage:
///   AppLogger.debug('Clinic list loaded: ${clinics.length} items');
///   AppLogger.warn('Token missing — redirecting to login');
///   AppLogger.error('Auth error', error: e, stackTrace: st);
///
/// DO NOT use:
///   print(token)          // ← visible in release builds
///   debugPrint(profile)   // ← same problem
class AppLogger {
  AppLogger._(); // prevent instantiation

  /// Logs a general debug/info message. No-op in release builds.
  static void debug(String message) {
    if (kDebugMode) {
      debugPrint('[DEBUG] $message');
    }
  }

  /// Logs a warning. No-op in release builds.
  static void warn(String message) {
    if (kDebugMode) {
      debugPrint('[WARN]  $message');
    }
  }

  /// Logs an error with optional stack trace. No-op in release builds.
  static void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (kDebugMode) {
      debugPrint('[ERROR] $message');
      if (error != null) debugPrint('        ↳ $error');
      if (stackTrace != null) debugPrint('        ↳ $stackTrace');
    }
  }
}
