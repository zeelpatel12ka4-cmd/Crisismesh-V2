import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'key_storage.dart';
import '../models/message_model.dart';
import '../models/private_message_model.dart';

/// Explicit authenticity outcomes according to Master Spec
class AuthenticityStatus {
  static const String verified = 'verified';
  static const String invalidSignature = 'invalid_signature';
  static const String stale = 'stale';
  static const String futureClock = 'future_clock';
  static const String replayed = 'replayed';
  static const String untrustedKeyMismatch = 'untrusted_key_mismatch';
  static const String rateLimited = 'rate_limited';
  static const String unverified = 'unverified';

  static String badgeText(String status) {
    switch (status) {
      case verified:
        return 'Verified';
      case invalidSignature:
        return 'Tampered';
      case stale:
        return 'Expired';
      case futureClock:
        return 'Future Clock';
      case replayed:
        return 'Duplicate';
      case untrustedKeyMismatch:
        return 'Key Mismatch';
      case rateLimited:
        return 'Rate Limited';
      case unverified:
      default:
        return 'Unverified';
    }
  }
}

enum TofuStatus {
  firstSeen,
  matched,
  untrustedKeyMismatch,
}

/// Centralized Cryptographic Service for Ed25519 SOS signing, X25519 key agreement,
/// HKDF-SHA256 key derivation, and ChaCha20-Poly1305 authenticated encryption.
class CryptoService {
  static final CryptoService instance = CryptoService._init();
  CryptoService._init();

  static const String currentSignatureVersion = '1';

  /// Standard Master Spec SOS broadcast expiry horizon (48 hours)
  static const Duration sosExpiryHorizon = Duration(hours: 48);

  /// Phase 8 Master Spec Private Message expiry horizon (7 days)
  static const Duration privateMessageExpiryHorizon = Duration(days: 7);

  /// Allowable clock skew for future timestamps (10 minutes)
  static const Duration futureTimestampTolerance = Duration(minutes: 10);

  // Ed25519 for Identity & Signing
  final Ed25519 _ed25519Algorithm = Ed25519();
  SimpleKeyPair? _keyPair;
  SimplePublicKey? _publicKey;
  String? _cachedPublicKeyBase64;
  String? _cachedDeviceId;

  // X25519 for Key Agreement (strictly separated from Ed25519)
  final X25519 _x25519Algorithm = X25519();
  SimpleKeyPair? _x25519KeyPair;
  SimplePublicKey? _x25519PublicKey;
  String? _cachedX25519PublicKeyBase64;
  String? _cachedX25519KeyId;

  // AEAD Cipher
  final Cipher _aeadCipher = Chacha20.poly1305Aead();

  // In-memory TOFU store: senderId -> publicKeyBase64
  final Map<String, String> _tofuStore = {};

  // In-memory Rate limiter: senderKey -> List<timestampMs>
  final Map<String, List<int>> _rateLimitHistory = {};

  bool get isInitialized => _keyPair != null && _x25519KeyPair != null;
  String? get publicKeyBase64 => _cachedPublicKeyBase64;
  String? get x25519PublicKeyBase64 => _cachedX25519PublicKeyBase64;
  String? get x25519KeyId => _cachedX25519KeyId;
  SimpleKeyPair? get x25519KeyPair => _x25519KeyPair;

  /// Returns the deterministic device ID derived from the Ed25519 public key fingerprint
  String get derivedDeviceId {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    if (_cachedPublicKeyBase64 != null) {
      final bytes = base64Decode(_cachedPublicKeyBase64!);
      final hexFingerprint = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      _cachedDeviceId = 'DEV-${hexFingerprint.substring(0, 8).toUpperCase()}';
      return _cachedDeviceId!;
    }
    return 'DEV-UNKNOWN';
  }

