/// Обёртка для API-ответа со статусом
class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? error;
  final int? statusCode;

  const ApiResponse({
    required this.success,
    this.data,
    this.error,
    this.statusCode,
  });

  /// Успешный ответ
  factory ApiResponse.ok(T data, {int? statusCode}) {
    return ApiResponse<T>(success: true, data: data, statusCode: statusCode);
  }

  /// Ответ с ошибкой
  factory ApiResponse.error(String error, {int? statusCode}) {
    return ApiResponse<T>(success: false, error: error, statusCode: statusCode);
  }
}

/// Модель ответа при отправке сообщения
class SendMessageResponse {
  final String id;
  final String status;

  const SendMessageResponse({required this.id, required this.status});

  factory SendMessageResponse.fromJson(Map<String, dynamic> json) {
    return SendMessageResponse(
      id: json['id'] as String,
      status: json['status'] as String,
    );
  }
}

/// Модель профиля пользователя
class UserProfile {
  final String name;
  final String address;
  final String? email;
  final DateTime? registeredAt;

  const UserProfile({
    required this.name,
    required this.address,
    this.email,
    this.registeredAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      name: json['name'] as String,
      address: json['address'] as String,
      email: json['email'] as String?,
      registeredAt: json['registered_at'] != null
          ? DateTime.parse(json['registered_at'] as String)
          : null,
    );
  }
}
