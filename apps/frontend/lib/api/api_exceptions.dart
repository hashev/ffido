import 'package:grpc/grpc_or_grpcweb.dart' show StatusCode;

class ApiException implements Exception {
  final String message;
  final int statusCode;
  final String rpcName;
  const ApiException({
    required this.message,
    required this.statusCode,
    this.rpcName = "",
  });
  bool get isAccessDenied => statusCode == StatusCode.permissionDenied;
  bool get allowsCacheFallback =>
      statusCode == StatusCode.unavailable ||
      statusCode == StatusCode.deadlineExceeded;
  // Only these business rejections prove that this CreateMessage did not commit.
  // INTERNAL/UNKNOWN may occur after the durable intent or while returning its result.
  bool get hasUncertainCommit => !const {
    StatusCode.invalidArgument,
    StatusCode.notFound,
    StatusCode.alreadyExists,
    StatusCode.permissionDenied,
    StatusCode.failedPrecondition,
    StatusCode.unauthenticated,
  }.contains(statusCode);
  @override
  String toString() => message;
}

class NetworkException extends ApiException {
  final Object? originalError;
  const NetworkException({
    super.message = 'Сервер недоступен',
    super.rpcName,
    this.originalError,
  }) : super(statusCode: StatusCode.unavailable);
}

class UnauthorizedException extends ApiException {
  const UnauthorizedException({
    super.message = 'Войдите с FTN-адресом и паролем',
    super.rpcName,
  }) : super(statusCode: StatusCode.unauthenticated);
}

class NotFoundException extends ApiException {
  const NotFoundException({super.message = 'Ресурс не найден', super.rpcName})
    : super(statusCode: StatusCode.notFound);
}

class ServerException extends ApiException {
  const ServerException({
    super.message = 'Ошибка сервера',
    super.rpcName,
    super.statusCode = StatusCode.internal,
  });
}

class ValidationException extends ApiException {
  final Map<String, List<String>> fieldErrors;
  const ValidationException({
    super.message = 'Проверьте введённые данные',
    super.rpcName,
    this.fieldErrors = const {},
  }) : super(statusCode: StatusCode.invalidArgument);
}

class DeadlineException extends ApiException {
  const DeadlineException({super.rpcName})
    : super(
        message: 'Превышено время ожидания',
        statusCode: StatusCode.deadlineExceeded,
      );
}

class CancelledException extends ApiException {
  const CancelledException({super.rpcName})
    : super(message: 'Запрос отменён', statusCode: StatusCode.cancelled);
}
