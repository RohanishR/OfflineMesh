import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'package:crypto/crypto.dart' as crypto;

import 'encrypted_envelope.dart';
import 'contact_security_model.dart';
import '../config/app_config.dart';

class DecryptionException implements Exception {
  final String message;
  DecryptionException(this.message);
  @override
  String toString() => message;
}

class IntegrityException implements Exception {
  final String message;
  IntegrityException(this.message);
  @override
  String toString() => message;
}

class EncryptedFileResult {
  final File encryptedFile;
  final String encryptedKeyEnvelope;
  final String checksum;
  final int encryptedFileSize;

  EncryptedFileResult({
    required this.encryptedFile,
    required this.encryptedKeyEnvelope,
    required this.checksum,
    required this.encryptedFileSize,
  });
}

class E2eEncryptionService {
  final String baseUrl;
  final String jwtToken;
  final String localOfflineMeshId;

  final FlutterSecureStorage _secureStorage;
  final http.Client _httpClient;
  SharedPreferences? _prefs;

  // Cryptographic primitives
  final _x25519 = X25519();
  final _chacha20 = Chacha20.poly1305Aead();
  final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final _sha256 = Sha256();

  // Local identity key pair
  SimpleKeyPair? _identityKeyPair;
  SimplePublicKey? _identityPublicKey;
  String? _identityKeyId;
  String? _fingerprint;

  // Replay protection: bounded LRU cache of recently seen message IDs
  static const int _maxReplayCacheSize = 1000;
  final LinkedHashSet<String> _seenMessageIds = LinkedHashSet<String>();

  // In-memory contact security cache
  final Map<String, ContactSecurityInfo> _contactCache = {};

  E2eEncryptionService({
    String? baseUrl,
    required this.jwtToken,
    required this.localOfflineMeshId,
    FlutterSecureStorage? secureStorage,
    http.Client? httpClient,
    SharedPreferences? prefs,
  })  : baseUrl = baseUrl ?? AppConfig.backendBaseUrl,
        _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _httpClient = httpClient ?? http.Client(),
        _prefs = prefs;

  String? get identityKeyId => _identityKeyId;
  String? get fingerprint => _fingerprint;
  String? get identityPublicKeyBase64 => _identityPublicKey != null ? base64Encode(_identityPublicKey!.bytes) : null;

  Future<String?> getPublicKeyBase64() async {
    if (_identityPublicKey == null) return null;
    return base64Encode(_identityPublicKey!.bytes);
  }

  /// Initialises local identity key pair, calculates fingerprint, and registers with backend.
  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
    _loadCachedContacts();

    final privKeyHex = await _secureStorage.read(key: 'e2ee_priv_${localOfflineMeshId}');
    final pubKeyHex = await _secureStorage.read(key: 'e2ee_pub_${localOfflineMeshId}');
    final keyId = await _secureStorage.read(key: 'e2ee_key_id_${localOfflineMeshId}');

    if (privKeyHex != null && pubKeyHex != null && keyId != null) {
      // Restore existing identity key
      final privBytes = base64Decode(privKeyHex);
      final pubBytes = base64Decode(pubKeyHex);
      _identityPublicKey = SimplePublicKey(pubBytes, type: KeyPairType.x25519);
      _identityKeyPair = SimpleKeyPairData(
        privBytes,
        publicKey: _identityPublicKey!,
        type: KeyPairType.x25519,
      );
      _identityKeyId = keyId;
    } else {
      // Generate new long-term identity key pair
      _identityKeyPair = await _x25519.newKeyPair();
      _identityPublicKey = await _identityKeyPair!.extractPublicKey();
      _identityKeyId = const Uuid().v4();

      final privBytes = await _identityKeyPair!.extractPrivateKeyBytes();
      await _secureStorage.write(
        key: 'e2ee_priv_${localOfflineMeshId}',
        value: base64Encode(privBytes),
      );
      await _secureStorage.write(
        key: 'e2ee_pub_${localOfflineMeshId}',
        value: base64Encode(_identityPublicKey!.bytes),
      );
      await _secureStorage.write(
        key: 'e2ee_key_id_${localOfflineMeshId}',
        value: _identityKeyId!,
      );
    }

    _fingerprint = await computeFingerprint(_identityPublicKey!.bytes);

