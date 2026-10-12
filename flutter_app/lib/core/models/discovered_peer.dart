class DiscoveredPeer {
  final String offlineMeshId;
  final String displayName;
  final String deviceId;
  final String ipAddress;
  final int port;
  final DateTime discoveryTimestamp;
  DateTime lastSeenTimestamp;
  bool isReachable;

  DiscoveredPeer({
    required this.offlineMeshId,
    required this.displayName,
    required this.deviceId,
    required this.ipAddress,
    required this.port,
    required this.discoveryTimestamp,
    required this.lastSeenTimestamp,
    this.isReachable = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'offlineMeshId': offlineMeshId,
      'displayName': displayName,
      'deviceId': deviceId,
      'ipAddress': ipAddress,
      'port': port,
      'discoveryTimestamp': discoveryTimestamp.toIso8601String(),
      'lastSeenTimestamp': lastSeenTimestamp.toIso8601String(),
      'isReachable': isReachable,
    };
  }

  factory DiscoveredPeer.fromJson(Map<String, dynamic> json) {
    return DiscoveredPeer(
      offlineMeshId: json['offlineMeshId'],
      displayName: json['displayName'],
      deviceId: json['deviceId'],
      ipAddress: json['ipAddress'],
      port: json['port'],
      discoveryTimestamp: DateTime.parse(json['discoveryTimestamp']),
      lastSeenTimestamp: DateTime.parse(json['lastSeenTimestamp']),
      isReachable: json['isReachable'] ?? true,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DiscoveredPeer && other.offlineMeshId == offlineMeshId;
  }

  @override
  int get hashCode => offlineMeshId.hashCode;
}