  /// Initializes both Ed25519 signing keypair and X25519 key-agreement keypair
  Future<void> init({Uint8List? customSeed, Uint8List? customX25519Seed}) async {
    if (_keyPair != null && _x25519KeyPair != null && customSeed == null && customX25519Seed == null) {
      return;
    }

    try {
      // 1. Initialize Ed25519 Identity & Signing Keypair
      if (customSeed != null) {
        _keyPair = await _ed25519Algorithm.newKeyPairFromSeed(customSeed);
      } else {
        final savedSeed = await loadKeySeed();
        if (savedSeed != null && savedSeed.length == 32) {
          _keyPair = await _ed25519Algorithm.newKeyPairFromSeed(savedSeed);
        } else {
          _keyPair = await _ed25519Algorithm.newKeyPair();
          final extracted = await _keyPair!.extractPrivateKeyBytes();
          await saveKeySeed(Uint8List.fromList(extracted));
        }
      }

      _publicKey = await _keyPair!.extractPublicKey();
      _cachedPublicKeyBase64 = base64Encode(_publicKey!.bytes);
      final hexFingerprint = _publicKey!.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      _cachedDeviceId = 'DEV-${hexFingerprint.substring(0, 8).toUpperCase()}';

      // 2. Initialize X25519 Key-Agreement Keypair
      if (customX25519Seed != null) {
        _x25519KeyPair = await _x25519Algorithm.newKeyPairFromSeed(customX25519Seed);
      } else {
        final savedX25519Seed = await loadX25519Seed();
        if (savedX25519Seed != null && savedX25519Seed.length == 32) {
          _x25519KeyPair = await _x25519Algorithm.newKeyPairFromSeed(savedX25519Seed);
        } else {
          _x25519KeyPair = await _x25519Algorithm.newKeyPair();
          final extracted = await _x25519KeyPair!.extractPrivateKeyBytes();
          await saveX25519Seed(Uint8List.fromList(extracted));
        }
      }

      _x25519PublicKey = await _x25519KeyPair!.extractPublicKey();
      _cachedX25519PublicKeyBase64 = base64Encode(_x25519PublicKey!.bytes);
      final x25519Hash = await Sha256().hash(_x25519PublicKey!.bytes);
      final x25519Hex = x25519Hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      _cachedX25519KeyId = 'X25519-${x25519Hex.substring(0, 8).toUpperCase()}';

      debugPrint('[CryptoService] Initialized Ed25519: $_cachedDeviceId, X25519 Key ID: $_cachedX25519KeyId');
    } catch (e) {
      debugPrint('[CryptoService] Initialization error: $e');
    }
  }

  // ===========================================================================
  // PHASE 8: E2EE KEY DERIVATION & AEAD ENCRYPTION / DECRYPTION
  // ===========================================================================

  /// Tier 1: Derives the 32-byte Pairwise Master Key (PMK) using HKDF-SHA256
  /// IKM: X25519 32-byte shared secret
  /// Salt: SHA-256("crisis-mesh-pmk-salt-v1")
  /// Info: `crisis-mesh-pmk-v1:<sorted public-key identifiers>`
  Future<Uint8List> derivePmk({
    required String peerX25519PublicKeyB64,
    SimpleKeyPair? myKeyPairOverride,
  }) async {
    if (_x25519KeyPair == null && myKeyPairOverride == null) await init();
    final keyPair = myKeyPairOverride ?? _x25519KeyPair!;
    final myPub = await keyPair.extractPublicKey();
    final myPubB64 = base64Encode(myPub.bytes);

    final peerPubBytes = base64Decode(peerX25519PublicKeyB64);
    final peerPublicKey = SimplePublicKey(peerPubBytes, type: KeyPairType.x25519);

    return derivePmkDirect(
      myX25519KeyPair: keyPair,
      peerX25519PublicKey: peerPublicKey,
      myX25519KeyB64: myPubB64,
      peerX25519KeyB64: peerX25519PublicKeyB64,
    );
  }

