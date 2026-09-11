import 'dart:io';
import 'package:dio/dio.dart';

/// Standard application-level exception for API and network failures.
/// Translates low-level network errors, timeouts, and HTTP status codes into
/// clean, user-friendly messages for the UI.
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  /// Factory constructor to convert a [DioException] into a human-friendly [ApiException].
  factory ApiException.fromDioException(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException(
          'Connection timed out. Please check your internet connection and try again.',
          statusCode: 408,
        );

      case DioExceptionType.connectionError:
        return ApiException(
          "Can't reach the server. Please check your internet connection and verify the backend is running.",
          statusCode: 503,
        );

      case DioExceptionType.badCertificate:
        return ApiException(
          'Security certificate verification failed. Please try again later.',
        );

      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        final dynamic data = error.response?.data;

        // Try extracting user-friendly message from backend JSON response if available
        String? backendMessage;
        if (data is Map<String, dynamic>) {
          backendMessage = data['message']?.toString();
        }

        if (backendMessage != null && backendMessage.trim().isNotEmpty) {
          return ApiException(backendMessage, statusCode: statusCode);
        }

        // Fallback friendly message based on standard HTTP status codes
        switch (statusCode) {
          case 400:
            return ApiException('Bad request. Please verify your input.', statusCode: 400);
          case 401:
            return ApiException('Session expired. Please log in again.', statusCode: 401);
          case 403:
            return ApiException('You do not have permission to perform this action.', statusCode: 403);
          case 404:
            return ApiException('Requested resource was not found.', statusCode: 404);
          case 409:
            return ApiException('A conflict occurred. This record or slot may already exist.', statusCode: 409);
          case 500:
          case 502:
          case 503:
          case 504:
            return ApiException('Server is temporarily unavailable. Please try again shortly.', statusCode: statusCode);
          default:
            return ApiException('Unexpected error occurred (${statusCode ?? 'unknown'}). Please try again.', statusCode: statusCode);
        }

      case DioExceptionType.cancel:
        return ApiException('Request was cancelled.');

      case DioExceptionType.unknown:
      default:
        if (error.error is SocketException) {
          return ApiException(
            "Can't reach the server. Please check your internet connection.",
            statusCode: 503,
          );
        }
        return ApiException('An unexpected network error occurred. Please try again.');
    }
  }

  @override
  String toString() => message;
}
