import 'message_model.dart';

/// Incident status workflow states
class IncidentStatus {
  static const String open = 'open';
  static const String assigned = 'assigned';
  static const String enRoute = 'en_route';
  static const String resolved = 'resolved';

  static const List<String> all = [open, assigned, enRoute, resolved];

  static String format(String status) {
    switch (status.toLowerCase()) {
      case open:
        return 'Open / Pending';
      case assigned:
        return 'Assigned';
      case enRoute:
        return 'En Route';
      case resolved:
        return 'Resolved';
      default:
        return status;
    }
  }
}

/// Rich Incident model used by the Responder Command Center,
/// backed directly by Firestore `sos_reports` documents.
class IncidentModel {
  final String id;
  final String type;
  final String senderId;
  final String? recipientId;
  final String? groupId;
  final String? payload;
  final String? needType;
  final double? lat;
  final double? lng;
  final int timestamp;
  final int hopCount;
  final String priorityTier;
  final int priorityScore;
  final String? signature;
  final String? publicKey;
  final String? signatureVersion;
  final String authenticityStatus;
  final bool synced;
  final int? syncedAt;
  final String? bridgeDeviceId;

  // Responder operational extensions (Phase 4)
  final String status; // 'open', 'assigned', 'en_route', 'resolved'
  final String? assignedTo; // e.g. "Unit-4 (Medic)", "Alpha-1"
  final int? assignedAt;
  final int? statusUpdatedAt;
  final String? resolutionNotes;

  IncidentModel({
    required this.id,
    this.type = 'broadcast',
    required this.senderId,
    this.recipientId,
    this.groupId,
    this.payload,
    this.needType,
    this.lat,
    this.lng,
    required this.timestamp,
    this.hopCount = 0,
    required this.priorityTier,
    required this.priorityScore,
    this.signature,
    this.publicKey,
    this.signatureVersion = '1',
    this.authenticityStatus = 'unverified',
    this.synced = true,
    this.syncedAt,
    this.bridgeDeviceId,
    this.status = IncidentStatus.open,
    this.assignedTo,
    this.assignedAt,
    this.statusUpdatedAt,
    this.resolutionNotes,
  });