  /// Direct PMK derivation given explicit keys (used by both service and test runners)
  Future<Uint8List> derivePmkDirect({
    required SimpleKeyPair myX25519KeyPair,
    required SimplePublicKey peerX25519PublicKey,
    required String myX25519KeyB64,
    required String peerX25519KeyB64,
  }) async {
    // 1. Perform X25519 key agreement
    final sharedSecret = await _x25519Algorithm.sharedSecretKey(
      keyPair: myX25519KeyPair,
      remotePublicKey: peerX25519PublicKey,
    );
    final sharedSecretBytes = await sharedSecret.extractBytes();

    // 2. Salt: Exactly SHA-256("crisis-mesh-pmk-salt-v1") -> 32 bytes
    final saltHash = await Sha256().hash(utf8.encode('crisis-mesh-pmk-salt-v1'));
    final saltBytes = saltHash.bytes;

    // 3. Info: Canonical UTF-8 with lexicographically sorted public keys
    final sortedKeys = [myX25519KeyB64, peerX25519KeyB64]..sort();
    final infoBytes = utf8.encode('crisis-mesh-pmk-v1:${sortedKeys[0]}:${sortedKeys[1]}');

    // 4. HKDF-SHA256 derivation -> 32 bytes
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final derivedSecret = await hkdf.deriveKey(
      secretKey: SecretKey(sharedSecretBytes),
      nonce: saltBytes,
      info: infoBytes,
    );

    final pmkBytes = await derivedSecret.extractBytes();
    return Uint8List.fromList(pmkBytes);
  }

  /// Tier 2: Derives the 32-byte Message Encryption Key (MEK) using HKDF-SHA256
  /// IKM: PMK (32 bytes)
  /// Salt: 12-byte per-message CSPRNG nonce
  /// Info: `crisis-mesh-mek-v1:<message_id>`
  Future<Uint8List> deriveMek({
    required List<int> pmkBytes,
    required List<int> nonce12Bytes,
    required String messageId,
  }) async {
    final infoBytes = utf8.encode('crisis-mesh-mek-v1:$messageId');
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

    final derivedKey = await hkdf.deriveKey(
      secretKey: SecretKey(pmkBytes),
      nonce: nonce12Bytes,
      info: infoBytes,
    );

    final mekBytes = await derivedKey.extractBytes();
    return Uint8List.fromList(mekBytes);
  }

  /// Builds canonical UTF-8 deterministic AAD bytes for ChaCha20-Poly1305
  /// Format: v1|messageId|conversationId|senderId|recipientId|senderKeyId|recipientKeyId|timestampMs
  /// Excludes hop_count and any mutable routing headers!
  static Uint8List buildPrivateMessageAad({
    required String messageId,
    required String conversationId,
    required String senderDeviceId,
    required String recipientDeviceId,
    required String senderKeyId,
    required String recipientKeyId,
    required int timestampMs,
  }) {
    final aadString = 'v1|'
        '$messageId|'
        '$conversationId|'
        '$senderDeviceId|'
        '$recipientDeviceId|'
        '$senderKeyId|'
        '$recipientKeyId|'
        '$timestampMs';
    return Uint8List.fromList(utf8.encode(aadString));
  }

  /// Builds canonical UTF-8 envelope bytes signed by Ed25519
  /// Format: crisis-mesh-envelope-sig-v1|messageId|conversationId|senderId|recipientId|senderKeyId|recipientKeyId|timestampMs|nonceB64|ciphertextB64|authTagB64
  /// Strictly excludes hop_count!
  static Uint8List buildPrivateEnvelopeSignBytes({
    required String messageId,
    required String conversationId,
    required String senderDeviceId,
    required String recipientDeviceId,
    required String senderKeyId,
    required String recipientKeyId,
    required int timestampMs,
    required String nonceB64,
    required String ciphertextB64,
    required String authTagB64,
  }) {
    final signPayload = 'crisis-mesh-envelope-sig-v1|'
        '$messageId|'
        '$conversationId|'
        '$senderDeviceId|'
        '$recipientDeviceId|'
        '$senderKeyId|'
        '$recipientKeyId|'
        '$timestampMs|'
        '$nonceB64|'
        '$ciphertextB64|'
        '$authTagB64';
    return Uint8List.fromList(utf8.encode(signPayload));
  }

  /// Generates a fresh 12-byte cryptographically secure random nonce
  static Uint8List generateCsprngNonce() {
    final rng = Random.secure();
    final nonce = Uint8List(12);
    for (int i = 0; i < 12; i++) {
      nonce[i] = rng.nextInt(256);
    }
    return nonce;
  }

