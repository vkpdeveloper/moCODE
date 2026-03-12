import 'package:dio/dio.dart';

import '../models/api_error.dart';

/// Utility class for parsing and handling API errors.
class ErrorHandler {
  ErrorHandler._();

  /// Parse a DioException into a user-friendly ApiError.
  static ApiError parseError(Object error) {
    if (error is DioException) {
      return _parseDioException(error);
    }

    if (error is ApiError) {
      return error;
    }

    return ApiError(type: ApiErrorType.unknown, message: error.toString());
  }

  static ApiError _parseDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
        return const ApiError(
          type: ApiErrorType.connection,
          message: 'Unable to connect to server',
          details:
              'Please check that the moCODE CLI is running and the host/port settings are correct.',
        );

      case DioExceptionType.connectionTimeout:
        return const ApiError(
          type: ApiErrorType.timeout,
          message: 'Connection timed out',
          details:
              'The server took too long to respond. Please check your network connection.',
        );

      case DioExceptionType.sendTimeout:
        return const ApiError(
          type: ApiErrorType.timeout,
          message: 'Request timed out',
          details: 'The request took too long to send. Please try again.',
        );

      case DioExceptionType.receiveTimeout:
        return const ApiError(
          type: ApiErrorType.timeout,
          message: 'Server took too long to respond',
          details: 'The server is taking too long. Please try again later.',
        );

      case DioExceptionType.badResponse:
        return _parseHttpError(e);

      case DioExceptionType.cancel:
        return const ApiError(
          type: ApiErrorType.unknown,
          message: 'Request cancelled',
        );

      case DioExceptionType.badCertificate:
        return const ApiError(
          type: ApiErrorType.connection,
          message: 'Certificate error',
          details:
              'There was a problem with the server certificate. Please check your connection.',
        );

      case DioExceptionType.unknown:
        // Check for common socket exceptions
        final errorMsg = e.error?.toString().toLowerCase() ?? '';
        if (errorMsg.contains('connection refused') ||
            errorMsg.contains('no route to host') ||
            errorMsg.contains('network is unreachable') ||
            errorMsg.contains('socket')) {
          return const ApiError(
            type: ApiErrorType.connection,
            message: 'Unable to connect to server',
            details:
                'Please check that the moCODE CLI is running and the host/port settings are correct.',
          );
        }
        return ApiError(
          type: ApiErrorType.unknown,
          message: e.message ?? 'An unexpected error occurred',
          details: e.error?.toString(),
        );
    }
  }

  static ApiError _parseHttpError(DioException e) {
    final statusCode = e.response?.statusCode;
    final data = e.response?.data;

    switch (statusCode) {
      case 400:
        // Try to parse BadRequestError
        if (data is Map<String, dynamic>) {
          try {
            return BadRequestApiError.fromJson(data);
          } catch (_) {
            // Fall through to default handling
          }
        }
        return ApiError(
          type: ApiErrorType.badRequest,
          message: _extractMessage(data) ?? 'Invalid request',
          rawData: data,
          statusCode: 400,
        );

      case 401:
      case 403:
        return ApiError(
          type: ApiErrorType.unauthorized,
          message: statusCode == 401 ? 'Unauthorized' : 'Access denied',
          details: _extractMessage(data),
          rawData: data,
          statusCode: statusCode,
        );

      case 404:
        // Try to parse NotFoundError
        if (data is Map<String, dynamic>) {
          try {
            return NotFoundApiError.fromJson(data);
          } catch (_) {
            // Fall through to default handling
          }
        }
        return ApiError(
          type: ApiErrorType.notFound,
          message: _extractMessage(data) ?? 'Resource not found',
          rawData: data,
          statusCode: 404,
        );

      case 500:
      case 502:
      case 503:
      case 504:
        return ApiError(
          type: ApiErrorType.serverError,
          message: 'Server error',
          details: _getServerErrorDetails(statusCode),
          rawData: data,
          statusCode: statusCode,
        );

      default:
        return ApiError(
          type: ApiErrorType.unknown,
          message: _extractMessage(data) ?? 'Request failed',
          details: statusCode != null ? 'HTTP $statusCode' : null,
          rawData: data,
          statusCode: statusCode,
        );
    }
  }

  static String? _extractMessage(dynamic data) {
    if (data == null) return null;
    if (data is String) return data;

    if (data is Map<String, dynamic>) {
      // Try common message fields
      if (data.containsKey('message')) return data['message']?.toString();
      if (data.containsKey('error')) return data['error']?.toString();
      if (data.containsKey('msg')) return data['msg']?.toString();

      // For NotFoundError format
      if (data.containsKey('data') && data['data'] is Map) {
        final innerData = data['data'] as Map;
        if (innerData.containsKey('message')) {
          return innerData['message']?.toString();
        }
      }

      // For BadRequestError format
      if (data.containsKey('errors') && data['errors'] is List) {
        final errors = data['errors'] as List;
        if (errors.isNotEmpty && errors.first is Map) {
          final first = errors.first as Map;
          if (first.containsKey('message')) {
            return first['message']?.toString();
          }
        }
      }
    }

    return null;
  }

  static String _getServerErrorDetails(int? statusCode) {
    switch (statusCode) {
      case 500:
        return 'Internal server error. Please try again later.';
      case 502:
        return 'Bad gateway. The server may be temporarily unavailable.';
      case 503:
        return 'Service unavailable. Please try again later.';
      case 504:
        return 'Gateway timeout. The server took too long to respond.';
      default:
        return 'An unexpected server error occurred.';
    }
  }
}
