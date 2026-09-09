import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Private message delivery lifecycle states
class PrivateMessageStatus {
  static const String pending = 'PENDING';
  static const String sent = 'SENT';
  static const String delivered = 'DELIVERED';
  static const String failed = 'FAILED';
  static const String received = 'RECEIVED';

  static String badgeText(String status) {
    switch (status) {
      case pending:
        return 'Pending';
      case sent:
        return 'Sent';
      case delivered:
        return 'Delivered';
      case failed:
        return 'Failed';
      case received:
        return 'Received';
      default:
        return status;
    }
  }
}

/// Over-the-air encrypted wire envelope for private 1-to-1 messages
class PrivateMessageEnvelope {
  final int protocolVersion; // Default 1
  final String type; // 'private_chat'
  final String messageId;
  final String conversationId;
  final String senderDeviceId;
  final String recipientDeviceId;
  final String senderKeyId;
  final String recipientKeyId;
  final int timestamp;
  int hopCount;
  final int ttlDays; // 7 days
  final String nonce; // Base64 (12 bytes)
  final String ciphertext; // Base64
  final String authTag; // Base64 (16 bytes Poly1305 MAC)
  final String senderEd25519Pub; // Base64 (32 bytes)
  final String senderX25519Pub; // Base64 (32 bytes)
  final String signature; // Base64 (64 bytes Ed25519 signature)

  PrivateMessageEnvelope({
    this.protocolVersion = 1,
    this.type = 'private_chat',
    required this.messageId,
    required this.conversationId,
    required this.senderDeviceId,
    required this.recipientDeviceId,
    required this.senderKeyId,
    required this.recipientKeyId,
    required this.timestamp,
    this.hopCount = 0,
    this.ttlDays = 7,
    required this.nonce,
    required this.ciphertext,
    required this.authTag,
    required this.senderEd25519Pub,
    required this.senderX25519Pub,
    required this.signature,
  });

  Map<String, dynamic> toMap() {
    return {
      'protocol_version': protocolVersion,
      'type': type,
      'message_id': messageId,
      'conversation_id': conversationId,
      'sender_device_id': senderDeviceId,
      'recipient_device_id': recipientDeviceId,
      'sender_key_id': senderKeyId,
      'recipient_key_id': recipientKeyId,
      'timestamp': timestamp,
      'hop_count': hopCount,
      'ttl_days': ttlDays,
      'nonce': nonce,
      'ciphertext': ciphertext,
      'auth_tag': authTag,
      'sender_ed25519_pub': senderEd25519Pub,
      'sender_x25519_pub': senderX25519Pub,
      'signature': signature,
    };
  }

  factory PrivateMessageEnvelope.fromMap(Map<String, dynamic> map) {
    return PrivateMessageEnvelope(
      protocolVersion: map['protocol_version'] as int? ?? 1,
      type: map['type'] as String? ?? 'private_chat',
      messageId: map['message_id'] as String,
      conversationId: map['conversation_id'] as String,
      senderDeviceId: map['sender_device_id'] as String,
      recipientDeviceId: map['recipient_device_id'] as String,
      senderKeyId: map['sender_key_id'] as String,
      recipientKeyId: map['recipient_key_id'] as String,
      timestamp: map['timestamp'] as int,
      hopCount: map['hop_count'] as int? ?? 0,
      ttlDays: map['ttl_days'] as int? ?? 7,
      nonce: map['nonce'] as String,
      ciphertext: map['ciphertext'] as String,
      authTag: map['auth_tag'] as String,
      senderEd25519Pub: map['sender_ed25519_pub'] as String,
      senderX25519Pub: map['sender_x25519_pub'] as String,
      signature: map['signature'] as String,
    );
  }

  String toJson() => jsonEncode(toMap());

  static PrivateMessageEnvelope? fromJson(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (map['type'] != 'private_chat') return null;
      return PrivateMessageEnvelope.fromMap(map);
    } catch (e) {
      debugPrint('[PrivateMessageEnvelope] Error parsing JSON: $e');
      return null;
    }
  }
}

/// Delivery acknowledgment envelope sent back to the sender
class PrivateAckEnvelope {
  final int protocolVersion;
  final String type; // 'private_ack'
  final String ackMessageId;
  final String senderDeviceId;
  final String recipientDeviceId;
  final int timestamp;
  final String signature; // Ed25519 signature over ack payload

  PrivateAckEnvelope({
    this.protocolVersion = 1,
    this.type = 'private_ack',
    required this.ackMessageId,
    required this.senderDeviceId,
    required this.recipientDeviceId,
    required this.timestamp,
    required this.signature,
  });

  Map<String, dynamic> toMap() {
    return {
      'protocol_version': protocolVersion,
      'type': type,
      'ack_message_id': ackMessageId,
      'sender_device_id': senderDeviceId,
      'recipient_device_id': recipientDeviceId,
      'timestamp': timestamp,
      'signature': signature,
    };
  }

  factory PrivateAckEnvelope.fromMap(Map<String, dynamic> map) {
    return PrivateAckEnvelope(
      protocolVersion: map['protocol_version'] as int? ?? 1,
      type: map['type'] as String? ?? 'private_ack',
      ackMessageId: map['ack_message_id'] as String,
      senderDeviceId: map['sender_device_id'] as String,
      recipientDeviceId: map['recipient_device_id'] as String,
      timestamp: map['timestamp'] as int,
      signature: map['signature'] as String,
    );
  }

