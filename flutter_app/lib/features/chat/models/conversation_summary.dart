class ConversationSummary {
  final String peerOfflineMeshId;
  final String peerUsername;
  final String lastMessage;
  final String lastMessageSenderId;
  final String lastMessageStatus; // sending, queued, sent, delivered, read
  final DateTime lastMessageTime;
  final int unreadCount;
  final bool isPinned;
  final bool isArchived;
  final bool isMuted;
  final bool isFromMe;
  final bool isEdited;
  final bool isDeleted;
  final String mediaType; // 'text', 'audio', 'image', 'file'
  final bool isGroup;
  final String? groupId;

  const ConversationSummary({
    required this.peerOfflineMeshId,
    required this.peerUsername,
    required this.lastMessage,
    required this.lastMessageSenderId,
    required this.lastMessageStatus,
    required this.lastMessageTime,
    this.unreadCount = 0,
    this.isPinned = false,
    this.isArchived = false,
    this.isMuted = false,
    this.isFromMe = false,
    this.isEdited = false,
    this.isDeleted = false,
    this.mediaType = 'text',
    this.isGroup = false,
    this.groupId,
  });

  ConversationSummary copyWith({
    String? peerOfflineMeshId,
    String? peerUsername,
    String? lastMessage,
    String? lastMessageSenderId,
    String? lastMessageStatus,
    DateTime? lastMessageTime,
    int? unreadCount,
    bool? isPinned,
    bool? isArchived,
    bool? isMuted,
    bool? isFromMe,
    bool? isEdited,
    bool? isDeleted,
    String? mediaType,
    bool? isGroup,
    String? groupId,
  }) {
    return ConversationSummary(
      peerOfflineMeshId: peerOfflineMeshId ?? this.peerOfflineMeshId,
      peerUsername: peerUsername ?? this.peerUsername,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      lastMessageStatus: lastMessageStatus ?? this.lastMessageStatus,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      isPinned: isPinned ?? this.isPinned,
      isArchived: isArchived ?? this.isArchived,
      isMuted: isMuted ?? this.isMuted,
      isFromMe: isFromMe ?? this.isFromMe,
      isEdited: isEdited ?? this.isEdited,
      isDeleted: isDeleted ?? this.isDeleted,
      mediaType: mediaType ?? this.mediaType,
      isGroup: isGroup ?? this.isGroup,
      groupId: groupId ?? this.groupId,
    );
  }

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    return ConversationSummary(
      peerOfflineMeshId: json['otherOfflineMeshId']?.toString() ?? json['peerOfflineMeshId']?.toString() ?? '',
      peerUsername: json['otherUsername']?.toString() ?? json['peerUsername']?.toString() ?? '',
      lastMessage: json['lastMessage']?.toString() ?? '',
      lastMessageSenderId: json['lastMessageSenderId']?.toString() ?? '',
      lastMessageStatus: json['lastMessageStatus']?.toString() ?? 'sent',
      lastMessageTime: json['lastMessageTime'] != null
          ? DateTime.tryParse(json['lastMessageTime'].toString()) ?? DateTime.now()
          : DateTime.now(),
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      isPinned: json['isPinned'] == true,
      isArchived: json['isArchived'] == true,
      isMuted: json['isMuted'] == true,
      isFromMe: json['isLastMessageFromMe'] == true || json['isFromMe'] == true,
      isEdited: json['isLastMessageEdited'] == true || json['isEdited'] == true,
      isDeleted: json['isLastMessageDeleted'] == true || json['isDeleted'] == true,
      mediaType: json['lastMessageType']?.toString().toLowerCase() ?? json['mediaType']?.toString() ?? 'text',
      isGroup: json['isGroup'] == true || json['groupId'] != null,
      groupId: json['groupId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'peerOfflineMeshId': peerOfflineMeshId,
      'peerUsername': peerUsername,
      'lastMessage': lastMessage,
      'lastMessageSenderId': lastMessageSenderId,
      'lastMessageStatus': lastMessageStatus,
      'lastMessageTime': lastMessageTime.toIso8601String(),
      'unreadCount': unreadCount,
      'isPinned': isPinned,
      'isArchived': isArchived,
      'isMuted': isMuted,
      'isFromMe': isFromMe,
      'isEdited': isEdited,
      'isDeleted': isDeleted,
      'mediaType': mediaType,
      'isGroup': isGroup,
      'groupId': groupId,
    };
  }
}