  /// Encrypts a private message using ChaCha20-Poly1305 with per-message MEK and AAD
  Future<PrivateMessageEnvelope> encryptPrivateMessage({
    required String plaintext,
    required String messageId,
    required String conversationId,
    required String recipientDeviceId,
    required String recipientX25519KeyB64,
    required String recipientX25519KeyId,
    int? timestampMs,
  }) async {
    if (!isInitialized) await init();

    final ts = timestampMs ?? DateTime.now().millisecondsSinceEpoch;
    final senderDeviceId = derivedDeviceId;
    final senderKeyId = _cachedX25519KeyId!;
    final senderEdPubB64 = _cachedPublicKeyBase64!;
    final senderX25PubB64 = _cachedX25519PublicKeyBase64!;

    // 1. Derive Tier 1 Pairwise Master Key (PMK)
    final pmk = await derivePmk(peerX25519PublicKeyB64: recipientX25519KeyB64);

    // 2. Generate 12-byte CSPRNG nonce
    final nonce = generateCsprngNonce();

    // 3. Derive Tier 2 Message Encryption Key (MEK)
    final mek = await deriveMek(
      pmkBytes: pmk,
      nonce12Bytes: nonce,
      messageId: messageId,
    );

    // 4. Construct canonical AAD
    final aad = buildPrivateMessageAad(
      messageId: messageId,
      conversationId: conversationId,
      senderDeviceId: senderDeviceId,
      recipientDeviceId: recipientDeviceId,
      senderKeyId: senderKeyId,
      recipientKeyId: recipientX25519KeyId,
      timestampMs: ts,
    );

    // 5. Encrypt with ChaCha20-Poly1305 producing SecretBox(nonce, cipherText, mac)
    final plaintextBytes = utf8.encode(plaintext);
    final secretBox = await _aeadCipher.encrypt(
      plaintextBytes,
      secretKey: SecretKey(mek),
      nonce: nonce,
      aad: aad,
    );

    final nonceB64 = base64Encode(secretBox.nonce);
    final ciphertextB64 = base64Encode(secretBox.cipherText);
    final authTagB64 = base64Encode(secretBox.mac.bytes);

    // 6. Sign immutable envelope fields with Ed25519
    final signBytes = buildPrivateEnvelopeSignBytes(
      messageId: messageId,
      conversationId: conversationId,
      senderDeviceId: senderDeviceId,
      recipientDeviceId: recipientDeviceId,
      senderKeyId: senderKeyId,
      recipientKeyId: recipientX25519KeyId,
      timestampMs: ts,
      nonceB64: nonceB64,
      ciphertextB64: ciphertextB64,
      authTagB64: authTagB64,
    );

    final signature = await _ed25519Algorithm.sign(signBytes, keyPair: _keyPair!);
    final signatureB64 = base64Encode(signature.bytes);

    return PrivateMessageEnvelope(
      messageId: messageId,
      conversationId: conversationId,
      senderDeviceId: senderDeviceId,
      recipientDeviceId: recipientDeviceId,
      senderKeyId: senderKeyId,
      recipientKeyId: recipientX25519KeyId,
      timestamp: ts,
      hopCount: 0,
      ttlDays: 7,
      nonce: nonceB64,
      ciphertext: ciphertextB64,
      authTag: authTagB64,
      senderEd25519Pub: senderEdPubB64,
      senderX25519Pub: senderX25PubB64,
      signature: signatureB64,
    );
  }