  String toJson() => jsonEncode(toMap());

  static PrivateAckEnvelope? fromJson(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (map['type'] != 'private_ack') return null;
      return PrivateAckEnvelope.fromMap(map);
    } catch (e) {
      return null;
    }
  }
}

/// Local database representation of an end-to-end encrypted private message
class PrivateMessageModel {
  final String messageId;
  final String conversationId;
  final String senderDeviceId;
  final String recipientDeviceId;
  final String? plaintextBody; // Decrypted locally on endpoint, NULL on transit nodes
  final String ciphertext;
  final String nonce;
  final String authTag;
  final String senderX25519Pub;
  final String senderEd25519Pub;
  final String signature;
  final String status; // PrivateMessageStatus
  final int timestamp;
  final int expiresAt; // Epoch ms (timestamp + 7 days)
  final bool isOutgoing;
  final bool acknowledged;

  PrivateMessageModel({
    required this.messageId,
    required this.conversationId,
    required this.senderDeviceId,
    required this.recipientDeviceId,
    this.plaintextBody,
    required this.ciphertext,
    required this.nonce,
    required this.authTag,
    required this.senderX25519Pub,
    required this.senderEd25519Pub,
    required this.signature,
    this.status = PrivateMessageStatus.pending,
    required this.timestamp,
    required this.expiresAt,
    this.isOutgoing = false,
    this.acknowledged = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'message_id': messageId,
      'conversation_id': conversationId,
      'sender_device_id': senderDeviceId,
      'recipient_device_id': recipientDeviceId,
      'plaintext_body': plaintextBody,
      'ciphertext': ciphertext,
      'nonce': nonce,
      'auth_tag': authTag,
      'sender_x25519_pub': senderX25519Pub,
      'sender_ed25519_pub': senderEd25519Pub,
      'signature': signature,
      'status': status,
      'timestamp': timestamp,
      'expires_at': expiresAt,
      'is_outgoing': isOutgoing ? 1 : 0,
      'acknowledged': acknowledged ? 1 : 0,
    };
  }

  factory PrivateMessageModel.fromMap(Map<String, dynamic> map) {
    return PrivateMessageModel(
      messageId: map['message_id'] as String,
      conversationId: map['conversation_id'] as String,
      senderDeviceId: map['sender_device_id'] as String,
      recipientDeviceId: map['recipient_device_id'] as String,
      plaintextBody: map['plaintext_body'] as String?,
      ciphertext: map['ciphertext'] as String,
      nonce: map['nonce'] as String,
      authTag: map['auth_tag'] as String,
      senderX25519Pub: map['sender_x25519_pub'] as String,
      senderEd25519Pub: map['sender_ed25519_pub'] as String,
      signature: map['signature'] as String,
      status: map['status'] as String? ?? PrivateMessageStatus.pending,
      timestamp: map['timestamp'] as int,
      expiresAt: map['expires_at'] as int,
      isOutgoing: (map['is_outgoing'] as int? ?? 0) == 1,
      acknowledged: (map['acknowledged'] as int? ?? 0) == 1,
    );
  }

  PrivateMessageModel copyWith({
    String? messageId,
    String? conversationId,
    String? senderDeviceId,
    String? recipientDeviceId,
    String? plaintextBody,
    String? ciphertext,
    String? nonce,
    String? authTag,
    String? senderX25519Pub,
    String? senderEd25519Pub,
    String? signature,
    String? status,
    int? timestamp,
    int? expiresAt,
    bool? isOutgoing,
    bool? acknowledged,
  }) {
    return PrivateMessageModel(
      messageId: messageId ?? this.messageId,
      conversationId: conversationId ?? this.conversationId,
      senderDeviceId: senderDeviceId ?? this.senderDeviceId,
      recipientDeviceId: recipientDeviceId ?? this.recipientDeviceId,
      plaintextBody: plaintextBody ?? this.plaintextBody,
      ciphertext: ciphertext ?? this.ciphertext,
      nonce: nonce ?? this.nonce,
      authTag: authTag ?? this.authTag,
      senderX25519Pub: senderX25519Pub ?? this.senderX25519Pub,
      senderEd25519Pub: senderEd25519Pub ?? this.senderEd25519Pub,
      signature: signature ?? this.signature,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      expiresAt: expiresAt ?? this.expiresAt,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      acknowledged: acknowledged ?? this.acknowledged,
    );
  }

  /// Converts this local message model into a wire envelope for mesh broadcast
  PrivateMessageEnvelope toEnvelope() {
    return PrivateMessageEnvelope(
      messageId: messageId,
      conversationId: conversationId,
      senderDeviceId: senderDeviceId,
      recipientDeviceId: recipientDeviceId,
      senderKeyId: 'X25519-${senderX25519Pub.substring(0, 8).toUpperCase()}',
      recipientKeyId: '', // Populated by caller if known
      timestamp: timestamp,
      nonce: nonce,
      ciphertext: ciphertext,
      authTag: authTag,
      senderEd25519Pub: senderEd25519Pub,
      senderX25519Pub: senderX25519Pub,
      signature: signature,
    );
  }
}
