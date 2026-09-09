/// Local delivery lifecycle states for Bluetooth Mesh transmission (Phase 5A)
class MeshDeliveryStatus {
  static const String pending = 'pending';
  static const String sending = 'sending';
  static const String transmittedToPeer = 'transmitted_to_peer';

  static const List<String> all = [pending, sending, transmittedToPeer];

  static String format(String status) {
    switch (status) {
      case pending:
        return 'Pending — waiting for nearby device';
      case sending:
        return 'Sending...';
      case transmittedToPeer:
        return 'Sent via mesh';
      default:
        return status;
    }
  }

  static String badgeText(String status) {
    switch (status) {
      case pending:
        return 'Waiting for device';
      case sending:
        return 'Sending...';
      case transmittedToPeer:
        return 'Sent via mesh';
      default:
        return status;
    }
  }
}

class MessageModel {
  final String id;
  final String type; // 'broadcast' or 'chat'
  final String senderId;
  final String? recipientId;
  final String? groupId;
  final String? payload; // For SOS, this is the description/details
  final String? needType; // medical, trapped, fire, water, food, shelter
  final double? lat;
  final double? lng;
  final int timestamp;
  final int hopCount;
  final String priorityTier;
  final int priorityScore;
  final String? signature;
  final String? publicKey;
  final String? signatureVersion;
  final String authenticityStatus; // 'verified', 'invalid_signature', 'stale', 'future_clock', 'replayed', 'untrusted_key_mismatch', 'rate_limited', 'unverified'
  final bool synced;
  final String meshDeliveryStatus; // 'pending', 'sending', 'transmitted_to_peer'

  MessageModel({
    required this.id,
    required this.type,
    required this.senderId,
    this.recipientId,
    this.groupId,
    this.payload,
    this.needType,
    this.lat,
    this.lng,
    required this.timestamp,
    required this.hopCount,
    required this.priorityTier,
    required this.priorityScore,
    this.signature,
    this.publicKey,
    this.signatureVersion = '1',
    this.authenticityStatus = 'unverified',
    this.synced = false,
    this.meshDeliveryStatus = MeshDeliveryStatus.transmittedToPeer,
  });

  /// Create a MessageModel from a database Map.
  factory MessageModel.fromMap(Map<String, dynamic> map) {
    final hop = map['hop_count'] != null ? (map['hop_count'] as num).toInt() : 0;
    final isSynced = (map['synced'] == 1 || map['synced'] == true);
    final rawMeshStatus = map['mesh_delivery_status'] as String?;

    final parsedMeshStatus = rawMeshStatus != null && MeshDeliveryStatus.all.contains(rawMeshStatus)
        ? rawMeshStatus
        : (isSynced || hop > 0 ? MeshDeliveryStatus.transmittedToPeer : MeshDeliveryStatus.pending);

    return MessageModel(
      id: map['id'] as String,
      type: map['type'] as String,
      senderId: map['sender_id'] as String,
      recipientId: map['recipient_id'] as String?,
      groupId: map['group_id'] as String?,
      payload: map['payload'] as String?,
      needType: map['need_type'] as String?,
      lat: map['lat'] != null ? (map['lat'] as num).toDouble() : null,
      lng: map['lng'] != null ? (map['lng'] as num).toDouble() : null,
      timestamp: map['timestamp'] != null ? (map['timestamp'] as num).toInt() : DateTime.now().millisecondsSinceEpoch,
      hopCount: hop,
      priorityTier: map['priority_tier'] as String? ?? 'Low',
      priorityScore: map['priority_score'] != null ? (map['priority_score'] as num).toInt() : 1,
      signature: map['signature'] as String?,
      publicKey: map['public_key'] as String?,
      signatureVersion: map['signature_version'] as String? ?? '1',
      authenticityStatus: map['authenticity_status'] as String? ?? (map['signature'] != null ? 'verified' : 'unverified'),
      synced: isSynced,
      meshDeliveryStatus: parsedMeshStatus,
    );
  }

  /// Convert a MessageModel to a database Map.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'sender_id': senderId,
      'recipient_id': recipientId,
      'group_id': groupId,
      'payload': payload,
      'need_type': needType,
      'lat': lat,
      'lng': lng,
      'timestamp': timestamp,
      'hop_count': hopCount,
      'priority_tier': priorityTier,
      'priority_score': priorityScore,
      'signature': signature,
      'public_key': publicKey,
      'signature_version': signatureVersion,
      'authenticity_status': authenticityStatus,
      'synced': synced ? 1 : 0,
      'mesh_delivery_status': meshDeliveryStatus,
    };
  }

  /// Convert a MessageModel to a Firestore-compatible Map for Cloud Bridge sync.
  Map<String, dynamic> toFirestoreMap({String? bridgeDeviceId}) {
    return {
      'id': id,
      'type': type,
      'sender_id': senderId,
      'recipient_id': recipientId,
      'group_id': groupId,
      'payload': payload,
      'need_type': needType,
      'lat': lat,
      'lng': lng,
      'timestamp': timestamp,
      'hop_count': hopCount,
      'priority_tier': priorityTier,
      'priority_score': priorityScore,
      'signature': signature,
      'public_key': publicKey,
      'signature_version': signatureVersion,
      'authenticity_status': authenticityStatus,
      'synced': true,
      'synced_at': DateTime.now().millisecondsSinceEpoch,
      'bridge_device_id': bridgeDeviceId,
      'mesh_delivery_status': meshDeliveryStatus,
    };
  }

  /// Create a copy of MessageModel with modified fields.
  MessageModel copyWith({
    String? id,
    String? type,
    String? senderId,
    String? recipientId,
    String? groupId,
    String? payload,
    String? needType,
    double? lat,
    double? lng,
    int? timestamp,
    int? hopCount,
    String? priorityTier,
    int? priorityScore,
    String? signature,
    String? publicKey,
    String? signatureVersion,
    String? authenticityStatus,
    bool? synced,
    String? meshDeliveryStatus,
  }) {
    return MessageModel(
      id: id ?? this.id,
      type: type ?? this.type,
      senderId: senderId ?? this.senderId,
      recipientId: recipientId ?? this.recipientId,
      groupId: groupId ?? this.groupId,
      payload: payload ?? this.payload,
      needType: needType ?? this.needType,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      timestamp: timestamp ?? this.timestamp,
      hopCount: hopCount ?? this.hopCount,
      priorityTier: priorityTier ?? this.priorityTier,
      priorityScore: priorityScore ?? this.priorityScore,
      signature: signature ?? this.signature,
      publicKey: publicKey ?? this.publicKey,
      signatureVersion: signatureVersion ?? this.signatureVersion,
      authenticityStatus: authenticityStatus ?? this.authenticityStatus,
      synced: synced ?? this.synced,
      meshDeliveryStatus: meshDeliveryStatus ?? this.meshDeliveryStatus,
    );
  }

  // --- Convenience Helpers ---
  bool get isMeshPending => meshDeliveryStatus == MeshDeliveryStatus.pending;
  bool get isMeshSending => meshDeliveryStatus == MeshDeliveryStatus.sending;
  bool get isTransmittedToPeer => meshDeliveryStatus == MeshDeliveryStatus.transmittedToPeer;
}
