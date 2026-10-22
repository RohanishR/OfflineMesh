import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/config/app_config.dart';
import 'package:flutter_app/features/call/models/call_session_state.dart';
import 'package:flutter_app/features/call/models/webrtc_signaling_message.dart';

void main() {
  group('WebRTC Signaling & Call Model Tests', () {
    test('WebRtcSignalingMessage serialization and deserialization roundtrip', () {
      final now = DateTime.now();
      final msg = WebRtcSignalingMessage(
        id: 'msg-123',
        sessionId: 'session-456',
        senderOfflineMeshId: 'OM-ALICE',
        recipientOfflineMeshId: 'OM-BOB',
        type: 'CALL_OFFER',
        sdp: '{"type":"offer","sdp":"v=0\\r\\no=..."}',
        iceCandidate: '{"candidate":"candidate:...","sdpMid":"0","sdpMLineIndex":0}',
        timestamp: now,
      );

      final jsonMap = msg.toJson();
      expect(jsonMap['id'], 'msg-123');
      expect(jsonMap['sessionId'], 'session-456');
      expect(jsonMap['senderOfflineMeshId'], 'OM-ALICE');
      expect(jsonMap['recipientOfflineMeshId'], 'OM-BOB');
      expect(jsonMap['type'], 'CALL_OFFER');
      expect(jsonMap['sdp'], contains('v=0'));
      expect(jsonMap['iceCandidate'], contains('candidate:'));

      final deserialized = WebRtcSignalingMessage.fromJson(jsonMap);
      expect(deserialized.id, msg.id);
      expect(deserialized.sessionId, msg.sessionId);
      expect(deserialized.senderOfflineMeshId, msg.senderOfflineMeshId);
      expect(deserialized.recipientOfflineMeshId, msg.recipientOfflineMeshId);
      expect(deserialized.type, msg.type);
      expect(deserialized.sdp, msg.sdp);
      expect(deserialized.iceCandidate, msg.iceCandidate);
    });

    test('WebRtcSignalingMessage handles CALL_BUSY type and null optional fields', () {
      final msg = WebRtcSignalingMessage(
        id: 'busy-1',
        sessionId: 'session-789',
        senderOfflineMeshId: 'OM-BOB',
        recipientOfflineMeshId: 'OM-ALICE',
        type: 'CALL_BUSY',
        timestamp: DateTime.now(),
      );

      final jsonMap = msg.toJson();
      expect(jsonMap.containsKey('sdp'), isFalse);
      expect(jsonMap.containsKey('iceCandidate'), isFalse);
      expect(jsonMap['type'], 'CALL_BUSY');

      final deserialized = WebRtcSignalingMessage.fromJson(jsonMap);
      expect(deserialized.type, 'CALL_BUSY');
      expect(deserialized.sdp, isNull);
      expect(deserialized.iceCandidate, isNull);
    });

    test('AppConfig provides valid default ICE servers configuration', () {
      expect(AppConfig.defaultIceServers, isNotEmpty);
      final firstServer = AppConfig.defaultIceServers.first;
      expect(firstServer.containsKey('urls'), isTrue);
      final urls = firstServer['urls'] as List;
      expect(urls.any((u) => u.toString().startsWith('stun:')), isTrue);
    });

    test('CallSessionState contains all required states including BUSY', () {
      const states = CallSessionState.values;
      expect(states.contains(CallSessionState.IDLE), isTrue);
      expect(states.contains(CallSessionState.CALLING), isTrue);
      expect(states.contains(CallSessionState.RINGING), isTrue);
      expect(states.contains(CallSessionState.ACCEPTED), isTrue);
      expect(states.contains(CallSessionState.NEGOTIATING), isTrue);
      expect(states.contains(CallSessionState.CONNECTED), isTrue);
      expect(states.contains(CallSessionState.RECONNECTING), isTrue);
      expect(states.contains(CallSessionState.REJECTED), isTrue);
      expect(states.contains(CallSessionState.CANCELLED), isTrue);
      expect(states.contains(CallSessionState.ENDED), isTrue);
      expect(states.contains(CallSessionState.FAILED), isTrue);
      expect(states.contains(CallSessionState.BUSY), isTrue);
    });

    test('Local Wi-Fi direct socket signaling payload frames properly', () {
      final signal = WebRtcSignalingMessage(
        id: 'sig-direct-1',
        sessionId: 'sess-wifi-1',
        senderOfflineMeshId: 'OM-ALICE',
        recipientOfflineMeshId: 'OM-BOB',
        type: 'CALL_OFFER',
        sdp: 'v=0\\r\\no=- 123 2 IN IP4 192.168.1.5',
        timestamp: DateTime.now(),
      );

      final payload = {
        'protocolVersion': 1,
        'type': 'WEBRTC_SIGNAL',
        'senderOfflineMeshId': 'OM-ALICE',
        'recipientOfflineMeshId': 'OM-BOB',
        'signal': signal.toJson(),
      };

      final serialized = jsonEncode(payload);
      expect(serialized, contains('WEBRTC_SIGNAL'));
      expect(serialized, contains('192.168.1.5'));

      final decoded = jsonDecode(serialized) as Map<String, dynamic>;
      expect(decoded['protocolVersion'], 1);
      expect(decoded['type'], 'WEBRTC_SIGNAL');
      expect(decoded['recipientOfflineMeshId'], 'OM-BOB');

      final extractedSignal = WebRtcSignalingMessage.fromJson(decoded['signal'] as Map<String, dynamic>);
      expect(extractedSignal.type, 'CALL_OFFER');
      expect(extractedSignal.sessionId, 'sess-wifi-1');
      expect(extractedSignal.senderOfflineMeshId, 'OM-ALICE');
    });
  });
}