  /// Safe helpers for robust deserialization across diverse Firestore document shapes
  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static int? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    if (value is String) {
      final asInt = int.tryParse(value);
      if (asInt != null) return asInt;
      return DateTime.tryParse(value)?.millisecondsSinceEpoch;
    }
    // Handle cloud_firestore Timestamp if dynamically passed
    try {
      final dynamic dyn = value;
      if (dyn.millisecondsSinceEpoch != null) {
        return (dyn.millisecondsSinceEpoch as num).toInt();
      }
    } catch (_) {}
    return null;
  }

  /// Factory from Firestore Map / Document Snapshot data
  factory IncidentModel.fromMap(Map<String, dynamic> map, {String? documentId}) {
    final String rawId = (map['id'] ?? map['message_id'] ?? map['messageId'])?.toString() ?? '';
    final String docId = (documentId != null && documentId.isNotEmpty)
        ? documentId
        : (rawId.isNotEmpty ? rawId : 'UNKNOWN_ID');

    // Normalize status: fallback to 'open' if not set
    final rawStatus = (map['status'] as String?)?.toLowerCase().trim();
    final String parsedStatus = (rawStatus != null && IncidentStatus.all.contains(rawStatus))
        ? rawStatus
        : IncidentStatus.open;

    final parsedScore = _parseInt(map['priority_score'] ?? map['priorityScore']) ?? 1;
    String rawTier = (map['priority_tier'] ?? map['priorityTier'])?.toString() ?? '';
    if (rawTier.trim().isEmpty) {
      if (parsedScore >= 9) {
        rawTier = 'Critical';
      } else if (parsedScore >= 6) {
        rawTier = 'Urgent';
      } else if (parsedScore >= 3) {
        rawTier = 'Needs';
      } else {
        rawTier = 'Low';
      }
    }

    final dynamic rawSynced = map['synced'];
    final bool isSynced = rawSynced == true || rawSynced == 1 || rawSynced == 'true';

    return IncidentModel(
      id: docId,
      type: (map['type'] ?? 'broadcast').toString(),
      senderId: (map['sender_id'] ?? map['senderId'] ?? 'UNKNOWN').toString(),
      recipientId: map['recipient_id']?.toString() ?? map['recipientId']?.toString(),
      groupId: map['group_id']?.toString() ?? map['groupId']?.toString(),
      payload: (map['payload'] ?? map['description'])?.toString(),
      needType: (map['need_type'] ?? map['needType'])?.toString(),
      lat: _parseDouble(map['lat'] ?? map['latitude']),
      lng: _parseDouble(map['lng'] ?? map['longitude']),
      timestamp: _parseTimestamp(map['timestamp'] ?? map['created_at']) ?? DateTime.now().millisecondsSinceEpoch,
      hopCount: _parseInt(map['hop_count'] ?? map['hopCount']) ?? 0,
      priorityTier: rawTier,
      priorityScore: parsedScore,
      signature: map['signature']?.toString(),
      publicKey: (map['public_key'] ?? map['publicKey'])?.toString(),
      signatureVersion: (map['signature_version'] ?? map['signatureVersion'])?.toString() ?? '1',
      authenticityStatus: (map['authenticity_status'] ?? map['authenticityStatus'])?.toString() ??
          (map['signature'] != null ? 'verified' : 'unverified'),
      synced: isSynced,
      syncedAt: _parseTimestamp(map['synced_at'] ?? map['syncedAt']),
      bridgeDeviceId: (map['bridge_device_id'] ?? map['bridgeDeviceId'])?.toString(),
      status: parsedStatus,
      assignedTo: (map['assigned_to'] ?? map['assignedTo'])?.toString(),
      assignedAt: _parseTimestamp(map['assigned_at'] ?? map['assignedAt']),
      statusUpdatedAt: _parseTimestamp(map['status_updated_at'] ?? map['statusUpdatedAt']),
      resolutionNotes: (map['resolution_notes'] ?? map['resolutionNotes'])?.toString(),
    );
  }

  /// Create IncidentModel from existing MessageModel
  factory IncidentModel.fromMessageModel(MessageModel message, {String? status, String? assignedTo}) {
    return IncidentModel(
      id: message.id,
      type: message.type,
      senderId: message.senderId,
      recipientId: message.recipientId,
      groupId: message.groupId,
      payload: message.payload,
      needType: message.needType,
      lat: message.lat,
      lng: message.lng,
      timestamp: message.timestamp,
      hopCount: message.hopCount,
      priorityTier: message.priorityTier,
      priorityScore: message.priorityScore,
      signature: message.signature,
      publicKey: message.publicKey,
      signatureVersion: message.signatureVersion,
      authenticityStatus: message.authenticityStatus,
      synced: message.synced,
      status: status ?? IncidentStatus.open,
      assignedTo: assignedTo,
    );
  }

  /// Convert to Firestore Map representation
  Map<String, dynamic> toFirestoreMap() {
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
      'synced': synced,
      'synced_at': syncedAt ?? DateTime.now().millisecondsSinceEpoch,
      'bridge_device_id': bridgeDeviceId,
      'status': status,
      'assigned_to': assignedTo,
      'assigned_at': assignedAt,
      'status_updated_at': statusUpdatedAt ?? DateTime.now().millisecondsSinceEpoch,
      'resolution_notes': resolutionNotes,
    };
  }

  /// Convert to status update payload Map for Firestore update() calls
  Map<String, dynamic> toStatusUpdateMap() {
    return {
      'status': status,
      'assigned_to': assignedTo,
      'assigned_at': assignedAt,
      'status_updated_at': statusUpdatedAt ?? DateTime.now().millisecondsSinceEpoch,
      'resolution_notes': resolutionNotes,
    };
  }

  /// CopyWith helper
  IncidentModel copyWith({
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
    int? syncedAt,
    String? bridgeDeviceId,
    String? status,
    String? assignedTo,
    int? assignedAt,
    int? statusUpdatedAt,
    String? resolutionNotes,
  }) {
    return IncidentModel(
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
      syncedAt: syncedAt ?? this.syncedAt,
      bridgeDeviceId: bridgeDeviceId ?? this.bridgeDeviceId,
      status: status ?? this.status,
      assignedTo: assignedTo ?? this.assignedTo,
      assignedAt: assignedAt ?? this.assignedAt,
      statusUpdatedAt: statusUpdatedAt ?? this.statusUpdatedAt,
      resolutionNotes: resolutionNotes ?? this.resolutionNotes,
    );
  }

  // --- Helpers & Computeds ---

  bool get isOpen => status == IncidentStatus.open;
  bool get isAssigned => status == IncidentStatus.assigned;
  bool get isEnRoute => status == IncidentStatus.enRoute;
  bool get isResolved => status == IncidentStatus.resolved;
  bool get isActive => status != IncidentStatus.resolved;

  bool get isCritical => priorityTier.toLowerCase() == 'critical';
  bool get isUrgent => priorityTier.toLowerCase() == 'urgent';
  bool get isNeeds => priorityTier.toLowerCase() == 'needs';
  bool get isLow => priorityTier.toLowerCase() == 'low';

  bool get hasCoordinates => lat != null && lng != null;

  String get formattedTimeAgo {
    final now = DateTime.now().millisecondsSinceEpoch;
    final diffMs = now - timestamp;
    if (diffMs < 0) return 'Just now';

    final seconds = diffMs ~/ 1000;
    if (seconds < 60) return '${seconds}s ago';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '${minutes}m ago';
    final hours = minutes ~/ 60;
    if (hours < 24) return '${hours}h ago';
    final days = hours ~/ 24;
    return '${days}d ago';
  }
}
