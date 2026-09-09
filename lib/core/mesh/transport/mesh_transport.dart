import 'dart:typed_data';

/// Abstract transport layer interface for Crisis Mesh peer-to-peer networking.
/// Decouples shared SOS, triage, and cryptographic routing logic from
/// platform-specific mesh implementations (e.g. Nearby Connections on Android,
/// Apple Network.framework on iOS).
abstract class MeshTransport {
  /// Whether peer-to-peer mesh networking is supported on this platform.
  bool get isSupportedOnCurrentPlatform;

  /// Verifies and requests runtime platform permissions required for mesh operations.
  Future<bool> checkAndRequestPermissions();

  /// Starts broadcasting peer presence over local radio.
  Future<bool> startAdvertising({
    required String localDeviceId,
    required String serviceId,
    required void Function(String endpointId, dynamic info) onConnectionInitiated,
    required void Function(String endpointId, dynamic status) onConnectionResult,
    required void Function(String endpointId) onDisconnected,
  });

  /// Starts scanning for nearby peer devices.
  Future<bool> startDiscovery({
    required String localDeviceId,
    required String serviceId,
    required void Function(String endpointId, String endpointName, String serviceId) onEndpointFound,
    required void Function(String? endpointId) onEndpointLost,
  });

  /// Pauses or stops scanning.
  Future<void> stopDiscovery();

  /// Stops advertising presence.
  Future<void> stopAdvertising();

  /// Disconnects from all active endpoints.
  Future<void> stopAllEndpoints();

  /// Requests a connection to a discovered peer endpoint.
  Future<bool> requestConnection({
    required String localDeviceId,
    required String endpointId,
    required void Function(String endpointId, dynamic info) onConnectionInitiated,
    required void Function(String endpointId, dynamic status) onConnectionResult,
    required void Function(String endpointId) onDisconnected,
  });

  /// Accepts an incoming connection request from a peer endpoint.
  Future<bool> acceptConnection({
    required String endpointId,
    required void Function(String endpointId, dynamic payload) onPayloadReceived,
  });

  /// Sends a raw bytes payload to a connected peer endpoint.
  Future<void> sendBytesPayload(String endpointId, Uint8List bytes);
}
