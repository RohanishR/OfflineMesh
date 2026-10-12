class UserProfile {
  final String? id;
  final String username;
  final String? email;
  final String offlineMeshId;

  UserProfile({
    this.id,
    required this.username,
    this.email,
    required this.offlineMeshId,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id']?.toString(),
      username: json['username'],
      email: json['email'],
      offlineMeshId: json['offlineMeshId'],
    );
  }
}
