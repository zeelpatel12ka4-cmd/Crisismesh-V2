import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'mesh_transport.dart';

/// iOS placeholder implementation of [MeshTransport].
/// Allows Crisis Mesh to build and run seamlessly on iOS/iPhone without crashes,
/// while preparing for native Apple Network.framework peer-to-peer transport in Phase 2.
class IosMeshTransport implements MeshTransport {
  @override
  bool get isSupportedOnCurrentPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Future<bool> checkAndRequestPermissions() async {
    try {
      final permissions = [
        Permission.location,
        Permission.bluetooth,
      ];

      final statuses = await permissions.request();
      final locationGranted = statuses[Permission.location]?.isGranted ?? false;
      final bluetoothGranted = statuses[Permission.bluetooth]?.isGranted ?? true;

      debugPrint(
          '[IosMeshTransport] iOS permissions checked: location=$locationGranted, bluetooth=$bluetoothGranted');
      return locationGranted;
    } catch (e) {
      debugPrint('[IosMeshTransport] Error requesting iOS permissions: $e');
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
    debugPrint(
        '[IosMeshTransport] iOS mesh advertising placeholder active (Apple Network.framework transport scheduled for Phase 2).');
    return false;
  }

  @override
  Future<bool> startDiscovery({
    required String localDeviceId,
    required String serviceId,
    required void Function(String endpointId, String endpointName, String serviceId) onEndpointFound,
    required void Function(String? endpointId) onEndpointLost,
  }) async {
    debugPrint(
        '[IosMeshTransport] iOS mesh discovery placeholder active (Apple Network.framework transport scheduled for Phase 2).');
    return false;
  }

  @override
  Future<void> stopDiscovery() async {
    debugPrint('[IosMeshTransport] stopDiscovery called on iOS.');
  }

  @override
  Future<void> stopAdvertising() async {
    debugPrint('[IosMeshTransport] stopAdvertising called on iOS.');
  }

  @override
  Future<void> stopAllEndpoints() async {
    debugPrint('[IosMeshTransport] stopAllEndpoints called on iOS.');
  }

  @override
  Future<bool> requestConnection({
    required String localDeviceId,
    required String endpointId,
    required void Function(String endpointId, dynamic info) onConnectionInitiated,
    required void Function(String endpointId, dynamic status) onConnectionResult,
    required void Function(String endpointId) onDisconnected,
  }) async {
    debugPrint('[IosMeshTransport] requestConnection placeholder on iOS.');
    return false;
  }

  @override
  Future<bool> acceptConnection({
    required String endpointId,
    required void Function(String endpointId, dynamic payload) onPayloadReceived,
  }) async {
    debugPrint('[IosMeshTransport] acceptConnection placeholder on iOS.');
    return false;
  }

  @override
  Future<void> sendBytesPayload(String endpointId, Uint8List bytes) async {
    debugPrint('[IosMeshTransport] sendBytesPayload placeholder on iOS.');
  }
}
