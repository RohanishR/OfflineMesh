class GroupMemberModel {
  final String offlineMeshId;
  final String username;
  final String role;
  final DateTime joinedAt;

  const GroupMemberModel({
    required this.offlineMeshId,
    required this.username,
    required this.role,
    required this.joinedAt,
  });

  bool get isAdmin => role.toUpperCase() == 'ADMIN';

  factory GroupMemberModel.fromJson(Map<String, dynamic> json) {
    return GroupMemberModel(
      offlineMeshId: json['offlineMeshId']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      role: json['role']?.toString() ?? 'MEMBER',
      joinedAt: json['joinedAt'] != null
          ? DateTime.tryParse(json['joinedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'offlineMeshId': offlineMeshId,
      'username': username,
      'role': role,
      'joinedAt': joinedAt.toIso8601String(),
    };
  }
}

class GroupChat {
  final String id;
  final String name;
  final String? description;
  final String createdByOfflineMeshId;
  final DateTime createdAt;
  final List<GroupMemberModel> members;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;

  const GroupChat({
    required this.id,
    required this.name,
    this.description,
    required this.createdByOfflineMeshId,
    required this.createdAt,
    this.members = const [],
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
  });

  factory GroupChat.fromJson(Map<String, dynamic> json) {
    var rawMembers = json['members'];
    List<GroupMemberModel> memberList = [];
    if (rawMembers is List) {
      memberList = rawMembers
          .map((m) => GroupMemberModel.fromJson(m as Map<String, dynamic>))
          .toList();
    }

    return GroupChat(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Group',
      description: json['description']?.toString(),
      createdByOfflineMeshId: json['createdByOfflineMeshId']?.toString() ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      members: memberList,
      lastMessage: json['lastMessage']?.toString(),
      lastMessageTime: json['lastMessageTime'] != null
          ? DateTime.tryParse(json['lastMessageTime'].toString())
          : null,
      unreadCount: json['unreadCount'] is num ? (json['unreadCount'] as num).toInt() : 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (description != null) 'description': description,
      'createdByOfflineMeshId': createdByOfflineMeshId,
      'createdAt': createdAt.toIso8601String(),
      'members': members.map((m) => m.toJson()).toList(),
      if (lastMessage != null) 'lastMessage': lastMessage,
      if (lastMessageTime != null) 'lastMessageTime': lastMessageTime!.toIso8601String(),
      'unreadCount': unreadCount,
    };
  }

  GroupChat copyWith({
    String? id,
    String? name,
    String? description,
    String? createdByOfflineMeshId,
    DateTime? createdAt,
    List<GroupMemberModel>? members,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
  }) {
    return GroupChat(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdByOfflineMeshId: createdByOfflineMeshId ?? this.createdByOfflineMeshId,
      createdAt: createdAt ?? this.createdAt,
      members: members ?? this.members,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}
