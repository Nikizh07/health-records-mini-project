import 'package:flutter/foundation.dart';

class AppConstants {
  static const String appName = 'Migrant Worker Health Hub';

  /// Base API URL for backend network requests.
  /// Defaults to local development endpoint, but can be overridden at build/run time via:
  /// `--dart-define=API_BASE_URL=https://your-cloud-run-service.a.run.app/api`
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000/api',
  );

  /// Enforces that release builds cannot point to an insecure cleartext HTTP URL.
  /// Throws a [StateError] if a production build is compiled without an HTTPS endpoint.
  static void validateNetworkSecurity() {
    if (kReleaseMode && !apiBaseUrl.startsWith('https://')) {
      throw StateError(
        'SECURITY VIOLATION: Production release builds must connect to an HTTPS endpoint. '
        'Active apiBaseUrl is "$apiBaseUrl". '
        'Provide a production HTTPS URL using --dart-define=API_BASE_URL=https://...',
      );
    }
  }

  // Storage & Preference keys placeholder
  static const String authTokenKey = 'auth_token';
}
