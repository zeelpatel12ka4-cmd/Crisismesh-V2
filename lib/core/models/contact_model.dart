import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Contact trust status enum
enum ContactTrustStatus {
  unverified,
  qrVerified,
  keyChanged,
}

extension ContactTrustStatusExtension on ContactTrustStatus {
  String get value {
    switch (this) {
      case ContactTrustStatus.unverified:
        return 'UNVERIFIED';
      case ContactTrustStatus.qrVerified:
        return 'QR_VERIFIED';
      case ContactTrustStatus.keyChanged:
        return 'KEY_CHANGED';
    }
  }

  static ContactTrustStatus fromString(String val) {
    switch (val.toUpperCase()) {
      case 'QR_VERIFIED':
        return ContactTrustStatus.qrVerified;
      case 'KEY_CHANGED':
        return ContactTrustStatus.keyChanged;
      case 'UNVERIFIED':
      default:
        return ContactTrustStatus.unverified;
    }
  }

  String get label {
    switch (this) {
      case ContactTrustStatus.unverified:
        return 'Unverified';
      case ContactTrustStatus.qrVerified:
        return 'QR Verified';
      case ContactTrustStatus.keyChanged:
        return 'Key Changed (Security Warning)';
    }
  }
}

/// Representation of a trusted or discovered Crisis Mesh contact
class ContactModel {
  final String deviceId; // DEV-XXXXXXXX
  final String displayName;
  final String signingPublicKey; // Ed25519 Base64
  final String encryptionPublicKey; // X25519 Base64
  final String fingerprint; // e.g. A1B2:C3D4:E5F6:7890
  final ContactTrustStatus trustStatus;
  final int createdAt; // epoch ms
  final int lastSeenAt; // epoch ms

  ContactModel({
    required this.deviceId,
    required this.displayName,
    required this.signingPublicKey,
    required this.encryptionPublicKey,
    required this.fingerprint,
    this.trustStatus = ContactTrustStatus.unverified,
    required this.createdAt,
    required this.lastSeenAt,
  });

  /// Computes a deterministic human-auditable fingerprint from both public keys
  static String computeFingerprint({
    required String signingPublicKeyB64,
    required String encryptionPublicKeyB64,
  }) {
    final raw = utf8.encode('$signingPublicKeyB64:$encryptionPublicKeyB64');
    int h1 = 0x811c9dc5;
    int h2 = 0x5a17e429;
    for (int i = 0; i < raw.length; i++) {
      if (i % 2 == 0) {
        h1 = ((h1 ^ raw[i]) * 0x01000193) & 0xFFFFFFFF;
      } else {
        h2 = ((h2 ^ raw[i]) * 0x01000193) & 0xFFFFFFFF;
      }
    }
    final hex1 = h1.toRadixString(16).padLeft(8, '0').toUpperCase();
    final hex2 = h2.toRadixString(16).padLeft(8, '0').toUpperCase();
    return '${hex1.substring(0, 4)}:${hex1.substring(4, 8)}:${hex2.substring(0, 4)}:${hex2.substring(4, 8)}';
  }

  ContactModel copyWith({
    String? deviceId,
    String? displayName,
    String? signingPublicKey,
    String? encryptionPublicKey,
    String? fingerprint,
    ContactTrustStatus? trustStatus,
    int? createdAt,
    int? lastSeenAt,
  }) {
    return ContactModel(
      deviceId: deviceId ?? this.deviceId,
      displayName: displayName ?? this.displayName,
      signingPublicKey: signingPublicKey ?? this.signingPublicKey,
      encryptionPublicKey: encryptionPublicKey ?? this.encryptionPublicKey,
      fingerprint: fingerprint ?? this.fingerprint,
      trustStatus: trustStatus ?? this.trustStatus,
      createdAt: createdAt ?? this.createdAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'device_id': deviceId,
      'display_name': displayName,
      'signing_public_key': signingPublicKey,
      'encryption_public_key': encryptionPublicKey,
      'fingerprint': fingerprint,
      'trust_status': trustStatus.value,
      'created_at': createdAt,
      'last_seen_at': lastSeenAt,
    };
  }

  factory ContactModel.fromMap(Map<String, dynamic> map) {
    return ContactModel(
      deviceId: map['device_id'] as String,
      displayName: map['display_name'] as String,
      signingPublicKey: map['signing_public_key'] as String,
      encryptionPublicKey: map['encryption_public_key'] as String,
      fingerprint: map['fingerprint'] as String,
      trustStatus: ContactTrustStatusExtension.fromString(map['trust_status'] as String? ?? 'UNVERIFIED'),
      createdAt: map['created_at'] as int,
      lastSeenAt: map['last_seen_at'] as int,
    );
  }

  /// Exports strictly public information for QR code generation
  /// Contains zero private keys, zero seeds, zero credentials
  String toQrPayload() {
    final payload = {
      'v': 1,
      'type': 'crisis_mesh_contact',
      'dev_id': deviceId,
      'name': displayName,
      'sign_pub': signingPublicKey,
      'enc_pub': encryptionPublicKey,
      'fp': fingerprint,
    };
    return jsonEncode(payload);
  }

  /// Parses and validates a scanned QR payload
  /// Returns null if format or public keys are invalid
  static ContactModel? fromQrPayload(String qrString) {
    try {
      final map = jsonDecode(qrString) as Map<String, dynamic>;
      if (map['type'] != 'crisis_mesh_contact') return null;
      if (map['v'] != 1) return null;

      final devId = map['dev_id'] as String?;
      final name = map['name'] as String? ?? 'Unknown Contact';
      final signPub = map['sign_pub'] as String?;
      final encPub = map['enc_pub'] as String?;
      final fp = map['fp'] as String?;

      if (devId == null || signPub == null || encPub == null || fp == null) {
        return null;
      }

      // Validate base64 format and lengths (32 bytes each)
      final signBytes = base64Decode(signPub);
      final encBytes = base64Decode(encPub);
      if (signBytes.length != 32 || encBytes.length != 32) {
        return null;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      return ContactModel(
        deviceId: devId,
        displayName: name,
        signingPublicKey: signPub,
        encryptionPublicKey: encPub,
        fingerprint: fp,
        trustStatus: ContactTrustStatus.unverified, // Stays unverified until user taps confirmation
        createdAt: now,
        lastSeenAt: now,
      );
    } catch (e) {
      debugPrint('[ContactModel] Failed to parse QR payload: $e');
      return null;
    }
  }
}
