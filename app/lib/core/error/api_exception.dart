import 'package:dio/dio.dart';

/// 서버 오류 envelope {code, message, details, request_id}를 그대로 담는 예외.
/// 네트워크 계층 실패도 같은 타입으로 정규화해서 화면에서는 message만 보여주면 된다.
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.details = const {},
    this.requestId,
  });

  final String code;
  final String message;
  final int? statusCode;
  final Map<String, dynamic> details;
  final String? requestId;

  factory ApiException.from(Object error) {
    if (error is ApiException) return error;
    if (error is! DioException) {
      return const ApiException(
        code: 'UNKNOWN',
        message: '알 수 없는 오류가 발생했어요. 잠시 후 다시 시도해 주세요.',
      );
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const ApiException(
          code: 'TIMEOUT',
          message: '서버 응답이 늦어지고 있어요. 잠시 후 다시 시도해 주세요.',
        );
      case DioExceptionType.connectionError:
        return const ApiException(
          code: 'NETWORK_ERROR',
          message: '서버에 연결할 수 없어요. 네트워크 상태를 확인해 주세요.',
        );
      case DioExceptionType.cancel:
        return const ApiException(
          code: 'REQUEST_CANCELLED',
          message: '요청이 취소되었어요.',
        );
      case DioExceptionType.badResponse:
        return _fromResponse(error.response);
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return const ApiException(
          code: 'NETWORK_ERROR',
          message: '서버에 연결할 수 없어요. 네트워크 상태를 확인해 주세요.',
        );
    }
  }

  static ApiException _fromResponse(Response<dynamic>? response) {
    final status = response?.statusCode;
    final body = response?.data;
    if (body is Map<String, dynamic> && body['code'] is String) {
      return ApiException(
        code: body['code'] as String,
        message: (body['message'] as String?) ?? '요청을 처리하지 못했어요.',
        statusCode: status,
        details: (body['details'] as Map<String, dynamic>?) ?? const {},
        requestId: body['request_id'] as String?,
      );
    }
    return ApiException(
      code: 'HTTP_${status ?? 0}',
      message: '요청을 처리하지 못했어요. (HTTP ${status ?? '?'})',
      statusCode: status,
    );
  }

  @override
  String toString() => 'ApiException($code, $statusCode): $message';
}

/// repository 계층 공통 래퍼. Dio 예외를 ApiException으로 바꿔 던진다.
Future<T> guardApi<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on ApiException {
    rethrow;
  } catch (e) {
    throw ApiException.from(e);
  }
}
