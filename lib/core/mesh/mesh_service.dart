import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/message_model.dart';

enum MeshStatus {
  idle,
  searching,
  connected,
}

class MeshService extends ChangeNotifier {
  static final MeshService instance = MeshService._init();

  MeshService._init();

  static const String _serviceId = 'com.crisismesh.mesh';
  static const int maxHops = 7;
  final Strategy _strategy = Strategy.P2P_CLUSTER;

  String _localDeviceId = 'unknown';
  MeshStatus _status = MeshStatus.idle;
  final Set<String> _connectedEndpoints = {};
  Future<void> Function(MessageModel message, String sourceEndpointId)? _onMessageReceived;

  MeshStatus get status => _status;
  int get connectedPeerCount => _connectedEndpoints.length;
  bool get isConnected => _connectedEndpoints.isNotEmpty;
  Set<String> get connectedEndpoints => Set.unmodifiable(_connectedEndpoints);

  /// Initializes the service with a local device ID and a message callback.
  void init({
    required String localDeviceId,
    required Future<void> Function(MessageModel message, String sourceEndpointId) onMessageReceived,
  }) {
    _localDeviceId = localDeviceId;
    _onMessageReceived = onMessageReceived;
  }

  /// Verifies and requests runtime permissions required for Nearby Connections.
  Future<bool> checkAndRequestPermissions() async {
    try {
      final permissions = [
        Permission.location,
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.nearbyWifiDevices,
      ];

      final statuses = await permissions.request();

      final locationGranted = statuses[Permission.location]?.isGranted ?? false;
      final btScanGranted = statuses[Permission.bluetoothScan]?.isGranted ?? true;
      final btAdvGranted = statuses[Permission.bluetoothAdvertise]?.isGranted ?? true;
      final btConnGranted = statuses[Permission.bluetoothConnect]?.isGranted ?? true;

      return locationGranted && btScanGranted && btAdvGranted && btConnGranted;
    } catch (e) {
      debugPrint('[MeshService] Error requesting permissions: $e');
      return false;
    }
  }

  /// Starts both advertising and discovery (symmetric P2P_CLUSTER).
  Future<bool> startMesh() async {
    final granted = await checkAndRequestPermissions();
    if (!granted) {
      debugPrint('[MeshService] Permissions not granted. Cannot start mesh.');
      return false;
    }

    _status = MeshStatus.searching;
    notifyListeners();

    final adv = await _startAdvertising();
    final disc = await _startDiscovery();

    return adv || disc;
  }

  Future<bool> _startAdvertising() async {
    try {
      return await Nearby().startAdvertising(
        _localDeviceId,
        _strategy,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: _serviceId,
      );
    } catch (e) {
      debugPrint('[MeshService] startAdvertising failed: $e');
      return false;
    }
  }

  Future<bool> _startDiscovery() async {
    try {
      return await Nearby().startDiscovery(
        _localDeviceId,
        _strategy,
        onEndpointFound: _onEndpointFound,
        onEndpointLost: _onEndpointLost,
        serviceId: _serviceId,
      );
    } catch (e) {
      debugPrint('[MeshService] startDiscovery failed: $e');
      return false;
    }
  }

  void _onEndpointFound(String endpointId, String endpointName, String serviceId) {
    debugPrint('[MeshService] Found peer: $endpointId ($endpointName)');
    if (_connectedEndpoints.contains(endpointId)) return;

    // Automatic handshake initiation
    Nearby().requestConnection(
      _localDeviceId,
      endpointId,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
    ).then((success) {
      debugPrint('[MeshService] requestConnection result: $success');
    }).catchError((e) {
      debugPrint('[MeshService] requestConnection error: $e');
    });
  }

  void _onEndpointLost(String? endpointId) {
    debugPrint('[MeshService] Lost peer: $endpointId');
  }

  void _onConnectionInitiated(String endpointId, ConnectionInfo info) {
    debugPrint('[MeshService] Connection initiated with $endpointId (${info.endpointName}). Auto-accepting.');
    Nearby().acceptConnection(
      endpointId,
      onPayLoadRecieved: (endId, payload) {
        _onPayloadReceived(endId, payload);
      },
    );
  }

  void _onConnectionResult(String endpointId, Status status) {
    if (status == Status.CONNECTED) {
      debugPrint('[MeshService] Connected to peer: $endpointId');
      _connectedEndpoints.add(endpointId);
      _status = MeshStatus.connected;
      notifyListeners();
    } else {
      debugPrint('[MeshService] Connection to $endpointId failed with status: $status');
      _connectedEndpoints.remove(endpointId);
      if (_connectedEndpoints.isEmpty) {
        _status = MeshStatus.searching;
      }
      notifyListeners();
    }
  }

  void _onDisconnected(String endpointId) {
    debugPrint('[MeshService] Peer disconnected: $endpointId');
    _connectedEndpoints.remove(endpointId);
    if (_connectedEndpoints.isEmpty) {
      _status = MeshStatus.searching;
      // Re-trigger discovery and advertising to reconnect when back in range
      startMesh();
    } else {
      notifyListeners();
    }
  }

  void _onPayloadReceived(String endpointId, Payload payload) {
    if (payload.type != PayloadType.BYTES || payload.bytes == null) {
      debugPrint('[MeshService] Ignoring unsupported payload from $endpointId');
      return;
    }

    try {
      final jsonStr = utf8.decode(payload.bytes!);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final message = MessageModel.fromMap(map);

      debugPrint('[MeshService] Valid SOS payload received: ${message.id} from $endpointId (hop: ${message.hopCount})');
      _onMessageReceived?.call(message, endpointId);
    } catch (e) {
      debugPrint('[MeshService] Error parsing incoming payload: $e');
    }
  }

  /// Broadcasts an SOS message to connected peers, optionally excluding the source endpoint.
  Future<int> broadcastMessage(MessageModel message, {String? excludeEndpointId}) async {
    if (_connectedEndpoints.isEmpty) {
      debugPrint('[MeshService] No connected peers to broadcast to.');
      return 0;
    }

    try {
      final jsonStr = jsonEncode(message.toMap());
      final bytes = Uint8List.fromList(utf8.encode(jsonStr));
      int sentCount = 0;

      for (final endpointId in _connectedEndpoints) {
        if (excludeEndpointId != null && endpointId == excludeEndpointId) {
          debugPrint('[MeshService] Skipping echo back to source endpoint: $endpointId');
          continue;
        }
        await Nearby().sendBytesPayload(endpointId, bytes);
        sentCount++;
        debugPrint('[MeshService] Sent SOS ${message.id} (hop: ${message.hopCount}) to $endpointId');
      }

      return sentCount;
    } catch (e) {
      debugPrint('[MeshService] Error broadcasting message: $e');
      return 0;
    }
  }

  /// Clean shutdown of mesh operations.
  Future<void> stopMesh() async {
    try {
      await Nearby().stopAdvertising();
      await Nearby().stopDiscovery();
      await Nearby().stopAllEndpoints();
      _connectedEndpoints.clear();
      _status = MeshStatus.idle;
      notifyListeners();
    } catch (e) {
      debugPrint('[MeshService] Error stopping mesh: $e');
    }
  }
}
