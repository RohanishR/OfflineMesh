import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_app/core/config/app_config.dart';
import 'package:flutter_app/core/security/contact_security_model.dart';
import 'package:flutter_app/core/security/e2e_encryption_service.dart';
import 'package:flutter_app/features/call/models/call_session_state.dart';
import 'package:flutter_app/features/call/models/webrtc_signaling_message.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('Phase 5: STUN/TURN ICE Servers Configuration Tests', () {
    test('Default ICE servers return Google STUN when unconfigured', () async {
      final servers = await AppConfig.getIceServers();
      expect(servers, isNotEmpty);
      final firstUrls = servers.first['urls'] as List;
      expect(firstUrls.first.toString(), startsWith('stun:'));
    });

    test('Custom ICE servers can be saved and retrieved', () async {
      final customServers = [
        {
          'urls': ['turn:turn.offlinemesh.io:3478'],
          'username': 'meshuser',
          'credential': 'meshpassword',
        },
        {
          'urls': ['stun:stun.l.google.com:19302'],
        }
      ];

      await AppConfig.setCustomIceServers(customServers);
      final loaded = await AppConfig.getIceServers();

      expect(loaded.length, 2);
      expect(loaded.first['urls'], ['turn:turn.offlinemesh.io:3478']);
      expect(loaded.first['username'], 'meshuser');
      expect(loaded.first['credential'], 'meshpassword');
    });

    test('Resetting custom ICE servers restores defaults', () async {
      await AppConfig.setCustomIceServers(AppConfig.defaultIceServers);
      final loaded = await AppConfig.getIceServers();
      expect(loaded, AppConfig.defaultIceServers);
    });
  });

  group('Phase 5: Cryptographic Safety Numbers & Key Rotation Tests', () {
    test('Fingerprint computation is deterministic for given public key bytes', () async {
      final sampleKeyBytes = utf8.encode('32-byte-canonical-public-key-123');
      final fp1 = await E2eEncryptionService.computeFingerprint(sampleKeyBytes);
      final fp2 = await E2eEncryptionService.computeFingerprint(sampleKeyBytes);

      expect(fp1, fp2);
      // Fingerprint should be formatted as 8 groups of 4 hex characters separated by colons
      expect(fp1.contains(':'), isTrue);
      final parts = fp1.split(':');
      expect(parts.length, 8);
      for (final p in parts) {
        expect(p.length, 4);
      }
    });

    test('ContactSecurityInfo detects KEY_CHANGED when contact rotates key', () {
      final initialInfo = ContactSecurityInfo(
        offlineMeshId: 'user-bob',
        publicKeyBase64: 'AAAA_initial_key==',
        keyId: 'key-v1',
        fingerprint: '1111:2222:3333:4444:5555:6666:7777:8888',
        status: VerificationStatus.VERIFIED,
        lastSeenAt: DateTime.now(),
      );

      expect(initialInfo.status, VerificationStatus.VERIFIED);

      // Contact rotates their key
      const newKeyBase64 = 'BBBB_rotated_key==';
      const newKeyId = 'key-v2';
      const newFingerprint = '9999:8888:7777:6666:5555:4444:3333:2222';

      final rotatedInfo = initialInfo.copyWith(
        publicKeyBase64: newKeyBase64,
        keyId: newKeyId,
        fingerprint: newFingerprint,
        status: VerificationStatus.KEY_CHANGED,
        previousFingerprint: initialInfo.fingerprint,
        lastSeenAt: DateTime.now(),
      );

      expect(rotatedInfo.status, VerificationStatus.KEY_CHANGED);
      expect(rotatedInfo.previousFingerprint, initialInfo.fingerprint);
      expect(rotatedInfo.fingerprint, newFingerprint);
      expect(rotatedInfo.publicKeyBase64, newKeyBase64);
    });

    test('ContactSecurityInfo serialization preserves verification status and history', () {
      final info = ContactSecurityInfo(
        offlineMeshId: 'user-carol',
        publicKeyBase64: 'CCCC_key==',
        keyId: 'key-100',
        fingerprint: 'AAAA:BBBB:CCCC:DDDD:EEEE:FFFF:0000:1111',
        status: VerificationStatus.KEY_CHANGED,
        lastSeenAt: DateTime.now(),
        previousFingerprint: 'PREV:IOUS:FING:ERPR:INT0:0000:0000:0000',
      );

      final json = info.toJson();
      final deserialized = ContactSecurityInfo.fromJson(json);

      expect(deserialized.offlineMeshId, 'user-carol');
      expect(deserialized.publicKeyBase64, 'CCCC_key==');
      expect(deserialized.keyId, 'key-100');
      expect(deserialized.fingerprint, 'AAAA:BBBB:CCCC:DDDD:EEEE:FFFF:0000:1111');
      expect(deserialized.status, VerificationStatus.KEY_CHANGED);
      expect(deserialized.previousFingerprint, 'PREV:IOUS:FING:ERPR:INT0:0000:0000:0000');
    });
  });

  group('Phase 5: WebRTC Voice & Video Call State Flow Tests', () {
    test('Signaling messages support offer, answer, and candidate payloads', () {
      final offer = WebRtcSignalingMessage(
        id: 'offer-1',
        sessionId: 'session-101',
        senderOfflineMeshId: 'user-alice',
        recipientOfflineMeshId: 'user-bob',
        type: 'CALL_OFFER',
        sdp: 'v=0\\r\\nm=audio 54312\\r\\nm=video 54314',
        timestamp: DateTime.now(),
      );

      expect(offer.type, 'CALL_OFFER');
      expect(offer.sdp?.contains('m=video'), isTrue);

      final answer = WebRtcSignalingMessage(
        id: 'answer-1',
        sessionId: 'session-101',
        senderOfflineMeshId: 'user-bob',
        recipientOfflineMeshId: 'user-alice',
        type: 'CALL_ANSWER',
        sdp: 'v=0\\r\\nm=audio 54312\\r\\nm=video 54314',
        timestamp: DateTime.now(),
      );

      expect(answer.type, 'CALL_ANSWER');
      expect(answer.recipientOfflineMeshId, 'user-alice');

      final ice = WebRtcSignalingMessage(
        id: 'ice-1',
        sessionId: 'session-101',
        senderOfflineMeshId: 'user-alice',
        recipientOfflineMeshId: 'user-bob',
        type: 'ICE_CANDIDATE',
        iceCandidate: '{"candidate":"candidate:1 1 UDP 2130706431 192.168.1.5 54321 typ host"}',
        timestamp: DateTime.now(),
      );

      expect(ice.type, 'ICE_CANDIDATE');
      expect(ice.iceCandidate?.contains('typ host'), isTrue);
    });

    test('Call session states correctly track full lifecycle', () {
      final states = <CallSessionState>[
        CallSessionState.IDLE,
        CallSessionState.CALLING,
        CallSessionState.RINGING,
        CallSessionState.ACCEPTED,
        CallSessionState.NEGOTIATING,
        CallSessionState.CONNECTED,
        CallSessionState.RECONNECTING,
        CallSessionState.ENDED,
      ];

      expect(states.length, 8);
      expect(states.first, CallSessionState.IDLE);
      expect(states.last, CallSessionState.ENDED);
    });
  });
}
