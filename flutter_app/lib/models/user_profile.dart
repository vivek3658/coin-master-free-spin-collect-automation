class UserProfile {
  final String id;
  final String name;
  final String gamePlayerId;
  final bool isActive;
  final DateTime createdAt;

  const UserProfile({
    required this.id,
    required this.name,
    this.gamePlayerId = '',
    this.isActive = true,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'gamePlayerId': gamePlayerId,
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'User',
      gamePlayerId: json['gamePlayerId'] as String? ?? '',
      isActive: json['isActive'] as bool? ?? true,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
