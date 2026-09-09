import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'mesh_transport.dart';

/// Android implementation of [MeshTransport] wrapping Google Nearby Connections P2P_CLUSTER.
class AndroidMeshTransport implements MeshTransport {
  final Strategy _strategy = Strategy.P2P_CLUSTER;

  @override
  bool get isSupportedOnCurrentPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> checkAndRequestPermissions() async {
    try {
      final permissions = [
        Permission.location,
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.nearbyWifiDevices,
        Permission.notification,
      ];

      final statuses = await permissions.request();

      final locationGranted = statuses[Permission.location]?.isGranted ?? false;
      final btScanGranted = statuses[Permission.bluetoothScan]?.isGranted ?? true;
      final btAdvGranted = statuses[Permission.bluetoothAdvertise]?.isGranted ?? true;
      final btConnGranted = statuses[Permission.bluetoothConnect]?.isGranted ?? true;

      final isGranted = locationGranted && btScanGranted && btAdvGranted && btConnGranted;
      if (!isGranted) {
        debugPrint(
            '[AndroidMeshTransport] Permissions incomplete: location=$locationGranted, btScan=$btScanGranted, btAdv=$btAdvGranted, btConn=$btConnGranted');
      }
      return isGranted;
    } catch (e) {
      debugPrint('[AndroidMeshTransport] Error requesting permissions: $e');
      return false;
    }
  }

  @override
  Future<bool> startAdvertising({
    required String localDeviceId,
    required String serviceId,
    required void Function(String endpointId, dynamic info) onConnectionInitiated,
    required void Function(String endpointId, dynamic status) onConnectionResult,
    required void Function(String endpointId) onDisconnected,
  }) async {
    try {
      return await Nearby().startAdvertising(
        localDeviceId,
        _strategy,
        onConnectionInitiated: (endId, info) => onConnectionInitiated(endId, info),
        onConnectionResult: (endId, status) => onConnectionResult(endId, status),
        onDisconnected: onDisconnected,
        serviceId: serviceId,
      );
    } catch (e) {
      debugPrint('[AndroidMeshTransport] startAdvertising failed: $e');
      return false;
    }
  }

  @override
  Future<bool> startDiscovery({
    required String localDeviceId,
    required String serviceId,
    required void Function(String endpointId, String endpointName, String serviceId) onEndpointFound,
    required void Function(String? endpointId) onEndpointLost,
  }) async {
    try {
      return await Nearby().startDiscovery(
        localDeviceId,
        _strategy,
        onEndpointFound: onEndpointFound,
        onEndpointLost: onEndpointLost,
        serviceId: serviceId,
      );
    } catch (e) {
      debugPrint('[AndroidMeshTransport] startDiscovery failed: $e');
      return false;
    }
  }

  @override
  Future<void> stopDiscovery() async {
    try {
      await Nearby().stopDiscovery();
    } catch (e) {
      debugPrint('[AndroidMeshTransport] stopDiscovery failed: $e');
    }
  }

  @override
  Future<void> stopAdvertising() async {
    try {
      await Nearby().stopAdvertising();
    } catch (e) {
      debugPrint('[AndroidMeshTransport] stopAdvertising failed: $e');
    }
  }

  @override
  Future<void> stopAllEndpoints() async {
    try {
      await Nearby().stopAllEndpoints();
    } catch (e) {
      debugPrint('[AndroidMeshTransport] stopAllEndpoints failed: $e');
    }
  }

  @override
  Future<bool> requestConnection({
    required String localDeviceId,
    required String endpointId,
    required void Function(String endpointId, dynamic info) onConnectionInitiated,
    required void Function(String endpointId, dynamic status) onConnectionResult,
    required void Function(String endpointId) onDisconnected,
  }) async {
    try {
      return await Nearby().requestConnection(
        localDeviceId,
        endpointId,
        onConnectionInitiated: (endId, info) => onConnectionInitiated(endId, info),
        onConnectionResult: (endId, status) => onConnectionResult(endId, status),
        onDisconnected: onDisconnected,
      );
    } catch (e) {
      debugPrint('[AndroidMeshTransport] requestConnection failed: $e');
      return false;
    }
  }

  @override
  Future<bool> acceptConnection({
    required String endpointId,
    required void Function(String endpointId, dynamic payload) onPayloadReceived,
  }) async {
    try {
      return await Nearby().acceptConnection(
        endpointId,
        onPayLoadRecieved: (endId, payload) => onPayloadReceived(endId, payload),
      );
    } catch (e) {
      debugPrint('[AndroidMeshTransport] acceptConnection failed: $e');
      return false;
    }
  }

  @override
  Future<void> sendBytesPayload(String endpointId, Uint8List bytes) async {
    await Nearby().sendBytesPayload(endpointId, bytes);
  }
}
