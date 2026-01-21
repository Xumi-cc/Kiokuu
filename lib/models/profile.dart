/// Represents a user profile (main account or sub-profile)
class Profile {
  final String id;
  final String username;
  final String? photoUrl;
  final String color;
  final bool isOwner;

  Profile({
    required this.id,
    required this.username,
    this.photoUrl,
    required this.color,
    required this.isOwner,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      username: json['username'] as String,
      photoUrl: json['photo_url'] as String?,
      color: json['color'] as String? ?? 'blue',
      isOwner: json['is_owner'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'photo_url': photoUrl,
      'color': color,
      'is_owner': isOwner,
    };
  }

  /// Get the color as a Flutter Color
  static const Map<String, int> colorMap = {
    'blue': 0xFF4A90D9,
    'purple': 0xFF9B59B6,
    'green': 0xFF27AE60,
    'orange': 0xFFE67E22,
    'pink': 0xFFE91E63,
    'red': 0xFFE74C3C,
    'teal': 0xFF1ABC9C,
    'indigo': 0xFF3F51B5,
  };

  int get colorValue => colorMap[color] ?? colorMap['blue']!;
}
