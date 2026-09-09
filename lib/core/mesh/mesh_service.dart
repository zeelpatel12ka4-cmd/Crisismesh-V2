import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../battery/battery_duty_cycle_manager.dart';
import '../database/database_service.dart';
import '../models/message_model.dart';
import '../models/contact_model.dart';
import '../models/private_message_model.dart';
import '../crypto/crypto_service.dart';
import 'transport/mesh_transport.dart';
import 'transport/mesh_transport_factory.dart';

// Conditional import: Status is only available on non-web (nearby_connections package).
// On Web, this import resolves to a stub so the code compiles safely.
import 'nearby_status_stub.dart'
    if (dart.library.io) 'nearby_status_io.dart';

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

  MeshTransport _transport = createDefaultMeshTransport();

  /// Allows test injection of mock or custom mesh transport
  @visibleForTesting
  void setTransportForTest(MeshTransport transport) {
    _transport = transport;
  }

  String? _persistentDeviceId;
  bool _isMeshActive = false;
  final Set<String> _connectedEndpoints = {};
  final Set<String> _connectingEndpoints = {};

  Future<void> Function(MessageModel message, String sourceEndpointId)? _onMessageReceived;
  Future<void> Function(String endpointId)? _onPeerConnected;
  Future<int> Function()? _pendingMessageFlusher;
  Future<void> Function(PrivateMessageEnvelope envelope, String? plaintext)? _onPrivateMessageReceived;
  Future<void> Function(PrivateAckEnvelope ack)? _onAckReceived;

  void setPrivateMessageCallback(Future<void> Function(PrivateMessageEnvelope envelope, String? plaintext) callback) {
    _onPrivateMessageReceived = callback;
  }

  void setAckCallback(Future<void> Function(PrivateAckEnvelope ack) callback) {
    _onAckReceived = callback;
  }

  /// Stable device ID persistent for the process/session lifetime.
  /// Harmonized with CryptoService.derivedDeviceId when cryptographic identity is initialized.
  String get localDeviceId {
    if (_persistentDeviceId != null && _persistentDeviceId!.isNotEmpty) {
      return _persistentDeviceId!;
    }
    if (CryptoService.instance.isInitialized) {
      _persistentDeviceId = CryptoService.instance.derivedDeviceId;
      return _persistentDeviceId!;
    }
    _persistentDeviceId = 'DEV-${const Uuid().v4().substring(0, 8)}';
    return _persistentDeviceId!;
  }

  /// Explicitly sets or updates the local device ID.
  void setLocalDeviceId(String deviceId) {
    if (deviceId.isNotEmpty) {
      _persistentDeviceId = deviceId;
    }
  }

  /// Authoritative derived MeshStatus from single source of truth (_connectedEndpoints and _isMeshActive)
  MeshStatus get status {
    if (!_isMeshActive) return MeshStatus.idle;
    if (_connectedEndpoints.isNotEmpty) return MeshStatus.connected;
    return MeshStatus.searching;
  }

  bool get isMeshActive => _isMeshActive;
  int get connectedPeerCount => _connectedEndpoints.length;
  bool get isConnected => _connectedEndpoints.isNotEmpty;
  Set<String> get connectedEndpoints => Set.unmodifiable(_connectedEndpoints);
  Set<String> get connectingEndpoints => Set.unmodifiable(_connectingEndpoints);

  /// Initializes the service with a local device ID, message callback, and optional peer connection callbacks.
  void init({
    String? localDeviceId,
    required Future<void> Function(MessageModel message, String sourceEndpointId) onMessageReceived,
    Future<void> Function(String endpointId)? onPeerConnected,
    Future<int> Function()? pendingMessageFlusher,
  }) {
    if (localDeviceId != null && localDeviceId.isNotEmpty) {
      _persistentDeviceId = localDeviceId;
    } else if (CryptoService.instance.isInitialized) {
      _persistentDeviceId = CryptoService.instance.derivedDeviceId;
    }
    _onMessageReceived = onMessageReceived;
    _onPeerConnected = onPeerConnected;
    _pendingMessageFlusher = pendingMessageFlusher;
  }

  /// Verifies and requests runtime permissions required for local mesh radio & background operation.
  Future<bool> checkAndRequestPermissions() async {
    return await _transport.checkAndRequestPermissions();
  }

  /// Starts both advertising and discovery (symmetric P2P_CLUSTER) with adaptive battery duty cycling.
  Future<bool> startMesh() async {
    if (_isMeshActive) {
      debugPrint('[Mesh] Mesh already active.');
      return true;
    }

    final granted = await checkAndRequestPermissions();
    if (!granted) {
      debugPrint('[Mesh] Permissions not granted. Cannot start mesh.');
      _isMeshActive = false;
      notifyListeners();
      return false;
    }

    // Phase 5B: Activate native Android Foreground Service while app is visible
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _backgroundChannel.invokeMethod('startForegroundService');
        final isRunning = await isNativeBackgroundServiceRunning();
        debugPrint('[Mesh] Native Android foreground service started: $isRunning');
      } catch (e) {
        debugPrint('[Mesh] Notice: Could not start native background service: $e');
      }
    }

    _isMeshActive = true;
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
    return await _transport.startAdvertising(
      localDeviceId: localDeviceId,
      serviceId: _serviceId,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
    );
  }

  Future<bool> _startDiscovery() async {
    return await _transport.startDiscovery(
      localDeviceId: localDeviceId,
      serviceId: _serviceId,
      onEndpointFound: _onEndpointFound,
      onEndpointLost: _onEndpointLost,
    );
  }

  Future<void> _stopDiscovery() async {
    await _transport.stopDiscovery();
  }

  void _onEndpointFound(String endpointId, String endpointName, String serviceId) {
    debugPrint('[Mesh:$localDeviceId] endpointFound: $endpointId / $endpointName');

    // Self-discovery ignore
    if (endpointName == localDeviceId) {
      debugPrint('[Mesh:$localDeviceId] Ignoring self-discovery echo: $endpointName');
      return;
    }

    // Handshake deduplication & in-flight tracking
    if (_connectedEndpoints.contains(endpointId)) {
      debugPrint('[Mesh:$localDeviceId] Peer $endpointId is already connected. Ignoring.');
      return;
    }
    if (_connectingEndpoints.contains(endpointId)) {
      debugPrint('[Mesh:$localDeviceId] Connection to $endpointId is already in progress. Ignoring duplicate.');
      return;
    }

    // Phase 6 Deterministic Tie-Breaker:
    // Only the device with the lexicographically smaller device ID initiates the connection request.
    // The device with the larger ID remains as advertiser and waits for the incoming connection.
    if (localDeviceId.compareTo(endpointName) > 0) {
      debugPrint('[Mesh:$localDeviceId] tie-breaker: waiting for peer $endpointId ($endpointName) to initiate');
      return;
    }

    debugPrint('[Mesh:$localDeviceId] tie-breaker: initiating connection to $endpointId ($endpointName)');
    _connectingEndpoints.add(endpointId);

    _transport.requestConnection(
      localDeviceId: localDeviceId,
      endpointId: endpointId,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
    ).then((success) {
      debugPrint('[Mesh:$localDeviceId] requestConnection result: $success for $endpointId');
      if (!success) {
        _connectingEndpoints.remove(endpointId);
      }
    }).catchError((e) {
      debugPrint('[Mesh:$localDeviceId] requestConnection error: $e for $endpointId');
      _connectingEndpoints.remove(endpointId);
    });
  }

  void _onEndpointLost(String? endpointId) {
    debugPrint('[Mesh:$localDeviceId] Lost peer: $endpointId');
  }

  void _onConnectionInitiated(String endpointId, dynamic info) {
    // ConnectionInfo is nearby_connections-specific (Android only).
    // Use a safe dynamic accessor: try the known field name, fall back to toString().
    String name;
    try {
      // On Android with real ConnectionInfo, this will work via dynamic dispatch.
      name = (info as dynamic).endpointName as String? ?? info?.toString() ?? 'peer';
    } catch (_) {
      name = info?.toString() ?? 'peer';
    }
    debugPrint('[Mesh:$localDeviceId] connection initiated with $endpointId ($name). Auto-accepting.');
    _connectingEndpoints.add(endpointId);
    _transport.acceptConnection(
      endpointId: endpointId,
      onPayloadReceived: (endId, payload) {
        _onPayloadReceived(endId, payload);
      },
    );
  }

  // Accept `dynamic` to match MeshTransport interface (nearby_connections Status is
  // Android-only; on Web this callback is never fired, but must compile).
  void _onConnectionResult(String endpointId, dynamic status) {
    _connectingEndpoints.remove(endpointId);

    // Use NearbyStatusHelper (resolves to real Status on Android, stub on Web)
    // so this check is safe on all platforms.
    final connected = NearbyStatusHelper.isConnected(status);

    if (connected) {
      debugPrint('[Mesh] connection succeeded: $endpointId');
      final isNew = _connectedEndpoints.add(endpointId);
      debugPrint('[Mesh] connectedPeerCount=${_connectedEndpoints.length}');
      if (isNew) {
        notifyListeners();
      }

      // Phase 5A: Notify peer connected listener and flush pending store-and-forward SOS messages
      _onPeerConnected?.call(endpointId);
      flushPendingMessages();
    } else {
      debugPrint('[Mesh] connection failed to $endpointId with status: $status');
      // Critical Phase 6 rule:
      // If endpointId is ALREADY in _connectedEndpoints, a failed duplicate request
      // must NOT remove it. Only an actual disconnect callback removes connected endpoints.
      debugPrint('[Mesh] connectedPeerCount=${_connectedEndpoints.length}');
    }
  }

  void _onDisconnected(String endpointId) {
    debugPrint('[Mesh] endpoint disconnected: $endpointId');
    _connectingEndpoints.remove(endpointId);
    final wasRemoved = _connectedEndpoints.remove(endpointId);
    debugPrint('[Mesh] connectedPeerCount=${_connectedEndpoints.length}');

    if (wasRemoved) {
      notifyListeners();
    }
  }

  @visibleForTesting
  void onEndpointFoundForTest(String endpointId, String endpointName, String serviceId) =>
      _onEndpointFound(endpointId, endpointName, serviceId);

  @visibleForTesting
  void onConnectionResultForTest(String endpointId, dynamic status) =>
      _onConnectionResult(endpointId, status);

  @visibleForTesting
  void onDisconnectedForTest(String endpointId) =>
      _onDisconnected(endpointId);

  @visibleForTesting
  void onPayloadReceivedForTest(String endpointId, dynamic payload) =>
      _onPayloadReceived(endpointId, payload);

  void _onPayloadReceived(String endpointId, dynamic payload) async {
    // Payload is a nearby_connections Android type. Access via dynamic dispatch.
    // On Web this callback is never invoked (WebMeshTransport is a no-op).
    final dynamic payloadType = NearbyPayloadHelper.getType(payload);
    final bool isBytes = NearbyPayloadHelper.isBytes(payloadType);
    final List<int>? bytes = NearbyPayloadHelper.getBytes(payload);

    if (!isBytes || bytes == null) {
      debugPrint('[MeshService] Ignoring unsupported payload from $endpointId');
      return;
    }

    try {
      final jsonStr = utf8.decode(bytes);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final type = map['type'] as String?;

      if (type == 'private_chat') {
        final envelope = PrivateMessageEnvelope.fromMap(map);
        await _handleIncomingPrivateEnvelope(envelope, endpointId);
      } else if (type == 'private_ack') {
        final ack = PrivateAckEnvelope.fromMap(map);
        await _handleIncomingPrivateAck(ack, endpointId);
      } else {
        final message = MessageModel.fromMap(map);
        debugPrint('[MeshService] Valid SOS payload received: ${message.id} from $endpointId (hop: ${message.hopCount})');
        _onMessageReceived?.call(message, endpointId);
      }
    } catch (e) {
      debugPrint('[MeshService] Error parsing incoming payload: $e');
    }
  }

  /// Handles incoming private 1-to-1 encrypted message envelopes
  Future<void> _handleIncomingPrivateEnvelope(
    PrivateMessageEnvelope envelope,
    String sourceEndpointId,
  ) async {
    // 1. Replay & deduplication check
    final alreadySeen = await DatabaseService.instance.hasSeenPrivateMessageId(envelope.messageId);
    if (alreadySeen) {
      debugPrint('[MeshService] Private message ${envelope.messageId} already recorded. Dropping duplicate.');
      return;
    }

    // 2. Expiry check (7 days policy)
    final msgTime = DateTime.fromMillisecondsSinceEpoch(envelope.timestamp);
    if (DateTime.now().difference(msgTime) > CryptoService.privateMessageExpiryHorizon) {
      debugPrint('[MeshService] Private message ${envelope.messageId} is expired (>7 days). Dropping.');
      return;
    }

    // 3. Check if this device is the intended recipient
    final isForThisDevice = envelope.recipientDeviceId == localDeviceId ||
        (CryptoService.instance.isInitialized && envelope.recipientDeviceId == CryptoService.instance.derivedDeviceId);

    if (isForThisDevice) {
      debugPrint('[MeshService] Private message ${envelope.messageId} addressed to local device.');

      // Verify Ed25519 signature
      final validSig = await CryptoService.instance.verifyPrivateEnvelopeSignature(envelope);
      if (!validSig) {
        debugPrint('[MeshService] Invalid signature on private message ${envelope.messageId}. Dropping.');
        return;
      }

      // Check contact and detect key changes
      final contact = await DatabaseService.instance.getContact(envelope.senderDeviceId);
      if (contact != null) {
        if (contact.signingPublicKey != envelope.senderEd25519Pub ||
            contact.encryptionPublicKey != envelope.senderX25519Pub) {
          debugPrint('[MeshService] SECURITY ALERT: Key mismatch detected for ${envelope.senderDeviceId}!');
          await DatabaseService.instance.updateContactTrustStatus(
            envelope.senderDeviceId,
            ContactTrustStatus.keyChanged,
          );
        }
      }

      // Decrypt locally
      String? plaintext;
      try {
        plaintext = await CryptoService.instance.decryptPrivateMessage(envelope: envelope);
      } catch (e) {
        debugPrint('[MeshService] Decryption failed for private message ${envelope.messageId}: $e');
        return;
      }

      // Store in SQLite
      final model = PrivateMessageModel(
        messageId: envelope.messageId,
        conversationId: envelope.conversationId,
        senderDeviceId: envelope.senderDeviceId,
        recipientDeviceId: envelope.recipientDeviceId,
        plaintextBody: plaintext,
        ciphertext: envelope.ciphertext,
        nonce: envelope.nonce,
        authTag: envelope.authTag,
        senderX25519Pub: envelope.senderX25519Pub,
        senderEd25519Pub: envelope.senderEd25519Pub,
        signature: envelope.signature,
        status: PrivateMessageStatus.received,
        timestamp: envelope.timestamp,
        expiresAt: envelope.timestamp + CryptoService.privateMessageExpiryHorizon.inMilliseconds,
        isOutgoing: false,
        acknowledged: false,
      );
      await DatabaseService.instance.savePrivateMessage(model);

      // Send delivery ACK back to sender
      try {
        final ack = await CryptoService.instance.signAck(
          ackMessageId: envelope.messageId,
          originalSenderDeviceId: envelope.senderDeviceId,
        );
        await broadcastAck(ack);
      } catch (e) {
        debugPrint('[MeshService] Could not send delivery ACK: $e');
      }

      // Trigger UI callback
      _onPrivateMessageReceived?.call(envelope, plaintext);
    } else {
      // Intermediate Relay Node: Forward without decryption
      if (envelope.hopCount < maxHops) {
        envelope.hopCount += 1;
        debugPrint('[MeshService] Relaying private message ${envelope.messageId} (hop ${envelope.hopCount}) for ${envelope.recipientDeviceId}');
        await broadcastPrivateEnvelope(envelope, excludeEndpointId: sourceEndpointId);
      } else {
        debugPrint('[MeshService] Private message ${envelope.messageId} exceeded max hops ($maxHops). Dropping.');
      }
    }
  }

  /// Handles incoming delivery acknowledgment envelopes
  Future<void> _handleIncomingPrivateAck(
    PrivateAckEnvelope ack,
    String sourceEndpointId,
  ) async {
    final isForThisDevice = ack.recipientDeviceId == localDeviceId ||
        (CryptoService.instance.isInitialized && ack.recipientDeviceId == CryptoService.instance.derivedDeviceId);

    if (isForThisDevice) {
      debugPrint('[MeshService] Delivery ACK received for message: ${ack.ackMessageId}');
      await DatabaseService.instance.markPrivateMessageDelivered(ack.ackMessageId);
      _onAckReceived?.call(ack);
    } else {
      // Relay ACK along connected peers
      debugPrint('[MeshService] Relaying delivery ACK for ${ack.ackMessageId}');
      await broadcastAck(ack, excludeEndpointId: sourceEndpointId);
    }
  }

  /// Broadcasts a private encrypted message envelope to connected peers
  Future<int> broadcastPrivateEnvelope(
    PrivateMessageEnvelope envelope, {
    String? excludeEndpointId,
  }) async {
    if (_connectedEndpoints.isEmpty) {
      debugPrint('[MeshService] No connected peers to broadcast private message to.');
      return 0;
    }

    try {
      final jsonStr = envelope.toJson();
      final bytes = Uint8List.fromList(utf8.encode(jsonStr));
      int sentCount = 0;

      for (final endpointId in _connectedEndpoints) {
        if (excludeEndpointId != null && endpointId == excludeEndpointId) {
          continue;
        }
        await _transport.sendBytesPayload(endpointId, bytes);
        sentCount++;
      }

      debugPrint('[MeshService] Broadcasted private message ${envelope.messageId} to $sentCount peer(s).');
      return sentCount;
    } catch (e) {
      debugPrint('[MeshService] Error broadcasting private envelope: $e');
      return 0;
    }
  }

  /// Broadcasts a delivery acknowledgment envelope to connected peers
  Future<int> broadcastAck(
    PrivateAckEnvelope ack, {
    String? excludeEndpointId,
  }) async {
    if (_connectedEndpoints.isEmpty) return 0;

    try {
      final jsonStr = ack.toJson();
      final bytes = Uint8List.fromList(utf8.encode(jsonStr));
      int sentCount = 0;

      for (final endpointId in _connectedEndpoints) {
        if (excludeEndpointId != null && endpointId == excludeEndpointId) {
          continue;
        }
        await _transport.sendBytesPayload(endpointId, bytes);
        sentCount++;
      }

      return sentCount;
    } catch (e) {
      debugPrint('[MeshService] Error broadcasting ACK: $e');
      return 0;
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
        await _transport.sendBytesPayload(endpointId, bytes);
        sentCount++;
        debugPrint('[MeshService] Sent SOS ${message.id} (hop: ${message.hopCount}) to $endpointId');
      }

      return sentCount;
    } catch (e) {
      debugPrint('[MeshService] Error broadcasting message: $e');
      return 0;
    }
  }

  /// Flushes pending outgoing private messages when a peer connects
  Future<int> flushPendingPrivateMessages() async {
    if (_connectedEndpoints.isEmpty) return 0;

    try {
      final pending = await DatabaseService.instance.getPendingPrivateMessages();
      if (pending.isEmpty) return 0;

      debugPrint('[MeshService] Flushing ${pending.length} pending private message(s)...');
      int transmittedCount = 0;

      for (final msg in pending) {
        final envelope = msg.toEnvelope();
        final sent = await broadcastPrivateEnvelope(envelope);
        if (sent > 0) {
          await DatabaseService.instance.updatePrivateMessageStatus(msg.messageId, PrivateMessageStatus.sent);
          transmittedCount++;
        }
      }

      return transmittedCount;
    } catch (e) {
      debugPrint('[MeshService] Error flushing pending private messages: $e');
      return 0;
    }
  }

  /// Automatically flushes pending offline SOS and private messages when a peer connects (Store-and-Forward)
  Future<int> flushPendingMessages() async {
    if (_connectedEndpoints.isEmpty) {
      debugPrint('[MeshService] No connected peers to flush pending messages to.');
      return 0;
    }

    try {
      if (_pendingMessageFlusher != null) {
        return await _pendingMessageFlusher!.call();
      }

      // Flush private messages
      await flushPendingPrivateMessages();

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
    if (!_isMeshActive && _connectedEndpoints.isEmpty) {
      debugPrint('[Mesh] Mesh already stopped.');
      return;
    }

    // Phase 5B.2: Stop battery duty-cycle scheduler
    BatteryDutyCycleManager.instance.stopScheduler();

    try {
      await _transport.stopAdvertising();
      await _transport.stopDiscovery();
      await _transport.stopAllEndpoints();
      _connectedEndpoints.clear();
      _connectingEndpoints.clear();
      _isMeshActive = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[Mesh] Error stopping transport: $e');
      _connectedEndpoints.clear();
      _connectingEndpoints.clear();
      _isMeshActive = false;
      notifyListeners();
    }

    // Phase 5B: Stop native Android Foreground Service
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _backgroundChannel.invokeMethod('stopForegroundService');
        debugPrint('[Mesh] Native Android foreground service stopped.');
      } catch (e) {
        debugPrint('[Mesh] Notice: Could not stop native background service: $e');
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
