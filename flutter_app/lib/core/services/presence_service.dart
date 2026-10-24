import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:stomp_dart_client/stomp.dart';

class UserPresence {
  final String offlineMeshId;
  final String status; // ONLINE, OFFLINE
  final bool isTyping;
  final bool isRecording;
  final DateTime lastSeen;

  const UserPresence({
    required this.offlineMeshId,
    required this.status,
    this.isTyping = false,
    this.isRecording = false,
    required this.lastSeen,
  });

  bool get isOnline => status.toUpperCase() == 'ONLINE';

  factory UserPresence.fromJson(Map<String, dynamic> json) {
    return UserPresence(
      offlineMeshId: json['offlineMeshId']?.toString() ?? '',
      status: json['status']?.toString() ?? 'OFFLINE',
      isTyping: json['isTyping'] == true,
      isRecording: json['isRecording'] == true,
      lastSeen: json['lastSeen'] != null
          ? DateTime.tryParse(json['lastSeen'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'offlineMeshId': offlineMeshId,
      'status': status,
      'isTyping': isTyping,
      'isRecording': isRecording,
      'lastSeen': lastSeen.toIso8601String(),
    };
  }
}

class PresenceService {
  StompClient? stompClient;
  String myOfflineMeshId;

  final Map<String, UserPresence> _presenceCache = {};
  final _presenceStreamController = StreamController<UserPresence>.broadcast();

  Stream<UserPresence> get presenceUpdates => _presenceStreamController.stream;

  PresenceService({
    this.stompClient,
    required this.myOfflineMeshId,
  });

  void initialize([StompClient? client]) {
    if (client != null) {
      stompClient = client;
    }
    if (stompClient != null && stompClient!.connected) {
      _subscribeToPresence();
    }
  }

  void _subscribeToPresence() {
    try {
      stompClient?.subscribe(
        destination: '/topic/presence',
        callback: (frame) {
          if (frame.body != null) {
            try {
              final json = jsonDecode(frame.body!);
              final update = UserPresence.fromJson(json);
              if (update.offlineMeshId != myOfflineMeshId) {
                _presenceCache[update.offlineMeshId] = update;
                _presenceStreamController.add(update);
              }
            } catch (e) {
              debugPrint('Error parsing presence update: $e');
            }
          }
        },
      );
    } catch (e) {
      debugPrint('Error subscribing to /topic/presence: $e');
    }
  }

  UserPresence? getPresence(String offlineMeshId) {
    return _presenceCache[offlineMeshId];
  }

  void sendTyping(bool isTyping) {
    _sendUpdate(isTyping: isTyping, isRecording: false);
  }

  void sendRecording(bool isRecording) {
    _sendUpdate(isTyping: false, isRecording: isRecording);
  }

  void _sendUpdate({required bool isTyping, required bool isRecording}) {
    if (stompClient != null && stompClient!.connected) {
      try {
        final payload = {
          'offlineMeshId': myOfflineMeshId,
          'status': 'ONLINE',
          'isTyping': isTyping,
          'isRecording': isRecording,
          'lastSeen': DateTime.now().toIso8601String(),
        };
        stompClient!.send(
          destination: '/app/presence/update',
          body: jsonEncode(payload),
        );
      } catch (e) {
        debugPrint('Failed to send presence update: $e');
      }
    }
  }

  void dispose() {
    _presenceStreamController.close();
  }
}
