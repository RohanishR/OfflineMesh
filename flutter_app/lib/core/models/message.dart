import '../transport/transport_type.dart';

class Message {
  final String id;
  final String senderOfflineMeshId;
  final String? recipientOfflineMeshId;
  final String content;
  final DateTime createdAt;
  String status;
  TransportType? transport;
  final String? replyToId;
  final String? replyToContent;
  final String? replyToSender;
  final Map<String, String>? reactions;
  final String mediaType; // 'text', 'audio', 'image', 'file', 'video'
  final bool isEdited;
  final bool isDeleted;
  final DateTime? editedAt;
  final String? mediaPath;
  final String? fileName;
  final int? fileSize;
  final int? durationMs;
  final String? fileHash;
  final String? attachmentId;

  Message({
    required this.id,
    required this.senderOfflineMeshId,
    this.recipientOfflineMeshId,
    required this.content,
    required this.createdAt,
    this.status = 'sent',
    this.transport,
    this.replyToId,
    this.replyToContent,
    this.replyToSender,
    this.reactions,
    this.mediaType = 'text',
    this.isEdited = false,
    this.isDeleted = false,
    this.editedAt,
    this.mediaPath,
    this.fileName,
    this.fileSize,
    this.durationMs,
    this.fileHash,
    this.attachmentId,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    TransportType? parsedTransport;
    if (json['transport'] != null) {
      try {
        parsedTransport =
            TransportType.values.byName(json['transport'].toString());
      } catch (_) {}
    }

    final reactionsRaw = json['reactions'];
    Map<String, String>? parsedReactions;
    if (reactionsRaw is Map) {
      parsedReactions =
          reactionsRaw.map((k, v) => MapEntry(k.toString(), v.toString()));
    }

    return Message(
      id: json['id']?.toString() ?? '',
      senderOfflineMeshId: json['senderOfflineMeshId']?.toString() ?? '',
      recipientOfflineMeshId: json['recipientOfflineMeshId']?.toString(),
      content: json['content']?.toString() ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      status: json['status']?.toString() ?? 'sent',
      transport: parsedTransport,
      replyToId: json['replyToId']?.toString(),
      replyToContent: json['replyToContent']?.toString(),
      replyToSender: json['replyToSender']?.toString(),
      reactions: parsedReactions,
      mediaType: json['mediaType']?.toString() ?? 'text',
      isEdited: json['isEdited'] == true,
      isDeleted: json['isDeleted'] == true,
      editedAt: json['editedAt'] != null
          ? DateTime.tryParse(json['editedAt'].toString())
          : null,
      mediaPath: json['mediaPath']?.toString(),
      fileName: json['fileName']?.toString(),
      fileSize:
          json['fileSize'] is num ? (json['fileSize'] as num).toInt() : null,
      durationMs: json['durationMs'] is num
          ? (json['durationMs'] as num).toInt()
          : null,
      fileHash: json['fileHash']?.toString(),
      attachmentId: json['attachmentId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderOfflineMeshId': senderOfflineMeshId,
      if (recipientOfflineMeshId != null)
        'recipientOfflineMeshId': recipientOfflineMeshId,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'status': status,
      if (transport != null) 'transport': transport!.name,
      if (replyToId != null) 'replyToId': replyToId,
      if (replyToContent != null) 'replyToContent': replyToContent,
      if (replyToSender != null) 'replyToSender': replyToSender,
      if (reactions != null && reactions!.isNotEmpty) 'reactions': reactions,
      'mediaType': mediaType,
      'isEdited': isEdited,
      'isDeleted': isDeleted,
      if (editedAt != null) 'editedAt': editedAt!.toIso8601String(),
      if (mediaPath != null) 'mediaPath': mediaPath,
      if (fileName != null) 'fileName': fileName,
      if (fileSize != null) 'fileSize': fileSize,
      if (durationMs != null) 'durationMs': durationMs,
      if (fileHash != null) 'fileHash': fileHash,
      if (attachmentId != null) 'attachmentId': attachmentId,
    };
  }

  Message copyWith({
    String? id,
    String? senderOfflineMeshId,
    String? recipientOfflineMeshId,
    String? content,
    DateTime? createdAt,
    String? status,
    TransportType? transport,
    String? replyToId,
    String? replyToContent,
    String? replyToSender,
    Map<String, String>? reactions,
    String? mediaType,
    bool? isEdited,
    bool? isDeleted,
    DateTime? editedAt,
    String? mediaPath,
    String? fileName,
    int? fileSize,
    int? durationMs,
    String? fileHash,
    String? attachmentId,
  }) {
    return Message(
      id: id ?? this.id,
      senderOfflineMeshId: senderOfflineMeshId ?? this.senderOfflineMeshId,
      recipientOfflineMeshId:
          recipientOfflineMeshId ?? this.recipientOfflineMeshId,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      transport: transport ?? this.transport,
      replyToId: replyToId ?? this.replyToId,
      replyToContent: replyToContent ?? this.replyToContent,
      replyToSender: replyToSender ?? this.replyToSender,
      reactions: reactions ?? this.reactions,
      mediaType: mediaType ?? this.mediaType,
      isEdited: isEdited ?? this.isEdited,
      isDeleted: isDeleted ?? this.isDeleted,
      editedAt: editedAt ?? this.editedAt,
      mediaPath: mediaPath ?? this.mediaPath,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      durationMs: durationMs ?? this.durationMs,
      fileHash: fileHash ?? this.fileHash,
      attachmentId: attachmentId ?? this.attachmentId,
    );
  }
}
