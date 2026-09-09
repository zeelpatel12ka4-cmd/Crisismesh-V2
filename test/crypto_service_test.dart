import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_app1/core/crypto/crypto_service.dart';
import 'package:flutter_app1/core/crypto/key_storage_io.dart';
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
          mockSecureStorage[methodCall.arguments['key'] as String] = methodCall.arguments['value'] as String;
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

  group('Phase 7: Message Authenticity & Anti-Fake SOS Cryptographic Tests', () {
    // 32-byte deterministic seed for Test Node A
    final seedA = Uint8List.fromList(List.generate(32, (i) => i + 1));
    // 32-byte deterministic seed for Test Node B
    final seedB = Uint8List.fromList(List.generate(32, (i) => 100 + i));

    setUp(() async {
      await CryptoService.instance.resetForTest(customSeed: seedA);
    });

    test('TEST 1 & 2 & 3: Ed25519 key generation, public key extraction, and deterministic device ID', () async {
      expect(CryptoService.instance.isInitialized, isTrue);
      final pubKey = CryptoService.instance.publicKeyBase64;
      expect(pubKey, isNotNull);
      expect(base64Decode(pubKey!).length, equals(32)); // Exact 32 bytes for Ed25519

      final deviceId = CryptoService.instance.derivedDeviceId;
      expect(deviceId.startsWith('DEV-'), isTrue);
      expect(deviceId.length, equals(12)); // 'DEV-' + 8 hex chars
    });

    test('TEST 4 & 5: SOS Signing and Verification on valid message', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final sig = await CryptoService.instance.signSos(
        messageId: 'msg-001',
        senderId: CryptoService.instance.derivedDeviceId,
        timestamp: now,
        needType: 'medical',
        lat: 37.774900,
        lng: -122.419400,
        payload: 'Injured victim requires assistance',
      );

      expect(sig, isNotNull);
      expect(base64Decode(sig!).length, equals(64)); // Exact 64 bytes for Ed25519

      final isValid = await CryptoService.instance.verifySignature(
        signatureBase64: sig,
        publicKeyBase64: CryptoService.instance.publicKeyBase64!,
        version: '1',
        messageId: 'msg-001',
        senderId: CryptoService.instance.derivedDeviceId,
        timestamp: now,
        needType: 'medical',
        lat: 37.774900,
        lng: -122.419400,
        payload: 'Injured victim requires assistance',
      );

      expect(isValid, isTrue);
    });

    test('TEST 6: Payload modification invalidates signature ("I am trapped" -> "I am safe")', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final sig = await CryptoService.instance.signSos(
        messageId: 'msg-tamper-payload',
        senderId: CryptoService.instance.derivedDeviceId,
        timestamp: now,
        needType: 'trapped',
        lat: 37.774900,
        lng: -122.419400,
        payload: 'I am trapped under collapsed beam',
      );

      // Verify with modified payload
      final isValid = await CryptoService.instance.verifySignature(
        signatureBase64: sig!,
        publicKeyBase64: CryptoService.instance.publicKeyBase64!,
        version: '1',
        messageId: 'msg-tamper-payload',
        senderId: CryptoService.instance.derivedDeviceId,
        timestamp: now,
        needType: 'trapped',
        lat: 37.774900,
        lng: -122.419400,
        payload: 'I am safe, do not rescue', // Tampered!
      );

      expect(isValid, isFalse);
    });

    test('TEST 7: GPS coordinates modification invalidates signature', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final sig = await CryptoService.instance.signSos(
        messageId: 'msg-tamper-gps',
        senderId: CryptoService.instance.derivedDeviceId,
        timestamp: now,
        needType: 'medical',
        lat: 37.774900,
        lng: -122.419400,
        payload: 'Severe bleeding',
      );

      // Verify with modified coordinates (redirecting responders)
      final isValid = await CryptoService.instance.verifySignature(
        signatureBase64: sig!,
        publicKeyBase64: CryptoService.instance.publicKeyBase64!,
        version: '1',
        messageId: 'msg-tamper-gps',
        senderId: CryptoService.instance.derivedDeviceId,
        timestamp: now,
        needType: 'medical',
        lat: 38.000000, // Altered latitude!
        lng: -122.419400,
        payload: 'Severe bleeding',
      );

      expect(isValid, isFalse);
    });

    test('TEST 8 & 9 & 10 & 11: NeedType, Timestamp, SenderId, or MessageId modification fails', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final sig = await CryptoService.instance.signSos(
        messageId: 'msg-base',
        senderId: CryptoService.instance.derivedDeviceId,
        timestamp: now,
        needType: 'fire',
        lat: 37.774900,
        lng: -122.419400,
        payload: 'House on fire',
      );

      // Modified needType
      expect(
        await CryptoService.instance.verifySignature(
          signatureBase64: sig!,
          publicKeyBase64: CryptoService.instance.publicKeyBase64!,
          version: '1',
          messageId: 'msg-base',
          senderId: CryptoService.instance.derivedDeviceId,
          timestamp: now,
          needType: 'water',
          lat: 37.774900,
          lng: -122.419400,
          payload: 'House on fire',
        ),
        isFalse,
      );

      // Modified timestamp
      expect(
        await CryptoService.instance.verifySignature(
          signatureBase64: sig,
          publicKeyBase64: CryptoService.instance.publicKeyBase64!,
          version: '1',
          messageId: 'msg-base',
          senderId: CryptoService.instance.derivedDeviceId,
          timestamp: now + 5000,
          needType: 'fire',
          lat: 37.774900,
          lng: -122.419400,
          payload: 'House on fire',
        ),
        isFalse,
      );

      // Modified senderId
      expect(
        await CryptoService.instance.verifySignature(
          signatureBase64: sig,
          publicKeyBase64: CryptoService.instance.publicKeyBase64!,
          version: '1',
          messageId: 'msg-base',
          senderId: 'DEV-FORGED',
          timestamp: now,
          needType: 'fire',
          lat: 37.774900,
          lng: -122.419400,
          payload: 'House on fire',
        ),
        isFalse,
      );

      // Modified messageId
      expect(
        await CryptoService.instance.verifySignature(
          signatureBase64: sig,
          publicKeyBase64: CryptoService.instance.publicKeyBase64!,
          version: '1',
          messageId: 'msg-fake-id',
          senderId: CryptoService.instance.derivedDeviceId,
          timestamp: now,
          needType: 'fire',
          lat: 37.774900,
          lng: -122.419400,
          payload: 'House on fire',
        ),
        isFalse,
      );
    });

    test('TEST 12: Public-key substitution fails verification', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final sig = await CryptoService.instance.signSos(
        messageId: 'msg-sub-key',
        senderId: CryptoService.instance.derivedDeviceId,
        timestamp: now,
        needType: 'medical',
        lat: 37.774900,
        lng: -122.419400,
        payload: 'Original SOS',
      );

      // Re-init with Seed B to get different public key
      final keyB = CryptoService.instance;
      await keyB.resetForTest(customSeed: seedB);
      final pubKeyB = keyB.publicKeyBase64;

      // Verify with Key B
      final isValid = await CryptoService.instance.verifySignature(
        signatureBase64: sig!,
        publicKeyBase64: pubKeyB!,
        version: '1',
        messageId: 'msg-sub-key',
        senderId: 'DEV-A',
        timestamp: now,
        needType: 'medical',
        lat: 37.774900,
        lng: -122.419400,
        payload: 'Original SOS',
      );

      expect(isValid, isFalse);
    });

    test('TEST 13 & 14: Deterministic canonicalization produces exact identical bytes', () {
      final bytes1 = CryptoService.buildCanonicalBytes(
        version: '1',
        messageId: 'id-100',
        senderId: 'DEV-ORIGIN',
        publicKey: 'pubkey123',
        timestamp: 1756850000000,
        needType: 'medical',
        lat: 37.774900,
        lng: -122.419400,
        payload: 'Need oxygen',
      );

      final bytes2 = CryptoService.buildCanonicalBytes(
        version: '1',
        messageId: 'id-100',
        senderId: 'DEV-ORIGIN',
        publicKey: 'pubkey123',
        timestamp: 1756850000000,
        needType: 'MEDICAL ', // Trims & lowercases
        lat: 37.7749001, // Formats to 6 decimals
        lng: -122.4194002,
        payload: 'Need oxygen ',
      );

      expect(utf8.decode(bytes1), equals(utf8.decode(bytes2)));
    });

    test('TEST 15 & 16 & 17: Relay-mutable fields (hop_count, sync, priority) do NOT invalidate signature', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final sig = await CryptoService.instance.signSos(
        messageId: 'msg-relay-hop',
        senderId: CryptoService.instance.derivedDeviceId,
        timestamp: now,
        needType: 'shelter',
        lat: 37.774900,
        lng: -122.419400,
        payload: 'Shelter collapsed',
      );

      // Node A creates message with hopCount = 0
      final original = MessageModel(
        id: 'msg-relay-hop',
        type: 'broadcast',
        senderId: CryptoService.instance.derivedDeviceId,
        payload: 'Shelter collapsed',
        needType: 'shelter',
        lat: 37.774900,
        lng: -122.419400,
        timestamp: now,
        hopCount: 0,
        priorityTier: 'Urgent',
        priorityScore: 7,
        signature: sig,
        publicKey: CryptoService.instance.publicKeyBase64,
        signatureVersion: '1',
        authenticityStatus: AuthenticityStatus.verified,
      );

      expect(await CryptoService.instance.evaluateAuthenticity(original), equals(AuthenticityStatus.verified));

      // Node B receives and relays: increments hopCount (0 -> 1) and changes meshDeliveryStatus
      final relayedHop1 = original.copyWith(
        hopCount: 1,
        meshDeliveryStatus: MeshDeliveryStatus.transmittedToPeer,
        priorityScore: 8, // Local node triage score adjustment
        synced: true,
      );

      // Node B verifies: signature MUST REMAIN VERIFIED!
      expect(await CryptoService.instance.evaluateAuthenticity(relayedHop1), equals(AuthenticityStatus.verified));

      // Node C receives and relays: increments hopCount (1 -> 2)
      final relayedHop2 = relayedHop1.copyWith(hopCount: 2);
      expect(await CryptoService.instance.evaluateAuthenticity(relayedHop2), equals(AuthenticityStatus.verified));
    });

    test('TEST 18: Duplicate message check', () async {
      final msg = MessageModel(
        id: 'msg-dup-1',
        type: 'broadcast',
        senderId: 'DEV-ORIGIN',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        hopCount: 0,
        priorityTier: 'Low',
        priorityScore: 1,
        signature: 'valid_sig',
        publicKey: 'valid_pub',
      );

      final status = await CryptoService.instance.evaluateAuthenticity(msg, isDuplicate: true);
      expect(status, equals(AuthenticityStatus.replayed));
    });

    test('TEST 19: Stale message rejection according to 48-hour Master Spec policy', () async {
      final pastTime = DateTime.now().subtract(const Duration(hours: 49)).millisecondsSinceEpoch;
      final sig = await CryptoService.instance.signSos(
        messageId: 'msg-stale',
        senderId: CryptoService.instance.derivedDeviceId,
        timestamp: pastTime,
        needType: 'water',
        lat: 37.774900,
        lng: -122.419400,
        payload: 'Old message',
      );

      final staleMsg = MessageModel(
        id: 'msg-stale',
        type: 'broadcast',
        senderId: CryptoService.instance.derivedDeviceId,
        timestamp: pastTime,
        needType: 'water',
        lat: 37.774900,
        lng: -122.419400,
        payload: 'Old message',
        hopCount: 0,
        priorityTier: 'Low',
        priorityScore: 1,
        signature: sig,
        publicKey: CryptoService.instance.publicKeyBase64,
      );

      final status = await CryptoService.instance.evaluateAuthenticity(staleMsg);
      expect(status, equals(AuthenticityStatus.stale));
    });

    test('TEST 20: Future timestamp rejection (>10 minutes clock skew)', () async {
      final futureTime = DateTime.now().add(const Duration(minutes: 15)).millisecondsSinceEpoch;
      final sig = await CryptoService.instance.signSos(
        messageId: 'msg-future',
        senderId: CryptoService.instance.derivedDeviceId,
        timestamp: futureTime,
        needType: 'food',
        lat: 37.774900,
        lng: -122.419400,
        payload: 'Future SOS',
      );

      final futureMsg = MessageModel(
        id: 'msg-future',
        type: 'broadcast',
        senderId: CryptoService.instance.derivedDeviceId,
        timestamp: futureTime,
        needType: 'food',
        lat: 37.774900,
        lng: -122.419400,
        payload: 'Future SOS',
        hopCount: 0,
        priorityTier: 'Low',
        priorityScore: 1,
        signature: sig,
        publicKey: CryptoService.instance.publicKeyBase64,
      );

      final status = await CryptoService.instance.evaluateAuthenticity(futureMsg);
      expect(status, equals(AuthenticityStatus.futureClock));
    });

    test('TEST 21: Rate limiting triggers on >5 SOS messages within 60 seconds per sender key', () async {
      const senderKey = 'TEST_FLOOD_KEY_123';
      final now = DateTime.now().millisecondsSinceEpoch;

      // 5 requests succeed
      for (int i = 0; i < 5; i++) {
        expect(CryptoService.instance.checkRateLimit(senderKey, nowMs: now + i * 100), isTrue);
      }

      // 6th request within 60 seconds MUST trigger rate limit
      expect(CryptoService.instance.checkRateLimit(senderKey, nowMs: now + 1000), isFalse);
    });

    test('TEST 22: Trust-On-First-Use (TOFU) detects key mismatch for same sender ID', () {
      const sender = 'DEV-TOFU-TEST';
      const key1 = 'PUB_KEY_VERSION_1';
      const key2 = 'PUB_KEY_VERSION_2';

      // First seen
      expect(CryptoService.instance.checkTofuKey(sender, key1), equals(TofuStatus.firstSeen));

      // Matched on repeat
      expect(CryptoService.instance.checkTofuKey(sender, key1), equals(TofuStatus.matched));

      // Key mismatch -> untrusted
      expect(CryptoService.instance.checkTofuKey(sender, key2), equals(TofuStatus.untrustedKeyMismatch));
    });

    test('TEST 23: Legacy unsigned message evaluates to UNVERIFIED for backward compatibility', () async {
      final legacy = MessageModel(
        id: 'msg-legacy',
        type: 'broadcast',
        senderId: 'DEV-LEGACY',
        payload: 'Legacy payload without signature',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        hopCount: 0,
        priorityTier: 'Low',
        priorityScore: 1,
      );

      expect(await CryptoService.instance.evaluateAuthenticity(legacy), equals(AuthenticityStatus.unverified));
    });

    test('TEST 24: Tampered message evaluates to INVALID_SIGNATURE', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final sig = await CryptoService.instance.signSos(
        messageId: 'msg-tamper-check',
        senderId: CryptoService.instance.derivedDeviceId,
        timestamp: now,
        needType: 'medical',
        lat: 37.774900,
        lng: -122.419400,
        payload: 'Original Text',
      );

      final tamperedMsg = MessageModel(
        id: 'msg-tamper-check',
        type: 'broadcast',
        senderId: CryptoService.instance.derivedDeviceId,
        timestamp: now,
        needType: 'medical',
        lat: 37.774900,
        lng: -122.419400,
        payload: 'Tampered Text', // modified!
        hopCount: 0,
        priorityTier: 'Low',
        priorityScore: 1,
        signature: sig,
        publicKey: CryptoService.instance.publicKeyBase64,
      );

      expect(await CryptoService.instance.evaluateAuthenticity(tamperedMsg), equals(AuthenticityStatus.invalidSignature));
    });

    test('TEST 25: Private key storage hardening & legacy seed file one-time migration', () async {
      clearInMemorySeedCacheForTest();

      // Simulate a legacy installation that had crisis_mesh_key.bin
      final dir = await getApplicationDocumentsDirectory();
      final legacyFile = File('${dir.path}/crisis_mesh_key.bin');
      final legacySeed = Uint8List.fromList(List.generate(32, (i) => 255 - i));
      await legacyFile.writeAsBytes(legacySeed, flush: true);
      expect(await legacyFile.exists(), isTrue);

      // Trigger loadKeySeed() which must detect, migrate into secure storage, and shred the legacy file
      final loadedSeed = await loadKeySeed();
      expect(loadedSeed, isNotNull);
      expect(loadedSeed, equals(legacySeed));

      // Verify the legacy plain-text file was securely purged from disk
      expect(await legacyFile.exists(), isFalse);

      // Verify future loads succeed from secure storage
      clearInMemorySeedCacheForTest();
      final reloadedSeed = await loadKeySeed();
      expect(reloadedSeed, isNotNull);
      expect(reloadedSeed, equals(legacySeed));
    });
  });
}
