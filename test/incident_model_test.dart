import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app1/core/models/incident_model.dart';
import 'package:flutter_app1/core/models/message_model.dart';

void main() {
  group('Phase 4: IncidentModel Tests', () {
    test('1. Deserialization from full Firestore Map with operational fields', () {
      final map = {
        'id': 'incident-uuid-001',
        'type': 'broadcast',
        'sender_id': 'DEV-VICTIM-1',
        'payload': 'Two people trapped under roof collapse',
        'need_type': 'trapped',
        'lat': 23.287434,
        'lng': 72.346430,
        'timestamp': 1700000000000,
        'hop_count': 2,
        'priority_tier': 'Critical',
        'priority_score': 10,
        'synced': true,
        'synced_at': 1700000005000,
        'bridge_device_id': 'DEV-BRIDGE-1',
        'status': 'assigned',
        'assigned_to': 'Rescue-Alpha',
        'assigned_at': 1700000010000,
        'status_updated_at': 1700000010000,
        'resolution_notes': null,
      };

      final incident = IncidentModel.fromMap(map, documentId: 'incident-uuid-001');

      expect(incident.id, equals('incident-uuid-001'));
      expect(incident.senderId, equals('DEV-VICTIM-1'));
      expect(incident.needType, equals('trapped'));
      expect(incident.lat, equals(23.287434));
      expect(incident.lng, equals(72.346430));
      expect(incident.priorityTier, equals('Critical'));
      expect(incident.priorityScore, equals(10));
      expect(incident.status, equals(IncidentStatus.assigned));
      expect(incident.assignedTo, equals('Rescue-Alpha'));
      expect(incident.isAssigned, isTrue);
      expect(incident.isActive, isTrue);
      expect(incident.isCritical, isTrue);
      expect(incident.hasCoordinates, isTrue);
    });

    test('2. Backwards compatibility: Missing status in legacy Firestore doc defaults to "open"', () {
      final legacyMap = {
        'id': 'legacy-doc-123',
        'type': 'broadcast',
        'sender_id': 'DEV-LEGACY',
        'payload': 'Need clean drinking water',
        'need_type': 'water',
        'timestamp': 1700000000000,
        'priority_tier': 'Needs',
        'priority_score': 4,
        // Notice: no 'status', 'assigned_to', etc.
      };

      final incident = IncidentModel.fromMap(legacyMap, documentId: 'legacy-doc-123');

      expect(incident.status, equals(IncidentStatus.open));
      expect(incident.isOpen, isTrue);
      expect(incident.isActive, isTrue);
      expect(incident.isAssigned, isFalse);
      expect(incident.isResolved, isFalse);
      expect(incident.assignedTo, isNull);
    });

    test('3. Conversion from MessageModel preserves all core triage and routing data', () {
      final message = MessageModel(
        id: 'msg-999',
        type: 'broadcast',
        senderId: 'DEV-NODE-8',
        needType: 'medical',
        payload: 'Severe bleeding trauma',
        lat: 23.2900,
        lng: 72.3500,
        timestamp: 1700000000000,
        hopCount: 3,
        priorityTier: 'Critical',
        priorityScore: 9,
        synced: true,
      );

      final incident = IncidentModel.fromMessageModel(message);

      expect(incident.id, equals('msg-999'));
      expect(incident.needType, equals('medical'));
      expect(incident.payload, equals('Severe bleeding trauma'));
      expect(incident.hopCount, equals(3));
      expect(incident.priorityTier, equals('Critical'));
      expect(incident.priorityScore, equals(9));
      expect(incident.status, equals(IncidentStatus.open));
    });

    test('4. Status transition helper methods and copyWith updates', () {
      var incident = IncidentModel(
        id: 'inc-1',
        senderId: 'DEV-1',
        timestamp: 1700000000000,
        priorityTier: 'Critical',
        priorityScore: 10,
      );

      expect(incident.isOpen, isTrue);
      expect(incident.isActive, isTrue);

      // Transition to Assigned
      incident = incident.copyWith(
        status: IncidentStatus.assigned,
        assignedTo: 'Medic-1',
        assignedAt: 1700000010000,
      );
      expect(incident.isAssigned, isTrue);
      expect(incident.isOpen, isFalse);
      expect(incident.isActive, isTrue);
      expect(incident.assignedTo, equals('Medic-1'));

      // Transition to En Route
      incident = incident.copyWith(status: IncidentStatus.enRoute);
      expect(incident.isEnRoute, isTrue);
      expect(incident.isActive, isTrue);

      // Transition to Resolved
      incident = incident.copyWith(
        status: IncidentStatus.resolved,
        resolutionNotes: 'Victim transported to hospital',
      );
      expect(incident.isResolved, isTrue);
      expect(incident.isActive, isFalse);
      expect(incident.resolutionNotes, equals('Victim transported to hospital'));
    });

    test('5. Firestore map serialization includes all operational fields', () {
      final incident = IncidentModel(
        id: 'inc-export-1',
        senderId: 'DEV-EXP',
        payload: 'Fire spreading in sector 3',
        needType: 'fire',
        lat: 23.2800,
        lng: 72.3400,
        timestamp: 1700000000000,
        hopCount: 1,
        priorityTier: 'Critical',
        priorityScore: 9,
        status: IncidentStatus.enRoute,
        assignedTo: 'Fire-Rescue-9',
        assignedAt: 1700000020000,
      );

      final map = incident.toFirestoreMap();

      expect(map['id'], equals('inc-export-1'));
      expect(map['status'], equals('en_route'));
      expect(map['assigned_to'], equals('Fire-Rescue-9'));
      expect(map['assigned_at'], equals(1700000020000));
      expect(map['priority_tier'], equals('Critical'));
      expect(map['priority_score'], equals(9));
    });

    test('6. Safe deserialization of heterogeneous and string-encoded Firestore fields', () {
      final variedMap = {
        'message_id': 'varied-doc-456',
        'senderId': 'NODE-CAMEL',
        'description': 'Bridge collapsed, urgent help needed',
        'needType': 'trapped',
        'latitude': '23.2874',
        'longitude': '72.3464',
        'timestamp': '1700000000000',
        'hopCount': '2',
        'priorityScore': '8',
        'synced': 'true',
      };

      final incident = IncidentModel.fromMap(variedMap, documentId: 'varied-doc-456');

      expect(incident.id, equals('varied-doc-456'));
      expect(incident.senderId, equals('NODE-CAMEL'));
      expect(incident.payload, equals('Bridge collapsed, urgent help needed'));
      expect(incident.needType, equals('trapped'));
      expect(incident.lat, equals(23.2874));
      expect(incident.lng, equals(72.3464));
      expect(incident.timestamp, equals(1700000000000));
      expect(incident.hopCount, equals(2));
      expect(incident.priorityScore, equals(8));
      expect(incident.priorityTier, equals('Urgent')); // Inferred from score 8
      expect(incident.synced, isTrue);
      expect(incident.status, equals(IncidentStatus.open));
    });

    test('7. Empty map with missing fields does not crash and provides sensible defaults', () {
      final emptyMap = <String, dynamic>{};

      final incident = IncidentModel.fromMap(emptyMap, documentId: 'empty-doc-999');

      expect(incident.id, equals('empty-doc-999'));
      expect(incident.senderId, equals('UNKNOWN'));
      expect(incident.payload, isNull);
      expect(incident.needType, isNull);
      expect(incident.lat, isNull);
      expect(incident.lng, isNull);
      expect(incident.hasCoordinates, isFalse);
      expect(incident.priorityScore, equals(1));
      expect(incident.priorityTier, equals('Low'));
      expect(incident.status, equals(IncidentStatus.open));
    });
  });
}
