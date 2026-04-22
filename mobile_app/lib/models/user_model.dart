class UserModel {
  const UserModel({
    required this.id,
    required this.fullName,
    required this.email,
    this.role,
    this.createdAt,
  });

  final int id;
  final String fullName;
  final String email;
  final String? role;
  final DateTime? createdAt;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as int,
      fullName: json['full_name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: json['role'] as String?,
      createdAt: _parseDateTime(json['created_at']),
    );
  }
}

class AuthResponse {
  const AuthResponse({
    required this.message,
    required this.user,
  });

  final String message;
  final UserModel user;

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      message: json['message'] as String? ?? '',
      user: UserModel.fromJson(Map<String, dynamic>.from(json['user'] as Map)),
    );
  }
}

DateTime? _parseDateTime(dynamic value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}