  /// Decrypts a private message envelope using ChaCha20-Poly1305 with per-message MEK and AAD
  /// Throws SecretBoxAuthenticationError or Exception on decryption / MAC failure
  Future<String> decryptPrivateMessage({
    required PrivateMessageEnvelope envelope,
    SimpleKeyPair? myKeyPairOverride,
  }) async {
    if (!isInitialized && myKeyPairOverride == null) await init();

    // 1. Re-derive Tier 1 PMK
    final pmk = await derivePmk(
      peerX25519PublicKeyB64: envelope.senderX25519Pub,
      myKeyPairOverride: myKeyPairOverride,
    );

    // 2. Decode nonce and reconstruct MEK
    final nonceBytes = base64Decode(envelope.nonce);
    final mek = await deriveMek(
      pmkBytes: pmk,
      nonce12Bytes: nonceBytes,
      messageId: envelope.messageId,
    );

    // 3. Reconstruct canonical AAD
    final aad = buildPrivateMessageAad(
      messageId: envelope.messageId,
      conversationId: envelope.conversationId,
      senderDeviceId: envelope.senderDeviceId,
      recipientDeviceId: envelope.recipientDeviceId,
      senderKeyId: envelope.senderKeyId,
      recipientKeyId: envelope.recipientKeyId,
      timestampMs: envelope.timestamp,
    );

    // 4. Reconstruct SecretBox from wire fields
    final ciphertextBytes = base64Decode(envelope.ciphertext);
    final authTagBytes = base64Decode(envelope.authTag);
    final secretBox = SecretBox(
      ciphertextBytes,
      nonce: nonceBytes,
      mac: Mac(authTagBytes),
    );

    // 5. Authenticated Decryption
    final decryptedBytes = await _aeadCipher.decrypt(
      secretBox,
      secretKey: SecretKey(mek),
      aad: aad,
    );

    return utf8.decode(decryptedBytes);
  }

  /// Verifies the Ed25519 signature on an incoming private message envelope
  Future<bool> verifyPrivateEnvelopeSignature(PrivateMessageEnvelope envelope) async {
    try {
      final sigBytes = base64Decode(envelope.signature);
      final pubKeyBytes = base64Decode(envelope.senderEd25519Pub);

      if (sigBytes.length != 64 || pubKeyBytes.length != 32) return false;

      final signBytes = buildPrivateEnvelopeSignBytes(
        messageId: envelope.messageId,
        conversationId: envelope.conversationId,
        senderDeviceId: envelope.senderDeviceId,
        recipientDeviceId: envelope.recipientDeviceId,
        senderKeyId: envelope.senderKeyId,
        recipientKeyId: envelope.recipientKeyId,
        timestampMs: envelope.timestamp,
        nonceB64: envelope.nonce,
        ciphertextB64: envelope.ciphertext,
        authTagB64: envelope.authTag,
      );

      final pubKey = SimplePublicKey(pubKeyBytes, type: KeyPairType.ed25519);
      final signatureObj = Signature(sigBytes, publicKey: pubKey);

      return await _ed25519Algorithm.verify(
        signBytes,
        signature: signatureObj,
      );
    } catch (e) {
      debugPrint('[CryptoService] Error verifying private envelope signature: $e');
      return false;
    }
  }

  /// Builds canonical UTF-8 bytes for signing a delivery ACK
  static Uint8List buildAckSignBytes({
    required String ackMessageId,
    required String senderDeviceId,
    required String recipientDeviceId,
    required int timestamp,
  }) {
    final payload = 'crisis-mesh-ack-sig-v1|$ackMessageId|$senderDeviceId|$recipientDeviceId|$timestamp';
    return Uint8List.fromList(utf8.encode(payload));
  }

  /// Creates and signs a delivery acknowledgment envelope
  Future<PrivateAckEnvelope> signAck({
    required String ackMessageId,
    required String originalSenderDeviceId,
  }) async {
    if (!isInitialized) await init();

    final ts = DateTime.now().millisecondsSinceEpoch;
    final myDeviceId = derivedDeviceId;

    final signBytes = buildAckSignBytes(
      ackMessageId: ackMessageId,
      senderDeviceId: myDeviceId,
      recipientDeviceId: originalSenderDeviceId,
      timestamp: ts,
    );

    final signature = await _ed25519Algorithm.sign(signBytes, keyPair: _keyPair!);

    return PrivateAckEnvelope(
      ackMessageId: ackMessageId,
      senderDeviceId: myDeviceId,
      recipientDeviceId: originalSenderDeviceId,
      timestamp: ts,
      signature: base64Encode(signature.bytes),
    );
  }

