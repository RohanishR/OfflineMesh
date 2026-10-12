import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_app/core/security/e2e_encryption_service.dart';
import 'package:flutter_app/core/security/encrypted_envelope.dart';
import 'package:flutter_app/core/security/contact_security_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('E2eEncryptionService Full Security Test Suite', () {
    late Map<String, String> secureStorageAlice;
    late Map<String, String> secureStorageBob;
    late Map<String, dynamic> directoryBackend;

    late E2eEncryptionService aliceService;
    late E2eEncryptionService bobService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      secureStorageAlice = {};
      secureStorageBob = {};
      directoryBackend = {};

      // Mock HTTP client simulating backend public key directory
      http.Client createMockClient() {
        return MockClient((request) async {
          final uri = request.url;
          if (uri.path == '/api/keys' && request.method == 'POST') {
            final body = jsonDecode(request.body);
            // In a real flow, auth header gives username/offlineMeshId
            final auth = request.headers['Authorization'] ?? '';
            final meshId = auth.contains('ALICE') ? 'OM-ALICE' : 'OM-BOB';
            directoryBackend[meshId] = {
              'offlineMeshId': meshId,
              'publicKey': body['publicKey'],
              'keyId': body['keyId'],
              'fingerprint': body['fingerprint'],
            };
            return http.Response(jsonEncode(directoryBackend[meshId]), 201);
          } else if (uri.path.startsWith('/api/keys/') && request.method == 'GET') {
            final meshId = uri.pathSegments.last;
            if (directoryBackend.containsKey(meshId)) {
              return http.Response(jsonEncode(directoryBackend[meshId]), 200);
            }
            return http.Response(jsonEncode({'error': 'Not found'}), 404);
          }
          return http.Response('Not Found', 404);
        });
      }

      // We test mock secure storage by using custom memory map
      FlutterSecureStorage.setMockInitialValues({});

      aliceService = E2eEncryptionService(
        baseUrl: 'http://localhost',
        jwtToken: 'JWT-ALICE',
        localOfflineMeshId: 'OM-ALICE',
        httpClient: createMockClient(),
      );

      bobService = E2eEncryptionService(
        baseUrl: 'http://localhost',
        jwtToken: 'JWT-BOB',
        localOfflineMeshId: 'OM-BOB',
        httpClient: createMockClient(),
      );

      await aliceService.initialize();
      await bobService.initialize();
    });

    test('1 & 2. Alice sends encrypted message to Bob; Bob decrypts successfully', () async {
      const plaintext = 'Secret rendezvous at 18:00';
      const messageId = 'msg-101';

      final envelope = await aliceService.encryptMessage(
        recipientOfflineMeshId: 'OM-BOB',
        messageId: messageId,
        plaintext: plaintext,
      );

      expect(envelope.version, 2);
      expect(envelope.senderId, 'OM-ALICE');
      expect(envelope.recipientId, 'OM-BOB');
      expect(envelope.ciphertext, isNot(contains(plaintext)));

      // Bob decrypts
      final decrypted = await bobService.decryptMessage(envelope);
      expect(decrypted, plaintext);
    });

    test('3. Verify plaintext is absent from envelope JSON', () async {
      const plaintext = 'Super confidential trade secret';
      final envelope = await aliceService.encryptMessage(
        recipientOfflineMeshId: 'OM-BOB',
        messageId: 'msg-102',
        plaintext: plaintext,
      );

      final envelopeJson = envelope.toJsonString();
      expect(envelopeJson.contains(plaintext), isFalse);
    });

    test('6. Tampering with ciphertext causes decryption failure', () async {
      final envelope = await aliceService.encryptMessage(
        recipientOfflineMeshId: 'OM-BOB',
        messageId: 'msg-103',
        plaintext: 'Valid Message',
      );

      // Flip byte in ciphertext
      final cipherBytes = base64Decode(envelope.ciphertext);
      cipherBytes[0] ^= 0xFF; // tamper
      final tamperedEnvelope = EncryptedEnvelope(
        version: envelope.version,
        messageId: envelope.messageId,
        senderId: envelope.senderId,
        recipientId: envelope.recipientId,
        keyId: envelope.keyId,
        ephemeralPublicKey: envelope.ephemeralPublicKey,
        nonce: envelope.nonce,
        ciphertext: base64Encode(cipherBytes),
        mac: envelope.mac,
      );

      expect(
        () async => await bobService.decryptMessage(tamperedEnvelope),
        throwsA(isA<DecryptionException>()),
      );
    });

    test('7. Tampering with authenticated metadata (AAD) causes decryption failure', () async {
      final envelope = await aliceService.encryptMessage(
        recipientOfflineMeshId: 'OM-BOB',
        messageId: 'msg-104',
        plaintext: 'Tamper AAD test',
      );

      // Tamper message ID in envelope without changing ciphertext or mac
      final tamperedEnvelope = EncryptedEnvelope(
        version: envelope.version,
        messageId: 'msg-FORGED',
        senderId: envelope.senderId,
        recipientId: envelope.recipientId,
        keyId: envelope.keyId,
        ephemeralPublicKey: envelope.ephemeralPublicKey,
        nonce: envelope.nonce,
        ciphertext: envelope.ciphertext,
        mac: envelope.mac,
      );

      expect(
        () async => await bobService.decryptMessage(tamperedEnvelope),
        throwsA(isA<DecryptionException>()),
      );
    });

    test('8. Replay protection rejects duplicate message delivery', () async {
      final envelope = await aliceService.encryptMessage(
        recipientOfflineMeshId: 'OM-BOB',
        messageId: 'msg-105',
        plaintext: 'Send 100 dollars',
      );

      final decryptedFirst = await bobService.decryptMessage(envelope);
      expect(decryptedFirst, 'Send 100 dollars');

      // Attempt replay
      expect(
        () async => await bobService.decryptMessage(envelope),
        throwsA(isA<DecryptionException>()),
      );
    });

    test('10. Public key fingerprint is deterministic', () async {
      final fp1 = aliceService.fingerprint;
      expect(fp1, isNotNull);
      expect(fp1!.contains(':'), isTrue);

      final pubBytes = base64Decode(await aliceService.getPublicKeyBase64() ?? '');
      final computedFp = await aliceService.computeFingerprint(pubBytes);
      expect(computedFp, fp1);
    });

    test('11. Wrong recipient private key fails decryption', () async {
      // Eve generates service with her own keys
      final eveService = E2eEncryptionService(
        baseUrl: 'http://localhost',
        jwtToken: 'JWT-EVE',
        localOfflineMeshId: 'OM-EVE',
        httpClient: http.Client(),
      );
      await eveService.initialize();

      // Alice sends message to Bob
      final envelope = await aliceService.encryptMessage(
        recipientOfflineMeshId: 'OM-BOB',
        messageId: 'msg-106',
        plaintext: 'For Bob only',
      );

      // Eve attempts to decrypt envelope intended for Bob
      expect(
        () async => await eveService.decryptMessage(envelope),
        throwsA(isA<DecryptionException>()),
      );
    });

    test('14. File streaming encryption and decryption roundtrip', () async {
      final tempDir = Directory.systemTemp.createTempSync('e2e_files_');
      final sourceFile = File('${tempDir.path}/source.bin');
      final targetFile = File('${tempDir.path}/target.bin');

      final sampleData = List.generate(128 * 1024, (i) => (i * 7) % 256);
      await sourceFile.writeAsBytes(sampleData);

      // Alice encrypts file for Bob
      final encResult = await aliceService.encryptFile(sourceFile, 'OM-BOB');
      expect(encResult.encryptedFile.existsSync(), isTrue);
      expect(encResult.encryptedKeyEnvelope.isNotEmpty, isTrue);

      // Verify encrypted file does NOT contain original plaintext
      final encBytes = await encResult.encryptedFile.readAsBytes();
      expect(encBytes, isNot(sampleData));

      // Bob decrypts file
      final decryptedFile = await bobService.decryptFile(
        encryptedFile: encResult.encryptedFile,
        encryptedKeyEnvelopeJson: encResult.encryptedKeyEnvelope,
        senderOfflineMeshId: 'OM-ALICE',
        targetFile: targetFile,
      );

      expect(decryptedFile.existsSync(), isTrue);
      final decryptedBytes = await decryptedFile.readAsBytes();
      expect(decryptedBytes, sampleData);

      // Clean up
      tempDir.deleteSync(recursive: true);
    });

    test('13. Corrupted encrypted file fails integrity check and cleans up', () async {
      final tempDir = Directory.systemTemp.createTempSync('e2e_corrupt_');
      final sourceFile = File('${tempDir.path}/source.bin');
      final targetFile = File('${tempDir.path}/target.bin');

      await sourceFile.writeAsBytes(utf8.encode('Data to be corrupted'));

      final encResult = await aliceService.encryptFile(sourceFile, 'OM-BOB');

      // Corrupt a byte in the encrypted file
      final encBytes = await encResult.encryptedFile.readAsBytes();
      encBytes[encBytes.length - 1] ^= 0xFF;
      await encResult.encryptedFile.writeAsBytes(encBytes);

      await expectLater(
        bobService.decryptFile(
          encryptedFile: encResult.encryptedFile,
          encryptedKeyEnvelopeJson: encResult.encryptedKeyEnvelope,
          senderOfflineMeshId: 'OM-ALICE',
          targetFile: targetFile,
        ),
        throwsA(isA<IntegrityException>()),
      );

      // Partial corrupted target file should be deleted
      expect(targetFile.existsSync(), isFalse);

      tempDir.deleteSync(recursive: true);
    });
  });
}
