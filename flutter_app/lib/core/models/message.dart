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
  final String mediaType; // 'text', 'audio', 'image', 'file'

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
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    TransportType? parsedTransport;
    if (json['transport'] != null) {
      try {
        parsedTransport = TransportType.values.byName(json['transport'].toString());
      } catch (_) {}
    }

    final reactionsRaw = json['reactions'];
    Map<String, String>? parsedReactions;
    if (reactionsRaw is Map) {
      parsedReactions = reactionsRaw.map((k, v) => MapEntry(k.toString(), v.toString()));
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderOfflineMeshId': senderOfflineMeshId,
      if (recipientOfflineMeshId != null) 'recipientOfflineMeshId': recipientOfflineMeshId,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'status': status,
      if (transport != null) 'transport': transport!.name,
      if (replyToId != null) 'replyToId': replyToId,
      if (replyToContent != null) 'replyToContent': replyToContent,
      if (replyToSender != null) 'replyToSender': replyToSender,
      if (reactions != null && reactions!.isNotEmpty) 'reactions': reactions,
      'mediaType': mediaType,
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
  }) {
    return Message(
      id: id ?? this.id,
      senderOfflineMeshId: senderOfflineMeshId ?? this.senderOfflineMeshId,
      recipientOfflineMeshId: recipientOfflineMeshId ?? this.recipientOfflineMeshId,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      transport: transport ?? this.transport,
      replyToId: replyToId ?? this.replyToId,
      replyToContent: replyToContent ?? this.replyToContent,
      replyToSender: replyToSender ?? this.replyToSender,
      reactions: reactions ?? this.reactions,
      mediaType: mediaType ?? this.mediaType,
    );
  }
}
