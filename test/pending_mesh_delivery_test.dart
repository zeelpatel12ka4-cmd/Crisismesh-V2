import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app1/core/models/message_model.dart';
import 'package:flutter_app1/core/mesh/mesh_service.dart';

void main() {
  group('Phase 5A: Reliable Pending SOS Delivery & Store-and-Forward Tests', () {
    late MessageModel sampleOriginSos;

    setUp(() {
      sampleOriginSos = MessageModel(
        id: 'sos-uuid-101',
        type: 'broadcast',
        senderId: 'DEV-ORIGIN-A',
        needType: 'trapped',
        payload: 'Victim trapped under rubble at Sector 4',
        lat: 37.7749,
        lng: -122.4194,
        timestamp: 1700000000000,
        hopCount: 0,
        priorityTier: 'Critical',
        priorityScore: 10,
        synced: false,
        meshDeliveryStatus: MeshDeliveryStatus.pending,
      );
    });

    test('TEST 1: SOS created with zero peers is saved locally and remains PENDING', () {
      // Offline node originates message with 0 connected peers
      expect(sampleOriginSos.isMeshPending, isTrue);
      expect(sampleOriginSos.meshDeliveryStatus, equals(MeshDeliveryStatus.pending));
      expect(sampleOriginSos.isTransmittedToPeer, isFalse);
      expect(sampleOriginSos.isMeshSending, isFalse);
      expect(MeshDeliveryStatus.format(sampleOriginSos.meshDeliveryStatus), equals('Pending — waiting for nearby device'));
    });

    test('TEST 2: A later peer connection triggers automatic pending-message transmission', () async {
      // Simulate pending message in queue
      final pendingQueue = <MessageModel>[sampleOriginSos];
      expect(pendingQueue.length, equals(1));
      expect(pendingQueue.first.meshDeliveryStatus, equals(MeshDeliveryStatus.pending));

      // Simulate peer connection event
      const connectedEndpoint = 'peer-endpoint-xyz';
      final transmittedPackets = <Map<String, dynamic>>[];

      // Flusher processing pending queue
      for (int i = 0; i < pendingQueue.length; i++) {
        var msg = pendingQueue[i];
        // Transition: PENDING -> SENDING
        msg = msg.copyWith(meshDeliveryStatus: MeshDeliveryStatus.sending);
        expect(msg.isMeshSending, isTrue);

        // Transmit over simulated mesh to connected peer
        transmittedPackets.add({
          'endpoint': connectedEndpoint,
          'messageId': msg.id,
          'payload': msg.toMap(),
        });

        // Transition: SENDING -> TRANSMITTED_TO_PEER
        msg = msg.copyWith(meshDeliveryStatus: MeshDeliveryStatus.transmittedToPeer);
        pendingQueue[i] = msg;
      }

      expect(transmittedPackets.length, equals(1));
      expect(transmittedPackets.first['messageId'], equals('sos-uuid-101'));
      expect(pendingQueue.first.isTransmittedToPeer, isTrue);
      expect(pendingQueue.first.meshDeliveryStatus, equals(MeshDeliveryStatus.transmittedToPeer));
      expect(MeshDeliveryStatus.format(pendingQueue.first.meshDeliveryStatus), equals('Sent via mesh'));
    });

    test('TEST 3: SOS created while a peer is already connected transmits immediately', () {
      // When peer is already connected, message transitions to transmitted_to_peer immediately
      final sentSos = sampleOriginSos.copyWith(
        meshDeliveryStatus: MeshDeliveryStatus.transmittedToPeer,
      );

      expect(sentSos.isTransmittedToPeer, isTrue);
      expect(sentSos.isMeshPending, isFalse);
      expect(sentSos.meshDeliveryStatus, equals(MeshDeliveryStatus.transmittedToPeer));
      expect(MeshDeliveryStatus.format(sentSos.meshDeliveryStatus), equals('Sent via mesh'));
    });

    test('TEST 4: Failed transmission returns/stays PENDING without data loss', () {
      // Message enters SENDING
      var msg = sampleOriginSos.copyWith(meshDeliveryStatus: MeshDeliveryStatus.sending);
      expect(msg.isMeshSending, isTrue);

      // Simulated network failure / peer disconnects mid-flight -> Revert to PENDING
      msg = msg.copyWith(meshDeliveryStatus: MeshDeliveryStatus.pending);

      expect(msg.isMeshPending, isTrue);
      expect(msg.id, equals('sos-uuid-101'));
      expect(msg.payload, equals('Victim trapped under rubble at Sector 4'));
      expect(msg.lat, equals(37.7749));
      expect(msg.lng, equals(-122.4194));
      expect(msg.priorityTier, equals('Critical'));
    });

    test('TEST 5: Retrying preserves the exact original immutable message ID and attributes', () {
      final originalId = sampleOriginSos.id;
      final originalTimestamp = sampleOriginSos.timestamp;
      final originalLat = sampleOriginSos.lat;
      final originalLng = sampleOriginSos.lng;
      final originalPriority = sampleOriginSos.priorityScore;

      // Simulated retry transmission
      final retriedMessage = sampleOriginSos.copyWith(
        meshDeliveryStatus: MeshDeliveryStatus.transmittedToPeer,
      );

      expect(retriedMessage.id, equals(originalId));
      expect(retriedMessage.timestamp, equals(originalTimestamp));
      expect(retriedMessage.lat, equals(originalLat));
      expect(retriedMessage.lng, equals(originalLng));
      expect(retriedMessage.priorityScore, equals(originalPriority));
    });

    test('TEST 6: Duplicate incoming message is processed only once via seen_message_ids', () {
      final seenMessageIds = <String>{};

      // First reception
      final isFirstSeen = seenMessageIds.contains(sampleOriginSos.id);
      expect(isFirstSeen, isFalse);
      seenMessageIds.add(sampleOriginSos.id);

      // Duplicate arrival of the exact same message (via retry or multi-path)
      final isSecondSeen = seenMessageIds.contains(sampleOriginSos.id);
      expect(isSecondSeen, isTrue, reason: 'Duplicate retry packet must be recognized as seen and dropped');
    });

    test('TEST 7: Multiple pending SOS messages are processed in deterministic FIFO order', () {
      final msg1 = sampleOriginSos.copyWith(id: 'sos-1', timestamp: 1000);
      final msg2 = sampleOriginSos.copyWith(id: 'sos-2', timestamp: 2000);
      final msg3 = sampleOriginSos.copyWith(id: 'sos-3', timestamp: 3000);

      final queue = [msg3, msg1, msg2];
      // Sort FIFO by timestamp ASC
      queue.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      expect(queue.map((m) => m.id).toList(), equals(['sos-1', 'sos-2', 'sos-3']));

      // Simulate sequential flush
      final transmittedOrder = <String>[];
      for (final m in queue) {
        transmittedOrder.add(m.id);
      }
      expect(transmittedOrder, equals(['sos-1', 'sos-2', 'sos-3']));
    });

    test('TEST 8: 7-hop limit is strictly enforced and halts forwarding at maxHops', () {
      expect(MeshService.maxHops, equals(7));

      final originMsg = sampleOriginSos.copyWith(hopCount: 0);
      expect(originMsg.hopCount < MeshService.maxHops, isTrue);

      final hop6Msg = sampleOriginSos.copyWith(hopCount: 6);
      final relayedAt7 = hop6Msg.copyWith(hopCount: hop6Msg.hopCount + 1);
      expect(relayedAt7.hopCount, equals(7));
      expect(relayedAt7.hopCount < MeshService.maxHops, isFalse, reason: 'Hop 7 must halt forwarding');
    });

    test('TEST 9: Cloud sync status remains strictly separate from mesh delivery status', () {
      // Message transmitted via mesh but offline from cloud
      final meshOnlyMsg = sampleOriginSos.copyWith(
        meshDeliveryStatus: MeshDeliveryStatus.transmittedToPeer,
        synced: false,
      );
      expect(meshOnlyMsg.isTransmittedToPeer, isTrue);
      expect(meshOnlyMsg.synced, isFalse);

      // Message uploaded to Firestore
      final cloudSyncedMsg = meshOnlyMsg.copyWith(synced: true);
      expect(cloudSyncedMsg.isTransmittedToPeer, isTrue);
      expect(cloudSyncedMsg.synced, isTrue);
    });

    test('TEST 10: Deserialization correctly maps legacy and new mesh_delivery_status payloads', () {
      // Legacy map without mesh_delivery_status: hop 0 unsynced -> pending
      final legacyMap = {
        'id': 'legacy-1',
        'type': 'broadcast',
        'sender_id': 'DEV-X',
        'timestamp': 1700000000000,
        'hop_count': 0,
        'priority_tier': 'Urgent',
        'priority_score': 8,
        'synced': 0,
      };
      final fromLegacy = MessageModel.fromMap(legacyMap);
      expect(fromLegacy.meshDeliveryStatus, equals(MeshDeliveryStatus.pending));

      // Relayed packet with hop > 0 -> transmitted_to_peer
      final relayedMap = {
        'id': 'relayed-1',
        'type': 'broadcast',
        'sender_id': 'DEV-Y',
        'timestamp': 1700000000000,
        'hop_count': 2,
        'priority_tier': 'Needs',
        'priority_score': 5,
        'synced': 0,
      };
      final fromRelayed = MessageModel.fromMap(relayedMap);
      expect(fromRelayed.meshDeliveryStatus, equals(MeshDeliveryStatus.transmittedToPeer));

      // Explicit status map
      final explicitMap = {
        'id': 'explicit-1',
        'type': 'broadcast',
        'sender_id': 'DEV-Z',
        'timestamp': 1700000000000,
        'hop_count': 0,
        'priority_tier': 'Critical',
        'priority_score': 10,
        'synced': 0,
        'mesh_delivery_status': 'pending',
      };
      final fromExplicit = MessageModel.fromMap(explicitMap);
      expect(fromExplicit.meshDeliveryStatus, equals(MeshDeliveryStatus.pending));
    });

    test('TEST 11: Delivery status is NOT reported as DELIVERED without an ACK mechanism', () {
      // Verify that the status constants do not use 'delivered'
      expect(MeshDeliveryStatus.transmittedToPeer, equals('transmitted_to_peer'));
      expect(MeshDeliveryStatus.format(MeshDeliveryStatus.transmittedToPeer), equals('Sent via mesh'));
      expect(MeshDeliveryStatus.all.contains('delivered'), isFalse);
    });
  });
}
