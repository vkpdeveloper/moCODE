/// Represents a parsed API error with user-friendly information.
class ApiError {
  /// Type of error (e.g., 'connection', 'timeout', 'badRequest', 'notFound', 'unknown')
  final ApiErrorType type;

  /// User-friendly error message
  final String message;

  /// Optional detailed information about the error
  final String? details;

  /// Original error data from the API response
  final dynamic rawData;

  /// HTTP status code if applicable
  final int? statusCode;

  const ApiError({
    required this.type,
    required this.message,
    this.details,
    this.rawData,
    this.statusCode,
  });

  /// Whether this is a connection-related error (server unreachable)
  bool get isConnectionError =>
      type == ApiErrorType.connection || type == ApiErrorType.timeout;

  /// Whether the user should be prompted to configure the server
  bool get shouldShowConfigure => isConnectionError;

  @override
  String toString() => message;
}

/// Types of API errors
enum ApiErrorType {
  /// Connection refused or server unreachable
  connection,

  /// Connection or receive timeout
  timeout,

  /// HTTP 400 - Bad Request
  badRequest,

  /// HTTP 404 - Not Found
  notFound,

  /// HTTP 401/403 - Unauthorized/Forbidden
  unauthorized,

  /// HTTP 500+ - Server Error
  serverError,

  /// Unknown or unhandled error
  unknown,
}

/// Parsed BadRequestError from API
/// Schema: { data: any, errors: [{ ... }], success: false }
class BadRequestApiError extends ApiError {
  final List<Map<String, dynamic>> errors;
  final dynamic data;

  BadRequestApiError({required this.errors, this.data, String? details})
    : super(
        type: ApiErrorType.badRequest,
        message: _extractMessage(errors) ?? 'Invalid request',
        details: details,
        rawData: {'data': data, 'errors': errors, 'success': false},
        statusCode: 400,
      );

  static String? _extractMessage(List<Map<String, dynamic>> errors) {
    if (errors.isEmpty) return null;
    final first = errors.first;
    // Try common fields for error message
    if (first.containsKey('message')) return first['message']?.toString();
    if (first.containsKey('msg')) return first['msg']?.toString();
    if (first.containsKey('error')) return first['error']?.toString();
    // Return first value if it's a simple key-value error
    if (first.values.isNotEmpty) {
      final val = first.values.first;
      if (val is String) return val;
    }
    return null;
  }

  factory BadRequestApiError.fromJson(Map<String, dynamic> json) {
    final errorsRaw = json['errors'];
    final errors = <Map<String, dynamic>>[];
    if (errorsRaw is List) {
      for (final e in errorsRaw) {
        if (e is Map<String, dynamic>) {
          errors.add(e);
        } else if (e is Map) {
          errors.add(Map<String, dynamic>.from(e));
        }
      }
    }
    return BadRequestApiError(errors: errors, data: json['data']);
  }
}

/// Parsed NotFoundError from API
/// Schema: { name: "NotFoundError", data: { message: string } }
class NotFoundApiError extends ApiError {
  NotFoundApiError({required String message, dynamic rawData})
    : super(
        type: ApiErrorType.notFound,
        message: message,
        rawData: rawData,
        statusCode: 404,
      );

  factory NotFoundApiError.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    String message = 'Resource not found';
    if (data is Map<String, dynamic> && data.containsKey('message')) {
      message = data['message']?.toString() ?? message;
    }
    return NotFoundApiError(message: message, rawData: json);
  }
}
