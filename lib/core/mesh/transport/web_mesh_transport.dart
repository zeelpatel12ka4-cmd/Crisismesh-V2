import 'package:flutter/foundation.dart';
import 'mesh_transport.dart';

/// Web no-op implementation of [MeshTransport].
/// Flutter Web cannot use Nearby Connections (Android-only native SDK).
/// All methods are safe no-ops that log a warning and return gracefully.
class WebMeshTransport implements MeshTransport {
  @override
  bool get isSupportedOnCurrentPlatform => false;

  @override
  Future<bool> checkAndRequestPermissions() async {
    debugPrint('[WebMeshTransport] Mesh not supported on Web. Permissions skipped.');
    return false;
  }

  @override
  Future<bool> startAdvertising({
    required String localDeviceId,
    required String serviceId,
    required void Function(String endpointId, dynamic info) onConnectionInitiated,
    required void Function(String endpointId, dynamic status) onConnectionResult,
    required void Function(String endpointId) onDisconnected,
  }) async {
    debugPrint('[WebMeshTransport] startAdvertising is a no-op on Web.');
    return false;
  }

  @override
  Future<bool> startDiscovery({
    required String localDeviceId,
    required String serviceId,
    required void Function(String endpointId, String endpointName, String serviceId) onEndpointFound,
    required void Function(String? endpointId) onEndpointLost,
  }) async {
    debugPrint('[WebMeshTransport] startDiscovery is a no-op on Web.');
    return false;
  }

  @override
  Future<void> stopDiscovery() async {
    debugPrint('[WebMeshTransport] stopDiscovery called on Web (no-op).');
  }

  @override
  Future<void> stopAdvertising() async {
    debugPrint('[WebMeshTransport] stopAdvertising called on Web (no-op).');
  }

  @override
  Future<void> stopAllEndpoints() async {
    debugPrint('[WebMeshTransport] stopAllEndpoints called on Web (no-op).');
  }

  @override
  Future<bool> requestConnection({
    required String localDeviceId,
    required String endpointId,
    required void Function(String endpointId, dynamic info) onConnectionInitiated,
    required void Function(String endpointId, dynamic status) onConnectionResult,
    required void Function(String endpointId) onDisconnected,
  }) async {
    debugPrint('[WebMeshTransport] requestConnection is a no-op on Web.');
    return false;
  }

  @override
  Future<bool> acceptConnection({
    required String endpointId,
    required void Function(String endpointId, dynamic payload) onPayloadReceived,
  }) async {
    debugPrint('[WebMeshTransport] acceptConnection is a no-op on Web.');
    return false;
  }

  @override
  Future<void> sendBytesPayload(String endpointId, Uint8List bytes) async {
    debugPrint('[WebMeshTransport] sendBytesPayload is a no-op on Web.');
  }
}
