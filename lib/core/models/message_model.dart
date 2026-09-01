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
  final bool synced;

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
    this.synced = false,
  });

  /// Create a MessageModel from a database Map.
  factory MessageModel.fromMap(Map<String, dynamic> map) {
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
      timestamp: map['timestamp'] as int,
      hopCount: map['hop_count'] as int,
      priorityTier: map['priority_tier'] as String,
      priorityScore: map['priority_score'] as int,
      signature: map['signature'] as String?,
      synced: (map['synced'] as int) == 1,
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
      'synced': synced ? 1 : 0,
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
      'synced': true,
      'synced_at': DateTime.now().millisecondsSinceEpoch,
      'bridge_device_id': bridgeDeviceId,
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
    bool? synced,
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
      synced: synced ?? this.synced,
    );
  }
}
