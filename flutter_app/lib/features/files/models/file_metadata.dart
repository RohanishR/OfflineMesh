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
      id: json['id']?.toString() ?? '',
      senderOfflineMeshId: json['senderOfflineMeshId']?.toString() ?? '',
      recipientOfflineMeshId: json['recipientOfflineMeshId']?.toString() ?? '',
      originalFileName: json['originalFileName']?.toString() ?? 'unknown_file',
      contentType: json['contentType']?.toString() ?? 'application/octet-stream',
      fileSize: json['fileSize'] is num
          ? (json['fileSize'] as num).toInt()
          : (int.tryParse(json['fileSize']?.toString() ?? '0') ?? 0),
      checksum: json['checksum']?.toString(),
      status: json['status']?.toString() ?? 'COMPLETED',
      createdAt: json['createdAt'] != null
          ? (DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now())
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())
          : null,
      localFilePath: json['localFilePath']?.toString(),
      transport: json['transport']?.toString(),
      isEncrypted: json['isEncrypted'] == true || json['encrypted'] == true,
      encryptedKeyEnvelope: json['encryptedKeyEnvelope']?.toString(),
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
