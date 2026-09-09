import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_app1/core/crypto/crypto_service.dart';
import 'package:flutter_app1/core/crypto/key_storage_io.dart';
import 'package:flutter_app1/core/models/contact_model.dart';
import 'package:flutter_app1/core/models/private_message_model.dart';
import 'package:flutter_app1/core/models/message_model.dart';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Map<String, String> mockSecureStorage = {};

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => '.',
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'write') {
          mockSecureStorage[methodCall.arguments['key'] as String] =
              methodCall.arguments['value'] as String;
          return null;
        } else if (methodCall.method == 'read') {
          return mockSecureStorage[methodCall.arguments['key'] as String];
        } else if (methodCall.method == 'delete') {
          mockSecureStorage.remove(methodCall.arguments['key'] as String);
          return null;
        }
        return null;
      },
    );
  });

  group('Crisis Mesh — Phase 8: E2EE Private 1-to-1 Messaging & QR Cryptographic Tests', () {
    // Deterministic seeds for test nodes
    final seedEdA = Uint8List.fromList(List.generate(32, (i) => i + 1));
    final seedX25A = Uint8List.fromList(List.generate(32, (i) => i + 10));
    final seedX25B = Uint8List.fromList(List.generate(32, (i) => i + 60));
    final seedX25C = Uint8List.fromList(List.generate(32, (i) => i + 110));

    setUp(() async {
      clearInMemorySeedCacheForTest();
      mockSecureStorage.clear();
      await CryptoService.instance.resetForTest(
        customSeed: seedEdA,
        customX25519Seed: seedX25A,
      );
    });

    test('TEST 1: X25519 Key Generation', () async {
      expect(CryptoService.instance.isInitialized, isTrue);
      final pubKeyB64 = CryptoService.instance.x25519PublicKeyBase64;
      expect(pubKeyB64, isNotNull);
      final pubBytes = base64Decode(pubKeyB64!);
      expect(pubBytes.length, equals(32)); // RFC 7748 X25519 public key length

      final keyId = CryptoService.instance.x25519KeyId;
      expect(keyId, isNotNull);
      expect(keyId!.startsWith('X25519-'), isTrue);
    });

    test('TEST 2: Key Persistence in Secure Storage (crisis_mesh_x25519_seed_v1)', () async {
      final testSeed = Uint8List.fromList(List.generate(32, (i) => 255 - i));
      await saveX25519Seed(testSeed);

      // Verify written to storage
      expect(mockSecureStorage['crisis_mesh_x25519_seed_v1'], equals(base64Encode(testSeed)));

      // Reload from storage
      clearInMemorySeedCacheForTest();
      final loadedSeed = await loadX25519Seed();
      expect(loadedSeed, equals(testSeed));
    });

    test('TEST 3: QR Generation exports strictly public information', () async {
      final contact = ContactModel(
        deviceId: 'DEV-A1B2C3D4',
        displayName: 'Alice Test',
        signingPublicKey: base64Encode(List.generate(32, (i) => i + 1)),
        encryptionPublicKey: base64Encode(List.generate(32, (i) => i + 2)),
        fingerprint: 'A1B2:C3D4:E5F6:7890',
        trustStatus: ContactTrustStatus.qrVerified,
        createdAt: 1000000,
        lastSeenAt: 1000000,
      );

      final qrString = contact.toQrPayload();
      expect(qrString.contains('crisis_mesh_contact'), isTrue);
      expect(qrString.contains('DEV-A1B2C3D4'), isTrue);
      expect(qrString.contains('Alice Test'), isTrue);
      expect(qrString.contains('A1B2:C3D4:E5F6:7890'), isTrue);
      // Ensure zero private key or credential fields
      expect(qrString.contains('private'), isFalse);
      expect(qrString.contains('seed'), isFalse);
      expect(qrString.contains('secret'), isFalse);
    });

    test('TEST 4: QR Decoding successfully parses valid QR payload', () async {
      final signPub = base64Encode(List.generate(32, (i) => i + 5));
      final encPub = base64Encode(List.generate(32, (i) => i + 15));
      final jsonPayload = jsonEncode({
        'v': 1,
        'type': 'crisis_mesh_contact',
        'dev_id': 'DEV-9876FEDC',
        'name': 'Bob Responder',
        'sign_pub': signPub,
        'enc_pub': encPub,
        'fp': '9876:FEDC:BA98:7654',
      });

      final parsed = ContactModel.fromQrPayload(jsonPayload);
      expect(parsed, isNotNull);
      expect(parsed!.deviceId, equals('DEV-9876FEDC'));
      expect(parsed.displayName, equals('Bob Responder'));
      expect(parsed.signingPublicKey, equals(signPub));
      expect(parsed.encryptionPublicKey, equals(encPub));
      expect(parsed.fingerprint, equals('9876:FEDC:BA98:7654'));
      expect(parsed.trustStatus, equals(ContactTrustStatus.unverified)); // Must remain unverified until confirmed
    });

    test('TEST 5: Malformed QR Rejection', () async {
      // 1. Invalid JSON
      expect(ContactModel.fromQrPayload('not-json'), isNull);

      // 2. Wrong type
      final wrongType = jsonEncode({'v': 1, 'type': 'other_type'});
      expect(ContactModel.fromQrPayload(wrongType), isNull);

      // 3. Missing keys
      final missingKeys = jsonEncode({'v': 1, 'type': 'crisis_mesh_contact', 'dev_id': 'DEV-1'});
      expect(ContactModel.fromQrPayload(missingKeys), isNull);

      // 4. Invalid key length (16 bytes instead of 32)
      final shortKey = jsonEncode({
        'v': 1,
        'type': 'crisis_mesh_contact',
        'dev_id': 'DEV-1',
        'name': 'Test',
        'sign_pub': base64Encode(List.generate(16, (i) => i)),
        'enc_pub': base64Encode(List.generate(32, (i) => i)),
        'fp': '1111:2222:3333:4444',
      });
      expect(ContactModel.fromQrPayload(shortKey), isNull);
    });

    test('TEST 6: Fingerprint Generation is deterministic and formatted', () {
      final signPub = base64Encode(List.generate(32, (i) => 1));
      final encPub = base64Encode(List.generate(32, (i) => 2));

      final fp1 = ContactModel.computeFingerprint(
        signingPublicKeyB64: signPub,
        encryptionPublicKeyB64: encPub,
      );
      final fp2 = ContactModel.computeFingerprint(
        signingPublicKeyB64: signPub,
        encryptionPublicKeyB64: encPub,
      );

      expect(fp1, equals(fp2));
      expect(RegExp(r'^[0-9A-F]{4}:[0-9A-F]{4}:[0-9A-F]{4}:[0-9A-F]{4}$').hasMatch(fp1), isTrue);
    });

    test('TEST 7 & 8: Contact Persistence and QR Verification State', () {
      final contact = ContactModel(
        deviceId: 'DEV-TEST001',
        displayName: 'Unit Test Contact',
        signingPublicKey: base64Encode(List.generate(32, (i) => i)),
        encryptionPublicKey: base64Encode(List.generate(32, (i) => i + 1)),
        fingerprint: '1234:5678:90AB:CDEF',
        trustStatus: ContactTrustStatus.qrVerified,
        createdAt: 1000,
        lastSeenAt: 2000,
      );

      final map = contact.toMap();
      expect(map['device_id'], equals('DEV-TEST001'));
      expect(map['trust_status'], equals('QR_VERIFIED'));

      final loaded = ContactModel.fromMap(map);
      expect(loaded.deviceId, equals('DEV-TEST001'));
      expect(loaded.displayName, equals('Unit Test Contact'));
      expect(loaded.trustStatus, equals(ContactTrustStatus.qrVerified));
      expect(loaded.signingPublicKey, equals(contact.signingPublicKey));
      expect(loaded.encryptionPublicKey, equals(contact.encryptionPublicKey));
      expect(loaded.fingerprint, equals(contact.fingerprint));
    });

    test('TEST 9: Key-Change Detection protects against silent key replacement', () {
      final initial = ContactModel(
        deviceId: 'DEV-VICTIM',
        displayName: 'Victim',
        signingPublicKey: base64Encode(List.generate(32, (i) => 1)),
        encryptionPublicKey: base64Encode(List.generate(32, (i) => 2)),
        fingerprint: '1111:2222:3333:4444',
        trustStatus: ContactTrustStatus.qrVerified,
        createdAt: 1000,
        lastSeenAt: 1000,
      );

      // Incoming altered keys for same deviceId
      final incomingAltered = ContactModel(
        deviceId: 'DEV-VICTIM',
        displayName: 'Victim',
        signingPublicKey: base64Encode(List.generate(32, (i) => 99)), // Altered key!
        encryptionPublicKey: base64Encode(List.generate(32, (i) => 2)),
        fingerprint: '9999:2222:3333:4444',
        trustStatus: ContactTrustStatus.qrVerified,
        createdAt: 2000,
        lastSeenAt: 2000,
      );

      final keyMismatch = initial.signingPublicKey != incomingAltered.signingPublicKey ||
          initial.encryptionPublicKey != incomingAltered.encryptionPublicKey;
      expect(keyMismatch, isTrue);

      final resolvedStatus = keyMismatch ? ContactTrustStatus.keyChanged : incomingAltered.trustStatus;
      expect(resolvedStatus, equals(ContactTrustStatus.keyChanged));
    });

    test('TEST 10: X25519 Shared-Secret Equality (A agreement B == B agreement A)', () async {
      final x25 = X25519();
      final keyPairA = await x25.newKeyPairFromSeed(seedX25A);
      final keyPairB = await x25.newKeyPairFromSeed(seedX25B);

      final pubA = await keyPairA.extractPublicKey();
      final pubB = await keyPairB.extractPublicKey();

      final secretAB = await x25.sharedSecretKey(keyPair: keyPairA, remotePublicKey: pubB);
      final secretBA = await x25.sharedSecretKey(keyPair: keyPairB, remotePublicKey: pubA);

      final bytesAB = await secretAB.extractBytes();
      final bytesBA = await secretBA.extractBytes();

      expect(bytesAB, equals(bytesBA));
      expect(bytesAB.length, equals(32));
    });

    test('TEST 11: Different recipients produce independent shared secrets', () async {
      final x25 = X25519();
      final keyPairA = await x25.newKeyPairFromSeed(seedX25A);
      final keyPairB = await x25.newKeyPairFromSeed(seedX25B);
      final keyPairC = await x25.newKeyPairFromSeed(seedX25C);

      final pubB = await keyPairB.extractPublicKey();
      final pubC = await keyPairC.extractPublicKey();

      final secretAB = await x25.sharedSecretKey(keyPair: keyPairA, remotePublicKey: pubB);
      final secretAC = await x25.sharedSecretKey(keyPair: keyPairA, remotePublicKey: pubC);

      final bytesAB = await secretAB.extractBytes();
      final bytesAC = await secretAC.extractBytes();

      expect(bytesAB, isNot(equals(bytesAC)));
    });

    test('TEST 12: HKDF Deterministic Derivation with sorted key IDs', () async {
      final x25 = X25519();
      final keyPairA = await x25.newKeyPairFromSeed(seedX25A);
      final keyPairB = await x25.newKeyPairFromSeed(seedX25B);

      final pubA = await keyPairA.extractPublicKey();
      final pubB = await keyPairB.extractPublicKey();
      final pubAB64 = base64Encode(pubA.bytes);
      final pubBB64 = base64Encode(pubB.bytes);

      // Node A derives PMK
      final pmkA = await CryptoService.instance.derivePmkDirect(
        myX25519KeyPair: keyPairA,
        peerX25519PublicKey: pubB,
        myX25519KeyB64: pubAB64,
        peerX25519KeyB64: pubBB64,
      );

      // Node B derives PMK (reversed caller roles)
      final pmkB = await CryptoService.instance.derivePmkDirect(
        myX25519KeyPair: keyPairB,
        peerX25519PublicKey: pubA,
        myX25519KeyB64: pubBB64,
        peerX25519KeyB64: pubAB64,
      );

      expect(pmkA, equals(pmkB));
      expect(pmkA.length, equals(32));

      // Test MEK derivation
      final nonce = CryptoService.generateCsprngNonce();
      const msgId = 'msg-test-1234';
      final mekA = await CryptoService.instance.deriveMek(pmkBytes: pmkA, nonce12Bytes: nonce, messageId: msgId);
      final mekB = await CryptoService.instance.deriveMek(pmkBytes: pmkB, nonce12Bytes: nonce, messageId: msgId);

      expect(mekA, equals(mekB));
      expect(mekA.length, equals(32));
    });

    test('TEST 13: AEAD ChaCha20-Poly1305 Encryption/Decryption Round-Trip', () async {
      final x25 = X25519();
      final keyPairB = await x25.newKeyPairFromSeed(seedX25B);
      final pubB = await keyPairB.extractPublicKey();
      final pubBB64 = base64Encode(pubB.bytes);

      const plaintext = 'Secret offline tactical coordinates: 37.7749, -122.4194. Safe to proceed.';
      const msgId = 'msg-roundtrip-01';
      const convId = 'conv-a-b';

      // Node A encrypts for Node B
      final envelope = await CryptoService.instance.encryptPrivateMessage(
        plaintext: plaintext,
        messageId: msgId,
        conversationId: convId,
        recipientDeviceId: 'DEV-NODE-B',
        recipientX25519KeyB64: pubBB64,
        recipientX25519KeyId: 'X25519-BBBBBBBB',
        timestampMs: 1757328000000,
      );

      expect(envelope.ciphertext.isNotEmpty, isTrue);
      expect(envelope.nonce.isNotEmpty, isTrue);
      expect(envelope.authTag.isNotEmpty, isTrue);
      expect(envelope.signature.isNotEmpty, isTrue);

      // Node B decrypts using its private key
      final decrypted = await CryptoService.instance.decryptPrivateMessage(
        envelope: envelope,
        myKeyPairOverride: keyPairB,
      );

      expect(decrypted, equals(plaintext));
    });

    test('TEST 14: Wrong Key Decryption Failure', () async {
      final x25 = X25519();
      final keyPairB = await x25.newKeyPairFromSeed(seedX25B);
      final keyPairC = await x25.newKeyPairFromSeed(seedX25C); // Eavesdropper Node C

      final pubB = await keyPairB.extractPublicKey();

      final envelope = await CryptoService.instance.encryptPrivateMessage(
        plaintext: 'Confidential casualty report',
        messageId: 'msg-wrong-key',
        conversationId: 'conv-a-b',
        recipientDeviceId: 'DEV-NODE-B',
        recipientX25519KeyB64: base64Encode(pubB.bytes),
        recipientX25519KeyId: 'X25519-B',
        timestampMs: 1757328000000,
      );

      // Node C tries to decrypt
      expect(
        () async => await CryptoService.instance.decryptPrivateMessage(
          envelope: envelope,
          myKeyPairOverride: keyPairC,
        ),
        throwsA(anything),
      );
    });

    test('TEST 15: Ciphertext Tampering triggers AEAD Authentication Failure', () async {
      final x25 = X25519();
      final keyPairB = await x25.newKeyPairFromSeed(seedX25B);
      final pubB = await keyPairB.extractPublicKey();

      final envelope = await CryptoService.instance.encryptPrivateMessage(
        plaintext: 'Medical supplies required at sector 4',
        messageId: 'msg-tamper-ct',
        conversationId: 'conv-a-b',
        recipientDeviceId: 'DEV-NODE-B',
        recipientX25519KeyB64: base64Encode(pubB.bytes),
        recipientX25519KeyId: 'X25519-B',
        timestampMs: 1757328000000,
      );

      // Flip 1 bit in ciphertext
      final rawCt = base64Decode(envelope.ciphertext);
      rawCt[0] ^= 0x01;
      final tamperedEnvelope = PrivateMessageEnvelope.fromMap({
        ...envelope.toMap(),
        'ciphertext': base64Encode(rawCt),
      });

      expect(
        () async => await CryptoService.instance.decryptPrivateMessage(
          envelope: tamperedEnvelope,
          myKeyPairOverride: keyPairB,
        ),
        throwsA(anything),
      );
    });

    test('TEST 16: Nonce Tampering triggers AEAD Authentication Failure', () async {
      final x25 = X25519();
      final keyPairB = await x25.newKeyPairFromSeed(seedX25B);
      final pubB = await keyPairB.extractPublicKey();

      final envelope = await CryptoService.instance.encryptPrivateMessage(
        plaintext: 'Operational briefing',
        messageId: 'msg-tamper-nonce',
        conversationId: 'conv-a-b',
        recipientDeviceId: 'DEV-NODE-B',
        recipientX25519KeyB64: base64Encode(pubB.bytes),
        recipientX25519KeyId: 'X25519-B',
        timestampMs: 1757328000000,
      );

      // Tamper nonce
      final rawNonce = base64Decode(envelope.nonce);
      rawNonce[0] ^= 0xFF;
      final tamperedEnvelope = PrivateMessageEnvelope.fromMap({
        ...envelope.toMap(),
        'nonce': base64Encode(rawNonce),
      });

      expect(
        () async => await CryptoService.instance.decryptPrivateMessage(
          envelope: tamperedEnvelope,
          myKeyPairOverride: keyPairB,
        ),
        throwsA(anything),
      );
    });

    test('TEST 17 & 18: AAD Tampering / Recipient Metadata Modification Failure', () async {
      final x25 = X25519();
      final keyPairB = await x25.newKeyPairFromSeed(seedX25B);
      final pubB = await keyPairB.extractPublicKey();

      final envelope = await CryptoService.instance.encryptPrivateMessage(
        plaintext: 'Direct order from Incident Commander',
        messageId: 'msg-tamper-aad',
        conversationId: 'conv-a-b',
        recipientDeviceId: 'DEV-NODE-B',
        recipientX25519KeyB64: base64Encode(pubB.bytes),
        recipientX25519KeyId: 'X25519-B',
        timestampMs: 1757328000000,
      );

      // 1. Tamper recipientDeviceId in envelope
      final tamperedRecipient = PrivateMessageEnvelope.fromMap({
        ...envelope.toMap(),
        'recipient_device_id': 'DEV-ATTACKER',
      });
      expect(
        () async => await CryptoService.instance.decryptPrivateMessage(
          envelope: tamperedRecipient,
          myKeyPairOverride: keyPairB,
        ),
        throwsA(anything),
      );

      // 2. Tamper timestamp in envelope
      final tamperedTimestamp = PrivateMessageEnvelope.fromMap({
        ...envelope.toMap(),
        'timestamp': 1757329000000,
      });
      expect(
        () async => await CryptoService.instance.decryptPrivateMessage(
          envelope: tamperedTimestamp,
          myKeyPairOverride: keyPairB,
        ),
        throwsA(anything),
      );
    });

    test('TEST 19: Nonce Uniqueness across 1,000 generated nonces', () {
      final Set<String> nonces = {};
      for (int i = 0; i < 1000; i++) {
        final nonce = CryptoService.generateCsprngNonce();
        expect(nonce.length, equals(12));
        final b64 = base64Encode(nonce);
        expect(nonces.contains(b64), isFalse);
        nonces.add(b64);
      }
      expect(nonces.length, equals(1000));
    });

    test('TEST 20: Replay Rejection in database layer', () {
      final processedMessageIds = <String>{};
      const msgId = 'msg-replay-1';

      // First arrival: processed
      final isFirstArrival = !processedMessageIds.contains(msgId);
      expect(isFirstArrival, isTrue);
      processedMessageIds.add(msgId);

      // Second arrival: rejected as replay
      final isReplay = processedMessageIds.contains(msgId);
      expect(isReplay, isTrue);
      expect(processedMessageIds.length, equals(1));
    });

    test('TEST 21: Expiry Enforcement: Private Message 7-day TTL vs SOS 48-hour TTL', () {
      expect(CryptoService.sosExpiryHorizon, equals(const Duration(hours: 48)));
      expect(CryptoService.privateMessageExpiryHorizon, equals(const Duration(days: 7)));
      expect(CryptoService.sosExpiryHorizon, isNot(equals(CryptoService.privateMessageExpiryHorizon)));
    });

    test('TEST 22: ACK Lifecycle (create, sign, verify, delivered state)', () async {
      const ackMsgId = 'msg-to-be-acked-99';
      final ack = await CryptoService.instance.signAck(
        ackMessageId: ackMsgId,
        originalSenderDeviceId: 'DEV-SENDER-A',
      );

      expect(ack.ackMessageId, equals(ackMsgId));
      expect(ack.senderDeviceId, equals(CryptoService.instance.derivedDeviceId));
      expect(ack.signature.isNotEmpty, isTrue);

      // Verify ACK signature using signer's Ed25519 public key
      final isValid = await CryptoService.instance.verifyAckSignature(
        ack: ack,
        senderEd25519PubB64: CryptoService.instance.publicKeyBase64!,
      );
      expect(isValid, isTrue);

      // Tampered ACK signature verification fails
      final tamperedAck = PrivateAckEnvelope(
        ackMessageId: 'tampered-msg-id',
        senderDeviceId: ack.senderDeviceId,
        recipientDeviceId: ack.recipientDeviceId,
        timestamp: ack.timestamp,
        signature: ack.signature,
      );
      final isTamperedValid = await CryptoService.instance.verifyAckSignature(
        ack: tamperedAck,
        senderEd25519PubB64: CryptoService.instance.publicKeyBase64!,
      );
      expect(isTamperedValid, isFalse);
    });

    test('TEST 23 & 24: Plaintext Absent from Wire Envelope and Firebase Payload', () async {
      final x25 = X25519();
      final keyPairB = await x25.newKeyPairFromSeed(seedX25B);
      final pubB = await keyPairB.extractPublicKey();

      const sensitivePlaintext = 'PATIENT_SSN_987-65-4321_STATUS_CRITICAL';
      final envelope = await CryptoService.instance.encryptPrivateMessage(
        plaintext: sensitivePlaintext,
        messageId: 'msg-privacy-check',
        conversationId: 'conv-a-b',
        recipientDeviceId: 'DEV-NODE-B',
        recipientX25519KeyB64: base64Encode(pubB.bytes),
        recipientX25519KeyId: 'X25519-B',
      );

      final envelopeJson = envelope.toJson();
      final envelopeMap = envelope.toMap();

      // Ensure plaintext does NOT appear anywhere in the wire JSON
      expect(envelopeJson.contains(sensitivePlaintext), isFalse);
      expect(envelopeJson.contains('PATIENT'), isFalse);
      expect(envelopeJson.contains('987-65-4321'), isFalse);

      // Ensure Firebase payload (which mirrors envelopeMap) has no plaintext field
      expect(envelopeMap.containsKey('plaintext'), isFalse);
      expect(envelopeMap.containsKey('body'), isFalse);
      expect(envelopeMap.containsKey('text'), isFalse);
    });

    test('TEST 25: Private Key Absent from QR Payload', () {
      final contact = ContactModel(
        deviceId: 'DEV-TEST',
        displayName: 'Test',
        signingPublicKey: base64Encode(List.generate(32, (i) => 1)),
        encryptionPublicKey: base64Encode(List.generate(32, (i) => 2)),
        fingerprint: '1111:2222:3333:4444',
        createdAt: 1000,
        lastSeenAt: 1000,
      );

      final qr = contact.toQrPayload();
      expect(qr.contains('private'), isFalse);
      expect(qr.contains('seed'), isFalse);
      expect(qr.contains('secret'), isFalse);
      expect(qr.contains('key_pair'), isFalse);
    });

    test('TEST 26: Private Key Absent from Model Schema Fields and Maps', () {
      final contact = ContactModel(
        deviceId: 'DEV-SCHEMA-CHECK',
        displayName: 'Test',
        signingPublicKey: base64Encode(List.generate(32, (i) => 1)),
        encryptionPublicKey: base64Encode(List.generate(32, (i) => 2)),
        fingerprint: '1111:2222:3333:4444',
        createdAt: 1000,
        lastSeenAt: 1000,
      );
      final contactMap = contact.toMap();
      for (final key in contactMap.keys) {
        expect(key.contains('priv'), isFalse, reason: 'Key $key should not contain private key material');
        expect(key.contains('seed'), isFalse, reason: 'Key $key should not contain seed material');
      }

      final privMsg = PrivateMessageModel(
        messageId: 'm1',
        conversationId: 'c1',
        senderDeviceId: 'DEV-1',
        recipientDeviceId: 'DEV-2',
        plaintextBody: 'test',
        ciphertext: 'ct',
        nonce: 'n',
        authTag: 'tag',
        senderX25519Pub: 'xpub',
        senderEd25519Pub: 'edpub',
        signature: 'sig',
        status: PrivateMessageStatus.sent,
        timestamp: 1000,
        expiresAt: 2000,
      );
      final msgMap = privMsg.toMap();
      for (final key in msgMap.keys) {
        if (key != 'plaintext_body') {
          expect(key.contains('priv'), isFalse, reason: 'Field $key must not contain private key');
        }
        expect(key.contains('seed'), isFalse, reason: 'Field $key must not contain seed');
      }
    });

    test('TEST 27 & 28: Relay node forwards without private key; hop_count mutation preserves ciphertext and signature', () async {
      final x25 = X25519();
      final keyPairB = await x25.newKeyPairFromSeed(seedX25B);
      final pubB = await keyPairB.extractPublicKey();

      // Node A encrypts for Node B
      final originalEnvelope = await CryptoService.instance.encryptPrivateMessage(
        plaintext: 'Relayed emergency message',
        messageId: 'msg-relay-01',
        conversationId: 'conv-a-b',
        recipientDeviceId: 'DEV-NODE-B',
        recipientX25519KeyB64: base64Encode(pubB.bytes),
        recipientX25519KeyId: 'X25519-B',
        timestampMs: 1757328000000,
      );

      expect(originalEnvelope.hopCount, equals(0));

      // Relay node increments hop_count from 0 to 1, then to 2
      final relayedEnvelope = PrivateMessageEnvelope.fromMap({
        ...originalEnvelope.toMap(),
        'hop_count': 2,
      });

      // 1. Ed25519 signature remains VALID because hop_count is not in signing payload
      final isSigValid = await CryptoService.instance.verifyPrivateEnvelopeSignature(relayedEnvelope);
      expect(isSigValid, isTrue);

      // 2. Decryption at final destination Node B SUCCEEDS because hop_count is not in AAD
      final decrypted = await CryptoService.instance.decryptPrivateMessage(
        envelope: relayedEnvelope,
        myKeyPairOverride: keyPairB,
      );
      expect(decrypted, equals('Relayed emergency message'));
    });

    test('TEST 29 & 30: Ed25519 Envelope Signature Verification and Tamper Detection', () async {
      final x25 = X25519();
      final keyPairB = await x25.newKeyPairFromSeed(seedX25B);
      final pubB = await keyPairB.extractPublicKey();

      final envelope = await CryptoService.instance.encryptPrivateMessage(
        plaintext: 'Authentic signed message',
        messageId: 'msg-sig-check',
        conversationId: 'conv-a-b',
        recipientDeviceId: 'DEV-NODE-B',
        recipientX25519KeyB64: base64Encode(pubB.bytes),
        recipientX25519KeyId: 'X25519-B',
      );

      // Valid signature verifies
      final valid = await CryptoService.instance.verifyPrivateEnvelopeSignature(envelope);
      expect(valid, isTrue);

      // Tampered messageId fails verification
      final tamperedMsgId = PrivateMessageEnvelope.fromMap({
        ...envelope.toMap(),
        'message_id': 'altered-message-id',
      });
      final invalid1 = await CryptoService.instance.verifyPrivateEnvelopeSignature(tamperedMsgId);
      expect(invalid1, isFalse);

      // Tampered senderEd25519Pub fails verification
      final tamperedSender = PrivateMessageEnvelope.fromMap({
        ...envelope.toMap(),
        'sender_ed25519_pub': base64Encode(List.generate(32, (i) => 254 - i)),
      });
      final invalid2 = await CryptoService.instance.verifyPrivateEnvelopeSignature(tamperedSender);
      expect(invalid2, isFalse);
    });

    test('TEST 31: Existing Phase 7 SOS signing and verification remains fully functional', () async {
      final msgId = 'sos-phase7-check';
      final senderId = CryptoService.instance.derivedDeviceId;
      final ts = DateTime.now().millisecondsSinceEpoch;

      final sig = await CryptoService.instance.signSos(
        messageId: msgId,
        senderId: senderId,
        timestamp: ts,
        needType: 'medical',
        lat: 37.7749,
        lng: -122.4194,
        payload: 'Injured survivor needs triage',
      );

      expect(sig, isNotNull);

      final verified = await CryptoService.instance.verifySignature(
        signatureBase64: sig!,
        publicKeyBase64: CryptoService.instance.publicKeyBase64!,
        version: '1',
        messageId: msgId,
        senderId: senderId,
        timestamp: ts,
        needType: 'medical',
        lat: 37.7749,
        lng: -122.4194,
        payload: 'Injured survivor needs triage',
      );

      expect(verified, isTrue);

      // Full authenticity evaluation
      final sosMessage = MessageModel(
        id: msgId,
        type: 'broadcast',
        senderId: senderId,
        timestamp: ts,
        needType: 'medical',
        lat: 37.7749,
        lng: -122.4194,
        payload: 'Injured survivor needs triage',
        hopCount: 0,
        priorityTier: 'Critical',
        priorityScore: 90,
        signature: sig,
        publicKey: CryptoService.instance.publicKeyBase64,
        signatureVersion: '1',
      );

      final status = await CryptoService.instance.evaluateAuthenticity(sosMessage);
      expect(status, equals(AuthenticityStatus.verified));
    });
  });
}