  /// Verifies a delivery acknowledgment signature
  Future<bool> verifyAckSignature({
    required PrivateAckEnvelope ack,
    required String senderEd25519PubB64,
  }) async {
    try {
      final sigBytes = base64Decode(ack.signature);
      final pubKeyBytes = base64Decode(senderEd25519PubB64);

      if (sigBytes.length != 64 || pubKeyBytes.length != 32) return false;

      final signBytes = buildAckSignBytes(
        ackMessageId: ack.ackMessageId,
        senderDeviceId: ack.senderDeviceId,
        recipientDeviceId: ack.recipientDeviceId,
        timestamp: ack.timestamp,
      );

      final pubKey = SimplePublicKey(pubKeyBytes, type: KeyPairType.ed25519);
      final signatureObj = Signature(sigBytes, publicKey: pubKey);

      return await _ed25519Algorithm.verify(
        signBytes,
        signature: signatureObj,
      );
    } catch (e) {
      return false;
    }
  }

  // ===========================================================================
  // EXISTING PHASE 7: SOS ED25519 SIGNING & VERIFICATION (PRESERVED UNTOUCHED)
  // ===========================================================================

  /// Builds a deterministic canonical UTF-8 byte representation of immutable SOS fields
  static Uint8List buildCanonicalBytes({
    required String version,
    required String messageId,
    required String senderId,
    required String publicKey,
    required int timestamp,
    required String? needType,
    required double? lat,
    required double? lng,
    required String? payload,
  }) {
    final buffer = StringBuffer();
    buffer.write('CRISIS_MESH_SIG_V$version\n');
    buffer.write('$messageId\n');
    buffer.write('$senderId\n');
    buffer.write('$publicKey\n');
    buffer.write('$timestamp\n');
    buffer.write('${needType?.trim().toLowerCase() ?? ""}\n');
    buffer.write('${lat != null ? lat.toStringAsFixed(6) : ""}\n');
    buffer.write('${lng != null ? lng.toStringAsFixed(6) : ""}\n');
    buffer.write(payload?.trim() ?? "");

    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }

  /// Signs an SOS message and returns the 64-byte Ed25519 signature encoded as Base64
  Future<String?> signSos({
    required String messageId,
    required String senderId,
    required int timestamp,
    required String? needType,
    required double? lat,
    required double? lng,
    required String? payload,
  }) async {
    if (_keyPair == null) await init();
    if (_keyPair == null || _cachedPublicKeyBase64 == null) return null;

    final canonicalBytes = buildCanonicalBytes(
      version: currentSignatureVersion,
      messageId: messageId,
      senderId: senderId,
      publicKey: _cachedPublicKeyBase64!,
      timestamp: timestamp,
      needType: needType,
      lat: lat,
      lng: lng,
      payload: payload,
    );

    final signature = await _ed25519Algorithm.sign(
      canonicalBytes,
      keyPair: _keyPair!,
    );

    return base64Encode(signature.bytes);
  }

  /// Verifies an Ed25519 signature against the canonical representation
  Future<bool> verifySignature({
    required String signatureBase64,
    required String publicKeyBase64,
    required String version,
    required String messageId,
    required String senderId,
    required int timestamp,
    required String? needType,
    required double? lat,
    required double? lng,
    required String? payload,
  }) async {
    try {
      final sigBytes = base64Decode(signatureBase64);
      final pubKeyBytes = base64Decode(publicKeyBase64);

      if (sigBytes.length != 64 || pubKeyBytes.length != 32) {
        debugPrint('[CryptoService] Invalid signature or public key byte length.');
        return false;
      }

      final canonicalBytes = buildCanonicalBytes(
        version: version,
        messageId: messageId,
        senderId: senderId,
        publicKey: publicKeyBase64,
        timestamp: timestamp,
        needType: needType,
        lat: lat,
        lng: lng,
        payload: payload,
      );

      final pubKey = SimplePublicKey(pubKeyBytes, type: KeyPairType.ed25519);
      final signatureObj = Signature(sigBytes, publicKey: pubKey);

      return await _ed25519Algorithm.verify(
        canonicalBytes,
        signature: signatureObj,
      );
    } catch (e) {
      debugPrint('[CryptoService] Error during signature verification: $e');
      return false;
    }
  }

