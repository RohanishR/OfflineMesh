// ignore_for_file: constant_identifier_names

enum VerificationStatus {
  UNVERIFIED,
  VERIFIED,
  KEY_CHANGED,
}

class ContactSecurityInfo {
  final String offlineMeshId;
  final String publicKeyBase64;
  final String keyId;
  final String fingerprint;
  final VerificationStatus status;
  final DateTime lastSeenAt;
  final String? previousFingerprint;

  VerificationStatus get verificationStatus => status;

  ContactSecurityInfo({
    required this.offlineMeshId,
    required this.publicKeyBase64,
    required this.keyId,
    required this.fingerprint,
    required this.status,
    required this.lastSeenAt,
    this.previousFingerprint,
  });

  Map<String, dynamic> toJson() {
    return {
      'offlineMeshId': offlineMeshId,
      'publicKeyBase64': publicKeyBase64,
      'keyId': keyId,
      'fingerprint': fingerprint,
      'status': status.name,
      'lastSeenAt': lastSeenAt.toIso8601String(),
      'previousFingerprint': previousFingerprint,
    };
  }

  factory ContactSecurityInfo.fromJson(Map<String, dynamic> json) {
    return ContactSecurityInfo(
      offlineMeshId: json['offlineMeshId'] as String? ?? '',
      publicKeyBase64: json['publicKeyBase64'] as String? ?? '',
      keyId: json['keyId'] as String? ?? '',
      fingerprint: json['fingerprint'] as String? ?? '',
      status: VerificationStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => VerificationStatus.UNVERIFIED,
      ),
      lastSeenAt: json['lastSeenAt'] != null
          ? DateTime.parse(json['lastSeenAt'])
          : DateTime.now(),
      previousFingerprint: json['previousFingerprint'] as String?,
    );
  }

  ContactSecurityInfo copyWith({
    String? publicKeyBase64,
    String? keyId,
    String? fingerprint,
    VerificationStatus? status,
    DateTime? lastSeenAt,
    String? previousFingerprint,
  }) {
    return ContactSecurityInfo(
      offlineMeshId: offlineMeshId,
      publicKeyBase64: publicKeyBase64 ?? this.publicKeyBase64,
      keyId: keyId ?? this.keyId,
      fingerprint: fingerprint ?? this.fingerprint,
      status: status ?? this.status,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      previousFingerprint: previousFingerprint ?? this.previousFingerprint,
    );
  }
}
