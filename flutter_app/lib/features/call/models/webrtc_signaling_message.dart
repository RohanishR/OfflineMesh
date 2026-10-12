class WebRtcSignalingMessage {
  final String id;
  final String sessionId;
  final String senderOfflineMeshId;
  final String recipientOfflineMeshId;
  final String type; // CALL_OFFER, CALL_ANSWER, ICE_CANDIDATE, etc.
  final String? sdp;
  final String? iceCandidate;
  final DateTime timestamp;

  WebRtcSignalingMessage({
    required this.id,
    required this.sessionId,
    required this.senderOfflineMeshId,
    required this.recipientOfflineMeshId,
    required this.type,
    this.sdp,
    this.iceCandidate,
    required this.timestamp,
  });

  factory WebRtcSignalingMessage.fromJson(Map<String, dynamic> json) {
    return WebRtcSignalingMessage(
      id: json['id'] as String,
      sessionId: json['sessionId'] as String,
      senderOfflineMeshId: json['senderOfflineMeshId'] as String,
      recipientOfflineMeshId: json['recipientOfflineMeshId'] as String,
      type: json['type'] as String,
      sdp: json['sdp'] as String?,
      iceCandidate: json['iceCandidate'] as String?,
      timestamp: json['timestamp'] != null 
          ? DateTime.parse(json['timestamp'] as String) 
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionId': sessionId,
      'senderOfflineMeshId': senderOfflineMeshId,
      'recipientOfflineMeshId': recipientOfflineMeshId,
      'type': type,
      if (sdp != null) 'sdp': sdp,
      if (iceCandidate != null) 'iceCandidate': iceCandidate,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