    // Register public key with backend
    try {
      await _registerPublicKeyWithBackend();
    } catch (e) {
      debugPrint('Failed to register public key with backend: $e');
    }
  }

  static final _staticSha256 = Sha256();

  /// Computes a deterministic human-readable fingerprint: SHA-256(canonical public key)
  static Future<String> computeFingerprint(List<int> publicKeyBytes) async {
    final hash = await _staticSha256.hash(publicKeyBytes);
    final hexStr = hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();
    // Format into 8 groups of 4 characters: XXXX:XXXX:...
    final buffer = StringBuffer();
    for (int i = 0; i < 32 && i < hexStr.length; i += 4) {
      if (buffer.isNotEmpty) buffer.write(':');
      buffer.write(hexStr.substring(i, i + 4));
    }
    return buffer.toString();
  }

  Future<void> _registerPublicKeyWithBackend() async {
    final pubBase64 = base64Encode(_identityPublicKey!.bytes);
    final response = await _httpClient.post(
      Uri.parse('$baseUrl/api/keys'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwtToken',
      },
      body: jsonEncode({
        'publicKey': pubBase64,
        'keyId': _identityKeyId,
        'fingerprint': _fingerprint,
      }),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      debugPrint('Backend key registration response: ${response.statusCode} - ${response.body}');
    }
  }

  /// Retrieves and caches contact public key info.
  Future<ContactSecurityInfo> getContactSecurityInfo(String offlineMeshId) async {
    // Check if we have cached info
    ContactSecurityInfo? cached = _contactCache[offlineMeshId];

    try {
      final response = await _httpClient.get(
        Uri.parse('$baseUrl/api/keys/$offlineMeshId'),
        headers: {
          'Authorization': 'Bearer $jwtToken',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final remotePubKey = data['publicKey'] as String;
        final remoteKeyId = data['keyId'] as String;
        final remoteFingerprint = data['fingerprint'] as String;

        if (cached != null) {
          if (cached.publicKeyBase64 != remotePubKey) {
            // Security alert: Key changed unexpectedly!
            cached = cached.copyWith(
              status: VerificationStatus.KEY_CHANGED,
              previousFingerprint: cached.fingerprint,
              lastSeenAt: DateTime.now(),
            );
            _saveContact(cached);
            return cached;
          }
        } else {
          cached = ContactSecurityInfo(
            offlineMeshId: offlineMeshId,
            publicKeyBase64: remotePubKey,
            keyId: remoteKeyId,
            fingerprint: remoteFingerprint,
            status: VerificationStatus.UNVERIFIED,
            lastSeenAt: DateTime.now(),
          );
          _saveContact(cached);
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch public key from backend for $offlineMeshId: $e');
    }

    if (cached != null) {
      return cached;
    }

    throw Exception('Public key not found for contact $offlineMeshId');
  }

  /// Registers or updates a contact public key received directly over local transport (BLE / Wi-Fi LAN).
  Future<void> registerPeerKey({
    required String offlineMeshId,
    required String publicKeyBase64,
    required String keyId,
    String? fingerprint,
  }) async {
    final computedFp = fingerprint ?? await computeFingerprint(base64Decode(publicKeyBase64));
    ContactSecurityInfo? cached = _contactCache[offlineMeshId];
    if (cached != null) {
      if (cached.publicKeyBase64 != publicKeyBase64) {
        cached = cached.copyWith(
          publicKeyBase64: publicKeyBase64,
          keyId: keyId,
          fingerprint: computedFp,
          status: VerificationStatus.KEY_CHANGED,
          previousFingerprint: cached.fingerprint,
          lastSeenAt: DateTime.now(),
        );
        _saveContact(cached);
      }
    } else {
      cached = ContactSecurityInfo(
        offlineMeshId: offlineMeshId,
        publicKeyBase64: publicKeyBase64,
        keyId: keyId,
        fingerprint: computedFp,
        status: VerificationStatus.UNVERIFIED,
        lastSeenAt: DateTime.now(),
      );
      _saveContact(cached);
    }
  }

  void markContactVerified(String offlineMeshId, bool isVerified) {
    final cached = _contactCache[offlineMeshId];
    if (cached != null) {
      final updated = cached.copyWith(
        status: isVerified ? VerificationStatus.VERIFIED : VerificationStatus.UNVERIFIED,
      );
      _saveContact(updated);
    }
  }

  Future<void> setContactVerification(String offlineMeshId, VerificationStatus status) async {
    final cached = _contactCache[offlineMeshId];
    if (cached != null) {
      final updated = cached.copyWith(status: status);
      _saveContact(updated);
    }
  }

  void _saveContact(ContactSecurityInfo info) {
    _contactCache[info.offlineMeshId] = info;
    _prefs?.setString('e2ee_contact_${info.offlineMeshId}', jsonEncode(info.toJson()));
  }

  void _loadCachedContacts() {
    if (_prefs == null) return;
    for (final key in _prefs!.getKeys()) {
      if (key.startsWith('e2ee_contact_')) {
        try {
          final jsonStr = _prefs!.getString(key);
          if (jsonStr != null) {
            final info = ContactSecurityInfo.fromJson(jsonDecode(jsonStr));
            _contactCache[info.offlineMeshId] = info;
          }
        } catch (_) {}
      }
    }
  }

  /// Encrypts a message into an EncryptedEnvelope.
  Future<EncryptedEnvelope> encryptMessage({
    required String recipientOfflineMeshId,
    required String messageId,
    required String plaintext,
  }) async {
    if (_identityKeyPair == null) {
      throw StateError('E2eEncryptionService not initialized');
    }

    final contactInfo = await getContactSecurityInfo(recipientOfflineMeshId);
    final recipientPubKeyBytes = base64Decode(contactInfo.publicKeyBase64);
    final recipientPublicKey = SimplePublicKey(recipientPubKeyBytes, type: KeyPairType.x25519);

    // 1. Generate ephemeral key pair
    final ephemeralKeyPair = await _x25519.newKeyPair();
    final ephemeralPubKey = await ephemeralKeyPair.extractPublicKey();

    // 2. Perform key agreement
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: ephemeralKeyPair,
      remotePublicKey: recipientPublicKey,
    );

    // 3. Derive message key using HKDF-SHA256
    final messageKey = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode('OfflineMesh-E2EE-v2'),
      info: utf8.encode('OfflineMesh-E2EE-Message|$localOfflineMeshId|$recipientOfflineMeshId'),
    );

    // 4. Authenticated encryption (ChaCha20-Poly1305 AEAD)
    final nonce = _chacha20.newNonce();
    final aad = utf8.encode('v2|$messageId|$localOfflineMeshId|$recipientOfflineMeshId|$_identityKeyId');

    final secretBox = await _chacha20.encrypt(
      utf8.encode(plaintext),
      secretKey: messageKey,
      nonce: nonce,
      aad: aad,
    );

    final envelope = EncryptedEnvelope(
      version: 2,
      messageId: messageId,
      senderId: localOfflineMeshId,
      recipientId: recipientOfflineMeshId,
      keyId: _identityKeyId ?? '',
      ephemeralPublicKey: base64Encode(ephemeralPubKey.bytes),
      nonce: base64Encode(secretBox.nonce),
      ciphertext: base64Encode(secretBox.cipherText),
      mac: base64Encode(secretBox.mac.bytes),
    );

    await cacheSentMessage(messageId, plaintext);

    return envelope;
  }

  final Map<String, String> _sentMessageCache = {};

  Future<void> cacheSentMessage(String messageId, String plaintext) async {
    _sentMessageCache[messageId] = plaintext;
    if (_prefs != null) {
      await _prefs!.setString('e2ee_sent_$messageId', plaintext);
    }
  }

  String? getCachedSentMessage(String messageId) {
    if (_sentMessageCache.containsKey(messageId)) {
      return _sentMessageCache[messageId];
    }
    if (_prefs != null) {
      final cached = _prefs!.getString('e2ee_sent_$messageId');
      if (cached != null) {
        _sentMessageCache[messageId] = cached;
        return cached;
      }
    }
    return null;
  }

  /// Decrypts an EncryptedEnvelope.
  Future<String> decryptMessage(dynamic envelopeOrJson, {bool checkReplay = true}) async {
    if (_identityKeyPair == null) {
      throw StateError('E2eEncryptionService not initialized');
    }

    EncryptedEnvelope envelope;
    if (envelopeOrJson is EncryptedEnvelope) {
      envelope = envelopeOrJson;
    } else if (envelopeOrJson is String) {
      envelope = EncryptedEnvelope.fromJson(jsonDecode(envelopeOrJson));
    } else if (envelopeOrJson is Map<String, dynamic>) {
      envelope = EncryptedEnvelope.fromJson(envelopeOrJson);
    } else {
      throw DecryptionException('Unable to decrypt message. Invalid format.');
    }

    if (envelope.version != 2) {
      throw DecryptionException('Unsupported protocol version: ${envelope.version}');
    }

    if (envelope.recipientId != localOfflineMeshId) {
      throw DecryptionException('Unable to decrypt message. Recipient mismatch.');
    }

    // Replay Protection
    if (checkReplay) {
      if (_seenMessageIds.contains(envelope.messageId)) {
        throw DecryptionException('Duplicate message detected (replay protection)');
      }
      _seenMessageIds.add(envelope.messageId);
      if (_seenMessageIds.length > _maxReplayCacheSize) {
        _seenMessageIds.remove(_seenMessageIds.first);
      }
    }

    try {
      final ephemeralPubKeyBytes = base64Decode(envelope.ephemeralPublicKey);
      final ephemeralPublicKey = SimplePublicKey(ephemeralPubKeyBytes, type: KeyPairType.x25519);

      // 1. Key agreement with ephemeral public key and our private identity key
      final sharedSecret = await _x25519.sharedSecretKey(
        keyPair: _identityKeyPair!,
        remotePublicKey: ephemeralPublicKey,
      );

      // 2. Derive message key using HKDF-SHA256
      final messageKey = await _hkdf.deriveKey(
        secretKey: sharedSecret,
        nonce: utf8.encode('OfflineMesh-E2EE-v2'),
        info: utf8.encode('OfflineMesh-E2EE-Message|${envelope.senderId}|${envelope.recipientId}'),
      );

      // 3. Reconstruct AAD and Decrypt
      final aad = envelope.getAssociatedData();
      final nonceBytes = base64Decode(envelope.nonce);
      final cipherBytes = base64Decode(envelope.ciphertext);
      final macBytes = base64Decode(envelope.mac);

      final secretBox = SecretBox(cipherBytes, nonce: nonceBytes, mac: Mac(macBytes));

      final decryptedBytes = await _chacha20.decrypt(
        secretBox,
        secretKey: messageKey,
        aad: aad,
      );

      return utf8.decode(decryptedBytes);
    } catch (e) {
      debugPrint('Decryption failure: $e');
      throw DecryptionException('Unable to decrypt message.');
    }
  }

  // =========================================================================
  // FILE ENCRYPTION AND DECRYPTION (STREAMING AEAD)
  // =========================================================================

  /// Encrypts a file in streaming chunks using a unique symmetric file key.
  Future<EncryptedFileResult> encryptFile(File sourceFile, String recipientOfflineMeshId) async {
    final contactInfo = await getContactSecurityInfo(recipientOfflineMeshId);
    final recipientPubKeyBytes = base64Decode(contactInfo.publicKeyBase64);
    final recipientPublicKey = SimplePublicKey(recipientPubKeyBytes, type: KeyPairType.x25519);

    // 1. Generate unique 32-byte symmetric file key
    final fileKey = await _chacha20.newSecretKey();
    final fileKeyBytes = await fileKey.extractBytes();

    // 2. Encrypt the file key for recipient using ephemeral X25519 key agreement
    final ephemeralKeyPair = await _x25519.newKeyPair();
    final ephemeralPubKey = await ephemeralKeyPair.extractPublicKey();

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: ephemeralKeyPair,
      remotePublicKey: recipientPublicKey,
    );

    final keyDerivationKey = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode('OfflineMesh-FileKey-v1'),
      info: utf8.encode('FileKey|$localOfflineMeshId|$recipientOfflineMeshId'),
    );

    final keyNonce = _chacha20.newNonce();
    final encryptedKeyBox = await _chacha20.encrypt(
      fileKeyBytes,
      secretKey: keyDerivationKey,
      nonce: keyNonce,
      aad: utf8.encode('FileKeyEnvelope|$localOfflineMeshId|$recipientOfflineMeshId'),
    );

    final keyEnvelope = {
      'ephemeralPublicKey': base64Encode(ephemeralPubKey.bytes),
      'nonce': base64Encode(encryptedKeyBox.nonce),
      'ciphertext': base64Encode(encryptedKeyBox.cipherText),
      'mac': base64Encode(encryptedKeyBox.mac.bytes),
      'senderId': localOfflineMeshId,
      'recipientId': recipientOfflineMeshId,
    };
    final keyEnvelopeJson = jsonEncode(keyEnvelope);

    // 3. Encrypt file in streaming chunks (64 KB each)
    final encryptedFile = File('${sourceFile.path}.enc');
    final outSink = encryptedFile.openWrite();
    final inStream = sourceFile.openRead();

    int chunkIndex = 0;
    int totalEncryptedBytes = 0;

    await for (final chunk in inStream) {
      final nonce = _chacha20.newNonce();
      final aad = utf8.encode('file_chunk_$chunkIndex');
      final box = await _chacha20.encrypt(
        chunk,
        secretKey: fileKey,
        nonce: nonce,
        aad: aad,
      );

      final header = ByteData(4);
      header.setUint32(0, box.cipherText.length, Endian.big);
      final headerBytes = header.buffer.asUint8List();

      outSink.add(headerBytes);
      outSink.add(box.nonce);
      outSink.add(box.mac.bytes);
      outSink.add(box.cipherText);

      totalEncryptedBytes += 4 + 12 + 16 + box.cipherText.length;
      chunkIndex++;
    }

    await outSink.flush();
    await outSink.close();

    final digest = await crypto.sha256.bind(encryptedFile.openRead()).first;
    final checksumHex = digest.toString();

    return EncryptedFileResult(
      encryptedFile: encryptedFile,
      encryptedKeyEnvelope: keyEnvelopeJson,
      checksum: checksumHex,
      encryptedFileSize: totalEncryptedBytes,
    );
  }

  /// Decrypts a streaming encrypted file verifying all chunk MACs.
  Future<File> decryptFile({
    required File encryptedFile,
    required String encryptedKeyEnvelopeJson,
    required String senderOfflineMeshId,
    required File targetFile,
  }) async {
    if (_identityKeyPair == null) {
      throw StateError('E2eEncryptionService not initialized');
    }

    // 1. Decrypt file key from envelope
    final envelope = jsonDecode(encryptedKeyEnvelopeJson) as Map<String, dynamic>;
    final ephemeralPubKeyBytes = base64Decode(envelope['ephemeralPublicKey']);
    final ephemeralPublicKey = SimplePublicKey(ephemeralPubKeyBytes, type: KeyPairType.x25519);

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: _identityKeyPair!,
      remotePublicKey: ephemeralPublicKey,
    );

    final keyDerivationKey = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode('OfflineMesh-FileKey-v1'),
      info: utf8.encode('FileKey|$senderOfflineMeshId|$localOfflineMeshId'),
    );

    final keyNonce = base64Decode(envelope['nonce']);
    final keyCipher = base64Decode(envelope['ciphertext']);
    final keyMac = base64Decode(envelope['mac']);

    final fileKeyBytes = await _chacha20.decrypt(
      SecretBox(keyCipher, nonce: keyNonce, mac: Mac(keyMac)),
      secretKey: keyDerivationKey,
      aad: utf8.encode('FileKeyEnvelope|$senderOfflineMeshId|$localOfflineMeshId'),
    );
    final fileKey = SecretKey(fileKeyBytes);

    // 2. Stream decrypt chunks
    final encRaf = await encryptedFile.open(mode: FileMode.read);
    final decSink = targetFile.openWrite();
    final totalEncLength = await encryptedFile.length();
    int readOffset = 0;
    int chunkIndex = 0;

    try {
      while (readOffset < totalEncLength) {
        final lengthHeader = await encRaf.read(4);
        if (lengthHeader.length < 4) break;
        final cipherLen = ByteData.sublistView(lengthHeader).getUint32(0, Endian.big);

        final nonce = await encRaf.read(12);
        final macBytes = await encRaf.read(16);
        final cipherText = await encRaf.read(cipherLen);

        readOffset += 4 + 12 + 16 + cipherLen;

        final box = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));
        final aad = utf8.encode('file_chunk_$chunkIndex');

        final decryptedChunk = await _chacha20.decrypt(
          box,
          secretKey: fileKey,
          aad: aad,
        );

        decSink.add(decryptedChunk);
        chunkIndex++;
      }
      await decSink.flush();
    } catch (e) {
      if (await targetFile.exists()) {
        try {
          await targetFile.delete();
        } catch (_) {}
      }
      throw IntegrityException('File integrity verification failed during decryption.');
    } finally {
      await encRaf.close();
      await decSink.close();
    }

    return targetFile;
  }
}
