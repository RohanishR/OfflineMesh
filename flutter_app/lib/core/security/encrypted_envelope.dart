import 'dart:convert';

/// Represents a versioned End-to-End Encrypted message envelope.
/// Transports (Wi-Fi, Bluetooth, BLE Mesh, Internet) only see this envelope.
class EncryptedEnvelope {
  static const int currentVersion = 2;

  final int version;
  final String messageId;
  final String senderId;
  final String recipientId;
  final String keyId;
  final String ephemeralPublicKey;
  final String nonce;
  final String ciphertext;
  final String mac;

  EncryptedEnvelope({
    this.version = currentVersion,
    required this.messageId,
    required this.senderId,
    required this.recipientId,
    required this.keyId,
    required this.ephemeralPublicKey,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
  });

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'messageId': messageId,
      'senderId': senderId,
      'recipientId': recipientId,
      'keyId': keyId,
      'ephemeralPublicKey': ephemeralPublicKey,
      'nonce': nonce,
      'ciphertext': ciphertext,
      'mac': mac,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  factory EncryptedEnvelope.fromJsonString(String jsonString) {
    return EncryptedEnvelope.fromJson(jsonDecode(jsonString));
  }

  factory EncryptedEnvelope.fromJson(Map<String, dynamic> json) {
    return EncryptedEnvelope(
      version: json['version'] as int? ?? currentVersion,
      messageId: json['messageId'] as String? ?? '',
      senderId: json['senderId'] as String? ?? '',
      recipientId: json['recipientId'] as String? ?? '',
      keyId: json['keyId'] as String? ?? '',
      ephemeralPublicKey: json['ephemeralPublicKey'] as String? ?? '',
      nonce: json['nonce'] as String? ?? '',
      ciphertext: json['ciphertext'] as String? ?? '',
      mac: json['mac'] as String? ?? '',
    );
  }

  static bool isEncryptedEnvelope(String text) {
    if (!text.trim().startsWith('{') || !text.trim().endsWith('}')) {
      return false;
    }
    try {
      final decoded = jsonDecode(text);
      return decoded is Map &&
          decoded['version'] == 2 &&
          decoded['ciphertext'] != null &&
          decoded['ephemeralPublicKey'] != null;
    } catch (_) {
      return false;
    }
  }

  List<int> getAssociatedData() {
    return utf8.encode('v$version|$messageId|$senderId|$recipientId|$keyId');
  }
}
