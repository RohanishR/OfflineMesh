import '../transport/transport_type.dart';

class Message {
  final String id;
  final String senderOfflineMeshId;
  final String content;
  final DateTime createdAt;
  String status;
  TransportType? transport;

  Message({
    required this.id,
    required this.senderOfflineMeshId,
    required this.content,
    required this.createdAt,
    this.status = 'sent',
    this.transport,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    TransportType? parsedTransport;
    if (json['transport'] != null) {
      try {
        parsedTransport = TransportType.values.byName(json['transport']);
      } catch (_) {}
    }
    return Message(
      id: json['id']?.toString() ?? '',
      senderOfflineMeshId: json['senderOfflineMeshId'] ?? '',
      content: json['content'] ?? '',
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : DateTime.now(),
      status: json['status'] ?? 'sent',
      transport: parsedTransport,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderOfflineMeshId': senderOfflineMeshId,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'status': status,
      'transport': transport?.name,
    };
  }

  Message copyWith({
    String? id,
    String? senderOfflineMeshId,
    String? content,
    DateTime? createdAt,
    String? status,
    TransportType? transport,
  }) {
    return Message(
      id: id ?? this.id,
      senderOfflineMeshId: senderOfflineMeshId ?? this.senderOfflineMeshId,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      transport: transport ?? this.transport,
    );
  }
}

