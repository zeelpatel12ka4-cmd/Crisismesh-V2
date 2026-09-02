import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import '../battery/battery_duty_cycle_manager.dart';
import '../database/database_service.dart';
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
  static const MethodChannel _backgroundChannel = MethodChannel('com.crisismesh.app/background_service');
  final Strategy _strategy = Strategy.P2P_CLUSTER;

  String _localDeviceId = 'unknown';
  MeshStatus _status = MeshStatus.idle;
  final Set<String> _connectedEndpoints = {};
  Future<void> Function(MessageModel message, String sourceEndpointId)? _onMessageReceived;
  Future<void> Function(String endpointId)? _onPeerConnected;
  Future<int> Function()? _pendingMessageFlusher;

  MeshStatus get status => _status;
  int get connectedPeerCount => _connectedEndpoints.length;
  bool get isConnected => _connectedEndpoints.isNotEmpty;
  Set<String> get connectedEndpoints => Set.unmodifiable(_connectedEndpoints);

  /// Initializes the service with a local device ID, message callback, and optional peer connection callbacks.
  void init({
    required String localDeviceId,
    required Future<void> Function(MessageModel message, String sourceEndpointId) onMessageReceived,
    Future<void> Function(String endpointId)? onPeerConnected,
    Future<int> Function()? pendingMessageFlusher,
  }) {
    _localDeviceId = localDeviceId;
    _onMessageReceived = onMessageReceived;
    _onPeerConnected = onPeerConnected;
    _pendingMessageFlusher = pendingMessageFlusher;
  }

  /// Verifies and requests runtime permissions required for Nearby Connections & Background Service.
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
        debugPrint('[MeshService] Permissions incomplete: location=$locationGranted, btScan=$btScanGranted, btAdv=$btAdvGranted, btConn=$btConnGranted');
      }
      return isGranted;
    } catch (e) {
      debugPrint('[MeshService] Error requesting permissions: $e');
      return false;
    }
  }

  /// Starts both advertising and discovery (symmetric P2P_CLUSTER) with adaptive battery duty cycling.
  Future<bool> startMesh() async {
    if (_status == MeshStatus.searching || _status == MeshStatus.connected) {
      debugPrint('[MeshService] Mesh already active.');
      return true;
    }

    final granted = await checkAndRequestPermissions();
    if (!granted) {
      debugPrint('[MeshService] Permissions not granted. Cannot start mesh.');
      _status = MeshStatus.idle;
      notifyListeners();
      return false;
    }

    // Phase 5B: Activate native Android Foreground Service while app is visible
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _backgroundChannel.invokeMethod('startForegroundService');
        final isRunning = await isNativeBackgroundServiceRunning();
        debugPrint('[MeshService] Native Android foreground service started: $isRunning');
      } catch (e) {
        debugPrint('[MeshService] Notice: Could not start native background service: $e');
      }
    }

    _status = MeshStatus.searching;
    notifyListeners();

    final adv = await _startAdvertising();
    final disc = await _startDiscovery();

    // Phase 5B.2: Activate Adaptive Battery Duty-Cycling scheduler for discovery
    BatteryDutyCycleManager.instance.startScheduler(
      onScanStart: _startDiscovery,
      onScanStop: _stopDiscovery,
      isConnected: () => isConnected,
    );

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

  Future<void> _stopDiscovery() async {
    try {
      await Nearby().stopDiscovery();
      debugPrint('[MeshService] Discovery paused for battery duty-cycle sleep.');
    } catch (e) {
      debugPrint('[MeshService] stopDiscovery failed: $e');
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

      // Phase 5A: Notify peer connected listener and flush pending store-and-forward SOS messages
      _onPeerConnected?.call(endpointId);
      flushPendingMessages();
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

  /// Automatically flushes pending offline SOS messages when a peer connects (Phase 5A Store-and-Forward)
  Future<int> flushPendingMessages() async {
    if (_connectedEndpoints.isEmpty) {
      debugPrint('[MeshService] No connected peers to flush pending messages to.');
      return 0;
    }

    try {
      if (_pendingMessageFlusher != null) {
        return await _pendingMessageFlusher!.call();
      }

      final pending = await DatabaseService.instance.getPendingMeshMessages();
      if (pending.isEmpty) {
        debugPrint('[MeshService] No pending mesh messages to flush.');
        return 0;
      }

      debugPrint('[MeshService] Flushing ${pending.length} pending mesh message(s)...');
      int transmittedCount = 0;

      for (final msg in pending) {
        // Mark as SENDING to prevent race conditions during retry
        await DatabaseService.instance.updateMeshDeliveryStatus(msg.id, MeshDeliveryStatus.sending);
        final sentCount = await broadcastMessage(msg);
        if (sentCount > 0) {
          await DatabaseService.instance.markMessageMeshTransmitted(msg.id);
          transmittedCount++;
          debugPrint('[MeshService] Pending SOS ${msg.id} successfully transmitted to $sentCount peer(s).');
        } else {
          // Revert back to PENDING on failure
          await DatabaseService.instance.updateMeshDeliveryStatus(msg.id, MeshDeliveryStatus.pending);
          debugPrint('[MeshService] Pending SOS ${msg.id} failed transmission; returned to pending.');
        }
      }

      // Phase 5B.2: Notify battery duty-cycle manager of pending queue state update
      final remaining = await DatabaseService.instance.getPendingMeshMessages();
      BatteryDutyCycleManager.instance.notifyPendingCountChanged(remaining.length);

      return transmittedCount;
    } catch (e) {
      debugPrint('[MeshService] Error flushing pending messages: $e');
      return 0;
    }
  }

  /// Clean shutdown of mesh operations and Android Foreground Service.
  Future<void> stopMesh() async {
    if (_status == MeshStatus.idle && _connectedEndpoints.isEmpty) {
      debugPrint('[MeshService] Mesh already stopped.');
      return;
    }

    // Phase 5B.2: Stop battery duty-cycle scheduler
    BatteryDutyCycleManager.instance.stopScheduler();

    try {
      await Nearby().stopAdvertising();
      await Nearby().stopDiscovery();
      await Nearby().stopAllEndpoints();
      _connectedEndpoints.clear();
      _status = MeshStatus.idle;
      notifyListeners();
    } catch (e) {
      debugPrint('[MeshService] Error stopping Nearby: $e');
    }

    // Phase 5B: Stop native Android Foreground Service
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _backgroundChannel.invokeMethod('stopForegroundService');
        debugPrint('[MeshService] Native Android foreground service stopped.');
      } catch (e) {
        debugPrint('[MeshService] Notice: Could not stop native background service: $e');
      }
    }
  }

  /// Checks if the native Android Foreground Service is currently running.
  Future<bool> isNativeBackgroundServiceRunning() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final result = await _backgroundChannel.invokeMethod<bool>('isForegroundServiceRunning');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }
}
