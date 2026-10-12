class FileMetadata {
  final String id;
  final String senderOfflineMeshId;
  final String recipientOfflineMeshId;
  final String originalFileName;
  final String contentType;
  final int fileSize;
  final String? checksum;
  final String status;
  final DateTime createdAt;
  final DateTime? updatedAt;
  String? localFilePath;
  String? transport;
  final bool isEncrypted;
  final String? encryptedKeyEnvelope;

  FileMetadata({
    required this.id,
    required this.senderOfflineMeshId,
    required this.recipientOfflineMeshId,
    required this.originalFileName,
    required this.contentType,
    required this.fileSize,
    this.checksum,
    required this.status,
    required this.createdAt,
    this.updatedAt,
    this.localFilePath,
    this.transport,
    this.isEncrypted = false,
    this.encryptedKeyEnvelope,
  });

  factory FileMetadata.fromJson(Map<String, dynamic> json) {
    return FileMetadata(
      id: json['id'],
      senderOfflineMeshId: json['senderOfflineMeshId'],
      recipientOfflineMeshId: json['recipientOfflineMeshId'],
      originalFileName: json['originalFileName'],
      contentType: json['contentType'],
      fileSize: json['fileSize'],
      checksum: json['checksum'],
      status: json['status'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
      localFilePath: json['localFilePath'],
      transport: json['transport'],
      isEncrypted: json['isEncrypted'] == true,
      encryptedKeyEnvelope: json['encryptedKeyEnvelope'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderOfflineMeshId': senderOfflineMeshId,
      'recipientOfflineMeshId': recipientOfflineMeshId,
      'originalFileName': originalFileName,
      'contentType': contentType,
      'fileSize': fileSize,
      'checksum': checksum,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'localFilePath': localFilePath,
      'transport': transport,
      'isEncrypted': isEncrypted,
      'encryptedKeyEnvelope': encryptedKeyEnvelope,
    };
  }
}
