class AppUser {
  final int id;
  final String username;
  final String email;
  final bool isActive;
  final bool isAdmin;

  AppUser({
    required this.id,
    required this.username,
    required this.email,
    required this.isActive,
    required this.isAdmin,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] ?? 0,
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      isActive: json['is_active'] ?? true,
      isAdmin: json['is_admin'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'is_active': isActive,
      'is_admin': isAdmin,
    };
  }
}
