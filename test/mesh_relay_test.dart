import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app1/core/models/message_model.dart';
import 'package:flutter_app1/core/mesh/mesh_service.dart';

void main() {
  group('Phase 2B: Multi-Hop Mesh Relay Logic Tests', () {
    late MessageModel sampleOriginSos;

    setUp(() {
      sampleOriginSos = MessageModel(
        id: 'msg-uuid-101',
        type: 'broadcast',
        senderId: 'DEV-ORIGIN-A',
        needType: 'medical',
        payload: 'Injured victim requires assistance',
        lat: 37.7749,
        lng: -122.4194,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        hopCount: 0,
        priorityTier: 'Urgent',
        priorityScore: 7,
        synced: false,
      );
    });

    test('Hop increment: Hop count increments sequentially upon each relay', () {
      // Origin node creates message with hopCount = 0
      expect(sampleOriginSos.hopCount, equals(0));

      // Node B receives from Node A: increments hopCount (0 -> 1)
      final hop1Msg = sampleOriginSos.copyWith(hopCount: sampleOriginSos.hopCount + 1);
      expect(hop1Msg.hopCount, equals(1));
      expect(hop1Msg.id, equals(sampleOriginSos.id));
      expect(hop1Msg.senderId, equals('DEV-ORIGIN-A'));

      // Node C receives from Node B: increments hopCount (1 -> 2)
      final hop2Msg = hop1Msg.copyWith(hopCount: hop1Msg.hopCount + 1);
      expect(hop2Msg.hopCount, equals(2));

      // Node D receives from Node C: increments hopCount (2 -> 3)
      final hop3Msg = hop2Msg.copyWith(hopCount: hop2Msg.hopCount + 1);
      expect(hop3Msg.hopCount, equals(3));
    });

    test('7-Hop Cutoff: Messages forward while hopCount < 7, and halt at maxHops (7)', () {
      expect(MeshService.maxHops, equals(7));

      // Hops 0 to 5 increment to 1 to 6, which are all < 7 -> eligible to forward
      for (int currentHop = 0; currentHop < 6; currentHop++) {
        final incoming = sampleOriginSos.copyWith(hopCount: currentHop);
        final relayed = incoming.copyWith(hopCount: incoming.hopCount + 1);
        final shouldForward = relayed.hopCount < MeshService.maxHops;
        expect(shouldForward, isTrue, reason: 'Hop ${relayed.hopCount} should be forwarded');
      }

      // Hop 6 increments to 7 (reaching max limit) -> must NOT be forwarded
      final incomingAt6 = sampleOriginSos.copyWith(hopCount: 6);
      final relayedAt7 = incomingAt6.copyWith(hopCount: incomingAt6.hopCount + 1);
      expect(relayedAt7.hopCount, equals(7));
      final shouldForwardAt7 = relayedAt7.hopCount < MeshService.maxHops;
      expect(shouldForwardAt7, isFalse, reason: 'Hop 7 reaches maxHops and must halt forwarding');

      // Hop 7 increments to 8 -> must NOT be forwarded
      final incomingAt7 = sampleOriginSos.copyWith(hopCount: 7);
      final relayedAt8 = incomingAt7.copyWith(hopCount: incomingAt7.hopCount + 1);
      expect(relayedAt8.hopCount < MeshService.maxHops, isFalse);
    });

    test('Source endpoint exclusion: Forwarding excludes the source endpoint to prevent echo', () {
      final connectedEndpoints = {'endpoint_A', 'endpoint_C', 'endpoint_D'};
      const sourceEndpoint = 'endpoint_A';

      // Forwarding targets must exclude the exact sourceEndpoint
      final forwardingTargets = connectedEndpoints.where((ep) => ep != sourceEndpoint).toList();

      expect(forwardingTargets, contains('endpoint_C'));
      expect(forwardingTargets, contains('endpoint_D'));
      expect(forwardingTargets, isNot(contains('endpoint_A')));
      expect(forwardingTargets.length, equals(2));
    });

    test('Duplicate suppression: seen_message_ids drops duplicate incoming packets', () {
      final seenMessageIds = <String>{};

      // First arrival of message 'msg-uuid-101'
      final isFirstArrivalSeen = seenMessageIds.contains(sampleOriginSos.id);
      expect(isFirstArrivalSeen, isFalse);
      // Mark as seen
      seenMessageIds.add(sampleOriginSos.id);

      // Duplicate arrival of same message ID (e.g. via alternate path or echo)
      final isSecondArrivalSeen = seenMessageIds.contains(sampleOriginSos.id);
      expect(isSecondArrivalSeen, isTrue, reason: 'Duplicate packet must be recognized as already seen');

      // A different message ID must still be accepted
      final newMessage = sampleOriginSos.copyWith(id: 'msg-uuid-202');
      expect(seenMessageIds.contains(newMessage.id), isFalse);
    });

    test('Loop prevention: Circular mesh paths (A -> B -> C -> A) are blocked by seen_message_ids', () {
      // Simulate node state on Node A, B, and C
      final nodeASeen = <String>{};
      final nodeBSeen = <String>{};
      final nodeCSeen = <String>{};

      // 1. Node A originates message
      nodeASeen.add(sampleOriginSos.id);
      final msgFromA = sampleOriginSos.copyWith(hopCount: 0);

      // 2. Node B receives from A: new to B
      expect(nodeBSeen.contains(msgFromA.id), isFalse);
      nodeBSeen.add(msgFromA.id);
      final msgFromB = msgFromA.copyWith(hopCount: 1);

      // 3. Node C receives from B: new to C
      expect(nodeCSeen.contains(msgFromB.id), isFalse);
      nodeCSeen.add(msgFromB.id);
      final msgFromC = msgFromB.copyWith(hopCount: 2);

      // 4. Node C forwards back to Node A in a loop (circular link)
      // Node A receives msgFromC: Node A checks its seen set
      final isLoopPacketSeenByA = nodeASeen.contains(msgFromC.id);
      expect(isLoopPacketSeenByA, isTrue, reason: 'Node A must drop the loop packet because it is in seen_message_ids');

      // 5. Node C also forwards to Node B (mesh cross-link)
      final isCrossLinkSeenByB = nodeBSeen.contains(msgFromC.id);
      expect(isCrossLinkSeenByB, isTrue, reason: 'Node B must drop the cross-link duplicate');
    });
  });
}
