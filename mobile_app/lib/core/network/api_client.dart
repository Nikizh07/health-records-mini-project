import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/app_constants.dart';

/// Shared Dio client for every API service.
///
/// Firebase ID tokens expire after 1 hour, but the app captures one at login.
/// This interceptor swaps the Authorization header for a current token on each
/// request. getIdToken() returns the cached token until it is near expiry, so
/// this costs nothing in the common case.
Dio createApiClient() {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConstants.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && options.headers.containsKey('Authorization')) {
          try {
            final token = await user.getIdToken();
            if (token != null) options.headers['Authorization'] = 'Bearer $token';
          } catch (_) {
            // Offline refresh failed: send the old token; callers fall back to cache.
          }
        }
        handler.next(options);
      },
    ),
  );

  return dio;
}