  /// Evaluates the complete cryptographic authenticity, TOFU status, replay, freshness, and rate limit of an SOS message
  Future<String> evaluateAuthenticity(
    MessageModel message, {
    DateTime? now,
    bool isDuplicate = false,
  }) async {
    if (message.signature == null || message.signature!.isEmpty || message.publicKey == null || message.publicKey!.isEmpty) {
      return AuthenticityStatus.unverified;
    }

    if (isDuplicate) {
      return AuthenticityStatus.replayed;
    }

    final currentTime = now ?? DateTime.now();
    final messageTime = DateTime.fromMillisecondsSinceEpoch(message.timestamp);

    if (messageTime.isAfter(currentTime.add(futureTimestampTolerance))) {
      debugPrint('[CryptoService] Message ${message.id} timestamp is in the future (>10m clock skew).');
      return AuthenticityStatus.futureClock;
    }

    if (currentTime.difference(messageTime) > sosExpiryHorizon) {
      debugPrint('[CryptoService] Message ${message.id} is stale (older than 48h).');
      return AuthenticityStatus.stale;
    }

    final tofuResult = checkTofuKey(message.senderId, message.publicKey!);
    if (tofuResult == TofuStatus.untrustedKeyMismatch) {
      debugPrint('[CryptoService] Sender ${message.senderId} key mismatch: untrusted public key.');
      return AuthenticityStatus.untrustedKeyMismatch;
    }

    final rateAllowed = checkRateLimit(message.publicKey!, nowMs: currentTime.millisecondsSinceEpoch);
    if (!rateAllowed) {
      debugPrint('[CryptoService] Sender key ${message.publicKey} exceeded rate limit (5 SOS / 60s).');
      return AuthenticityStatus.rateLimited;
    }

    final validSig = await verifySignature(
      signatureBase64: message.signature!,
      publicKeyBase64: message.publicKey!,
      version: message.signatureVersion ?? currentSignatureVersion,
      messageId: message.id,
      senderId: message.senderId,
      timestamp: message.timestamp,
      needType: message.needType,
      lat: message.lat,
      lng: message.lng,
      payload: message.payload,
    );

    if (!validSig) {
      debugPrint('[CryptoService] Signature verification FAILED for message ${message.id}.');
      return AuthenticityStatus.invalidSignature;
    }

    return AuthenticityStatus.verified;
  }

  /// Evaluates Trust-On-First-Use (TOFU) association for a given sender ID and public key
  TofuStatus checkTofuKey(String senderId, String publicKeyBase64) {
    final existing = _tofuStore[senderId];
    if (existing == null) {
      _tofuStore[senderId] = publicKeyBase64;
      return TofuStatus.firstSeen;
    }
    if (existing == publicKeyBase64) {
      return TofuStatus.matched;
    }
    return TofuStatus.untrustedKeyMismatch;
  }

  /// Basic local flood protection: Maximum 5 SOS per 60 seconds per sender public key
  bool checkRateLimit(String senderKey, {int? nowMs}) {
    final currentMs = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final windowStart = currentMs - 60000;

    final history = _rateLimitHistory[senderKey] ?? [];
    final recent = history.where((t) => t >= windowStart).toList();

    if (recent.length >= 5) {
      return false;
    }

    recent.add(currentMs);
    _rateLimitHistory[senderKey] = recent;
    return true;
  }

  /// Resets in-memory caches and sets up custom seeds for deterministic testing
  Future<void> resetForTest({Uint8List? customSeed, Uint8List? customX25519Seed}) async {
    _keyPair = null;
    _publicKey = null;
    _cachedPublicKeyBase64 = null;
    _cachedDeviceId = null;
    _x25519KeyPair = null;
    _x25519PublicKey = null;
    _cachedX25519PublicKeyBase64 = null;
    _cachedX25519KeyId = null;
    _tofuStore.clear();
    _rateLimitHistory.clear();
    await init(customSeed: customSeed, customX25519Seed: customX25519Seed);
  }
}
