import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:flutter_app1/core/mesh/mesh_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 6: Peer Connection & Mesh State Reliability Tests', () {
    final List<String> requestedEndpoints = [];

    setUpAll(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.crisismesh.app/background_service'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'startForegroundService') return true;
          if (methodCall.method == 'stopForegroundService') return true;
          if (methodCall.method == 'isForegroundServiceRunning') return true;
          return null;
        },
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/permissions/methods'),
        (MethodCall methodCall) async {
          final Map<int, int> results = {};
          if (methodCall.arguments is List) {
            for (final p in methodCall.arguments as List) {
              if (p is int) results[p] = 1; // granted
            }
          }
          results[0] = 1;
          results[3] = 1;
          results[4] = 1;
          results[5] = 1;
          results[17] = 1;
          results[28] = 1;
          results[29] = 1;
          results[30] = 1;
          results[31] = 1;
          results[32] = 1;
          return results;
        },
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('nearby_connections'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'requestConnection') {
            final endpointId = methodCall.arguments['endpointId'] as String;
            requestedEndpoints.add(endpointId);
            return true;
          }
          return true;
        },
      );
    });

    setUp(() {
      requestedEndpoints.clear();
      MeshService.instance.init(
        localDeviceId: 'DEV-1000',
        onMessageReceived: (msg, ep) async {},
      );
    });

    tearDown(() async {
      await MeshService.instance.stopMesh();
      requestedEndpoints.clear();
    });

    test('TEST 1: connectedPeerCount = 0 when idle and when searching', () async {
      expect(MeshService.instance.status, equals(MeshStatus.idle));
      expect(MeshService.instance.connectedPeerCount, equals(0));
      expect(MeshService.instance.isConnected, isFalse);

      await MeshService.instance.startMesh();
      expect(MeshService.instance.status, equals(MeshStatus.searching));
      expect(MeshService.instance.connectedPeerCount, equals(0));
      expect(MeshService.instance.isConnected, isFalse);
    });

    test('TEST 2: Deterministic Tie-Breaker: lower device ID initiates connection, higher device ID waits', () async {
      await MeshService.instance.startMesh();
      expect(MeshService.instance.localDeviceId, equals('DEV-1000'));

      // Case A: Discovered peer has HIGHER ID ('DEV-2000' > 'DEV-1000') -> Local MUST initiate
      MeshService.instance.onEndpointFoundForTest('ep_higher', 'DEV-2000', 'com.crisismesh.mesh');
      expect(requestedEndpoints, contains('ep_higher'));
      expect(MeshService.instance.connectingEndpoints, contains('ep_higher'));

      // Case B: Discovered peer has LOWER ID ('DEV-0500' < 'DEV-1000') -> Local MUST wait for peer
      MeshService.instance.onEndpointFoundForTest('ep_lower', 'DEV-0500', 'com.crisismesh.mesh');
      expect(requestedEndpoints, isNot(contains('ep_lower')));
      expect(MeshService.instance.connectingEndpoints, isNot(contains('ep_lower')));
    });

    test('TEST 3: In-flight handshake deduplication: duplicate endpointFound does not duplicate request', () async {
      await MeshService.instance.startMesh();

      MeshService.instance.onEndpointFoundForTest('ep_dup', 'DEV-9999', 'com.crisismesh.mesh');
      expect(requestedEndpoints.where((ep) => ep == 'ep_dup').length, equals(1));

      // Second identical callback while connection is in-flight
      MeshService.instance.onEndpointFoundForTest('ep_dup', 'DEV-9999', 'com.crisismesh.mesh');
      expect(requestedEndpoints.where((ep) => ep == 'ep_dup').length, equals(1));
    });

    test('TEST 4: Connecting endpoint removed from connectingEndpoints upon success or failure', () async {
      await MeshService.instance.startMesh();

      // Initiate towards DEV-9000
      MeshService.instance.onEndpointFoundForTest('ep_test', 'DEV-9000', 'com.crisismesh.mesh');
      expect(MeshService.instance.connectingEndpoints, contains('ep_test'));

      // Success callback
      MeshService.instance.onConnectionResultForTest('ep_test', Status.CONNECTED);
      expect(MeshService.instance.connectingEndpoints, isNot(contains('ep_test')));
      expect(MeshService.instance.connectedEndpoints, contains('ep_test'));
      expect(MeshService.instance.connectedPeerCount, equals(1));
      expect(MeshService.instance.status, equals(MeshStatus.connected));
    });

    test('TEST 5: Failed duplicate request does NOT remove an already-connected peer', () async {
      await MeshService.instance.startMesh();

      // Peer connected successfully
      MeshService.instance.onConnectionResultForTest('ep_active', Status.CONNECTED);
      expect(MeshService.instance.connectedEndpoints, contains('ep_active'));
      expect(MeshService.instance.connectedPeerCount, equals(1));

      // Collided or duplicate request returns failure
      MeshService.instance.onConnectionResultForTest('ep_active', Status.REJECTED);
      // Connected peer MUST remain preserved
      expect(MeshService.instance.connectedEndpoints, contains('ep_active'));
      expect(MeshService.instance.connectedPeerCount, equals(1));
      expect(MeshService.instance.status, equals(MeshStatus.connected));
    });

    test('TEST 6: Multi-peer disconnect handling: 2 peers -> 1 peer -> 0 peers', () async {
      await MeshService.instance.startMesh();

      int notifications = 0;
      MeshService.instance.addListener(() {
        notifications++;
      });

      // Connect 2 peers
      MeshService.instance.onConnectionResultForTest('ep_peer_1', Status.CONNECTED);
      MeshService.instance.onConnectionResultForTest('ep_peer_2', Status.CONNECTED);

      expect(MeshService.instance.connectedPeerCount, equals(2));
      expect(MeshService.instance.status, equals(MeshStatus.connected));

      // Disconnect 1 peer (2 -> 1)
      notifications = 0;
      MeshService.instance.onDisconnectedForTest('ep_peer_1');
      expect(MeshService.instance.connectedPeerCount, equals(1));
      expect(MeshService.instance.status, equals(MeshStatus.connected));
      expect(notifications, greaterThanOrEqualTo(1));

      // Disconnect final peer (1 -> 0)
      notifications = 0;
      MeshService.instance.onDisconnectedForTest('ep_peer_2');
      expect(MeshService.instance.connectedPeerCount, equals(0));
      expect(MeshService.instance.status, equals(MeshStatus.searching));
      expect(notifications, greaterThanOrEqualTo(1));
    });

    test('TEST 7: Stable local device ID survives re-initialization and stop/start', () async {
      final initialId = MeshService.instance.localDeviceId;
      expect(initialId, isNotEmpty);

      // Re-init without specifying new ID
      MeshService.instance.init(
        onMessageReceived: (msg, ep) async {},
      );
      expect(MeshService.instance.localDeviceId, equals(initialId));

      await MeshService.instance.startMesh();
      expect(MeshService.instance.localDeviceId, equals(initialId));

      await MeshService.instance.stopMesh();
      expect(MeshService.instance.localDeviceId, equals(initialId));
    });

    test('TEST 8: Phase 5A Pending SOS flushes upon peer connection', () async {
      int flushCount = 0;
      MeshService.instance.init(
        localDeviceId: 'DEV-1000',
        onMessageReceived: (msg, ep) async {},
        pendingMessageFlusher: () async {
          flushCount++;
          return 1;
        },
      );

      await MeshService.instance.startMesh();
      expect(flushCount, equals(0));

      MeshService.instance.onConnectionResultForTest('ep_flush_peer', Status.CONNECTED);
      expect(flushCount, equals(1));
    });
  });
}
