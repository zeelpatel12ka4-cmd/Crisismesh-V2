import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import '../core/battery/battery_duty_cycle_manager.dart';
import '../core/database/database_service.dart';
import '../core/mesh/mesh_service.dart';
import '../core/models/message_model.dart';
import '../core/sync/sync_service.dart';
import '../core/triage/severity_engine.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  final _uuid = const Uuid();
  final _descriptionController = TextEditingController();
  final String _deviceId = 'DEV-${const Uuid().v4().substring(0, 8)}';

  String _selectedCategory = 'medical';
  double? _latitude;
  double? _longitude;
  bool _isFetchingLocation = false;
  bool _useDemoLocation = false;

  // Real-time triage status
  int _currentScore = 1;
  String _currentTier = 'Low';
  List<String> _matchedKeywords = [];
  String _explanation = 'No critical keywords matched -> LOW/UNCLASSIFIED';

  // Persistence list
  List<MessageModel> _messageHistory = [];

  // Dropdown categories as per specification
  final List<String> _categories = [
    'medical',
    'trapped',
    'fire',
    'water',
    'food',
    'shelter',
  ];

  @override
  void initState() {
    super.initState();
    _loadMessageHistory();
    _descriptionController.addListener(_onDescriptionChanged);
    _fetchLocation();

    if (!kIsWeb) {
      // Initialize MeshService for Phase 2, 5A & 5B background mesh
      MeshService.instance.init(
        localDeviceId: _deviceId,
        onMessageReceived: _handleIncomingMeshMessage,
        onPeerConnected: (endpointId) async {
          if (mounted) {
            await _loadMessageHistory();
          }
        },
      );
      MeshService.instance.addListener(_onMeshStatusChanged);
      _initAndSyncMesh();

      // Initialize SyncService for Phase 3 Cloud Bridge Synchronization
      SyncService.instance.init(localDeviceId: _deviceId);
      SyncService.instance.addListener(_onSyncStatusChanged);
    }
  }

  /// Synchronizes UI with native foreground service state and starts mesh if already active
  Future<void> _initAndSyncMesh() async {
    final isServiceRunning = await MeshService.instance.isNativeBackgroundServiceRunning();
    if (isServiceRunning || MeshService.instance.status == MeshStatus.idle) {
      await MeshService.instance.startMesh();
    }
  }

  /// Explicit user activation action for Emergency Mesh with clear permission error feedback
  Future<void> _enableEmergencyMesh() async {
    final success = await MeshService.instance.startMesh();
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Emergency Mesh requires Nearby and Location permissions to discover peers in the background.',
          ),
          action: SnackBarAction(
            label: 'RETRY',
            onPressed: _enableEmergencyMesh,
          ),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    _fetchLocation();
  }

  @override
  void dispose() {
    SyncService.instance.removeListener(_onSyncStatusChanged);
    MeshService.instance.removeListener(_onMeshStatusChanged);
    _descriptionController.dispose();
    super.dispose();
  }

  void _onMeshStatusChanged() {
    if (mounted) {
      _loadMessageHistory();
      setState(() {});
    }
  }

  void _onSyncStatusChanged() {
    if (mounted) {
      _loadMessageHistory();
      setState(() {});
    }
  }

  /// Phase 2B multi-hop incoming SOS handler: deduplication, hop count increment, SQLite save, and auto-forwarding.
  Future<void> _handleIncomingMeshMessage(MessageModel incomingMessage, String sourceEndpointId) async {
    // 1. Authoritative Deduplication & Loop Prevention: check seen_message_ids
    final alreadySeen = await DatabaseService.instance.hasSeenMessageId(incomingMessage.id);
    if (alreadySeen) {
      debugPrint('[SosScreen] Authoritative drop: Message ${incomingMessage.id} already processed (loop/duplicate prevention).');
      return;
    }

    // 2. Mark as seen immediately in SQLite
    await DatabaseService.instance.saveSeenMessageId(incomingMessage.id);

    // 3. Increment hop count
    final relayedMessage = incomingMessage.copyWith(
      hopCount: incomingMessage.hopCount + 1,
    );

    // 4. Save to local SQLite database
    await DatabaseService.instance.saveMessage(relayedMessage);

    // 5. Refresh local UI history
    await _loadMessageHistory();

    // 6. Multi-Hop Forwarding check: forward if hopCount < 7, excluding the source endpoint
    int forwardedPeers = 0;
    if (relayedMessage.hopCount < MeshService.maxHops) {
      debugPrint('[SosScreen] Forwarding message ${relayedMessage.id} (hop: ${relayedMessage.hopCount}) excluding source: $sourceEndpointId');
      forwardedPeers = await MeshService.instance.broadcastMessage(
        relayedMessage,
        excludeEndpointId: sourceEndpointId,
      );
    } else {
      debugPrint('[SosScreen] Max hop limit reached (${relayedMessage.hopCount} >= ${MeshService.maxHops}). Stored locally, halting forwarding.');
    }

    // 7. Phase 3 Cloud Bridge Sync: If this device has internet access, automatically sync to Firestore
    SyncService.instance.checkConnectivityAndSync();

    if (mounted) {
      final forwardInfo = relayedMessage.hopCount < MeshService.maxHops
          ? (forwardedPeers > 0 ? ' • Forwarded to $forwardedPeers peer(s)' : ' • Stored in mesh')
          : ' • Max 7-hop cap reached';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '🚨 Relayed SOS: ${relayedMessage.needType?.toUpperCase()} from ${relayedMessage.senderId} (Hop ${relayedMessage.hopCount}$forwardInfo)',
          ),
          backgroundColor: const Color(0xFF1E293B),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Reload the message list from the database.
  Future<void> _loadMessageHistory() async {
    if (kIsWeb) return;
    final list = await DatabaseService.instance.getMessages();
    if (mounted) {
      setState(() {
        _messageHistory = list;
      });
    }
  }

  /// Triggered whenever description text changes to compute real-time triage.
  void _onDescriptionChanged() {
    final triageResult = SeverityEngine.triage(
      description: _descriptionController.text,
      needType: _selectedCategory,
    );

    setState(() {
      _currentScore = triageResult.score;
      _currentTier = triageResult.tier;
      _matchedKeywords = triageResult.matchedKeywords;
      _explanation = triageResult.explanation;
    });
  }

  /// Refreshes geolocation or checks permission.
  Future<void> _fetchLocation() async {
    if (_useDemoLocation) return;

    setState(() {
      _isFetchingLocation = true;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _latitude = null;
          _longitude = null;
          _isFetchingLocation = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _latitude = null;
            _longitude = null;
            _isFetchingLocation = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _latitude = null;
          _longitude = null;
          _isFetchingLocation = false;
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 6),
      ).catchError((_) async {
        return await Geolocator.getLastKnownPosition() ??
            await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.low,
              timeLimit: const Duration(seconds: 4),
            );
      });

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
      });
    } catch (e) {
      setState(() {
        _latitude = null;
        _longitude = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingLocation = false;
        });
      }
    }
  }

  /// Sets coordinate mode (GPS vs Mock/Demo)
  void _toggleDemoLocation(bool? value) {
    setState(() {
      _useDemoLocation = value ?? false;
      if (_useDemoLocation) {
        _latitude = 37.774900;
        _longitude = -122.419400;
      } else {
        _latitude = null;
        _longitude = null;
        _fetchLocation();
      }
    });
  }

  /// Creates and saves the SOS report in Phase 1 SQLite structure.
  Future<void> _broadcastSos() async {
    final String description = _descriptionController.text.trim();
    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please describe the emergency incident.'),
          backgroundColor: Color(0xFFD97706),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Capture location parameters
    final double? finalLat = _latitude;
    final double? finalLng = _longitude;

    // Run final triage calculations
    final triageResult = SeverityEngine.triage(
      description: description,
      needType: _selectedCategory,
    );

    final bool hasPeers = MeshService.instance.isConnected;
    final initialMeshStatus = hasPeers ? MeshDeliveryStatus.sending : MeshDeliveryStatus.pending;

    final sosMessage = MessageModel(
      id: _uuid.v4(),
      type: 'broadcast',
      senderId: _deviceId,
      payload: description,
      needType: _selectedCategory,
      lat: finalLat,
      lng: finalLng,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      hopCount: 0,
      priorityTier: triageResult.tier,
      priorityScore: triageResult.score,
      synced: false,
      meshDeliveryStatus: initialMeshStatus,
    );

    // Save locally first to SQLite and record as seen
    await DatabaseService.instance.saveSeenMessageId(sosMessage.id);
    await DatabaseService.instance.saveMessage(sosMessage);

    // Phase 2 & 5A: Broadcast to connected peer(s) over Bluetooth mesh if available
    int sentCount = 0;
    if (hasPeers) {
      sentCount = await MeshService.instance.broadcastMessage(sosMessage);
      if (sentCount > 0) {
        await DatabaseService.instance.markMessageMeshTransmitted(sosMessage.id);
      } else {
        await DatabaseService.instance.updateMeshDeliveryStatus(sosMessage.id, MeshDeliveryStatus.pending);
      }
    }

    // Refresh local UI history
    await _loadMessageHistory();

    // Phase 5B.2: Notify battery duty-cycle manager of pending queue state update
    final currentPending = await DatabaseService.instance.getPendingMeshMessages();
    BatteryDutyCycleManager.instance.notifyPendingCountChanged(currentPending.length);

    // Phase 3: If device currently has internet, automatically sync to Firestore cloud
    SyncService.instance.checkConnectivityAndSync();

    // Clearly communicate local saving and peer transmission status
    if (mounted) {
      final String feedbackText = sentCount > 0
          ? 'SOS SAVED LOCALLY • Transmitted to $sentCount connected peer${sentCount == 1 ? "" : "s"}'
          : 'SOS SAVED LOCALLY • Stored to database (Pending — waiting for nearby device)';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  feedbackText,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: sentCount > 0 ? const Color(0xFF15803D) : const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }

    _descriptionController.clear();
    _loadMessageHistory();
  }

  // --- Design System Color & Icon Helpers ---

  Color _getTierColor(String tier) {
    switch (tier.toLowerCase()) {
      case 'critical':
        return const Color(0xFFDC2626); // Crimson Red
      case 'urgent':
        return const Color(0xFFEA580C); // Vibrant Orange
      case 'needs':
        return const Color(0xFF2563EB); // Deep Blue
      default:
        return const Color(0xFF64748B); // Slate Grey
    }
  }

  Color _getTierBgColor(String tier) {
    switch (tier.toLowerCase()) {
      case 'critical':
        return const Color(0xFFFEF2F2);
      case 'urgent':
        return const Color(0xFFFFF7ED);
      case 'needs':
        return const Color(0xFFEFF6FF);
      default:
        return const Color(0xFFF1F5F9);
    }
  }

  Color _getTierBorderColor(String tier) {
    switch (tier.toLowerCase()) {
      case 'critical':
        return const Color(0xFFFECACA);
      case 'urgent':
        return const Color(0xFFFED7AA);
      case 'needs':
        return const Color(0xFFBFDBFE);
      default:
        return const Color(0xFFE2E8F0);
    }
  }

  IconData _getCategoryIcon(String? category) {
    switch (category?.toLowerCase()) {
      case 'medical':
        return Icons.medical_services_outlined;
      case 'trapped':
        return Icons.emergency_outlined;
      case 'fire':
        return Icons.local_fire_department_outlined;
      case 'water':
        return Icons.water_drop_outlined;
      case 'food':
        return Icons.restaurant_outlined;
      case 'shelter':
        return Icons.home_work_outlined;
      default:
        return Icons.warning_amber_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        titleSpacing: 16,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cell_tower,
              color: Color(0xFFDC2626),
              size: 20,
            ),
            SizedBox(width: 8),
            Text(
              'Crisis Mesh',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w800,
                fontSize: 18,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              _loadMessageHistory();
              _fetchLocation();
              MeshService.instance.startMesh();
              SyncService.instance.checkConnectivityAndSync();
            },
            tooltip: 'Refresh & Sync Status',
          ),
          const SizedBox(width: 4),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isTablet = constraints.maxWidth >= 720;
            if (isTablet) {
              return _buildTabletLayout();
            } else {
              return _buildMobileLayout();
            }
          },
        ),
      ),
    );
  }

  // --- Mobile Single-Column Responsive Layout ---
  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Mesh connection status
          _buildMeshStatusBanner(),
          const SizedBox(height: 8),
          _buildSyncStatusBanner(),
          const SizedBox(height: 16),

          // 2. SEND SOS Section
          _buildSendSosSectionHeader(),
          const SizedBox(height: 10),
          _buildSosFormCard(),
          const SizedBox(height: 12),
          _buildEmergencyPriorityCard(),
          const SizedBox(height: 12),
          _buildLocationCard(),
          const SizedBox(height: 16),
          _buildBroadcastButton(),
          const SizedBox(height: 24),

          // 3. Local Logged Alerts Section
          _buildAlertsSectionHeader(),
          const SizedBox(height: 12),
          _buildAlertsList(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // --- Tablet Two-Column Responsive Layout ---
  Widget _buildTabletLayout() {
    return Column(
      children: [
        // Full width Mesh & Cloud status banners
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(
            children: [
              Expanded(child: _buildMeshStatusBanner()),
              const SizedBox(width: 12),
              Expanded(child: _buildSyncStatusBanner()),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Column: SOS Creation & Broadcast
              Expanded(
                flex: 5,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSendSosSectionHeader(),
                      const SizedBox(height: 10),
                      _buildSosFormCard(),
                      const SizedBox(height: 12),
                      _buildEmergencyPriorityCard(),
                      const SizedBox(height: 12),
                      _buildLocationCard(),
                      const SizedBox(height: 16),
                      _buildBroadcastButton(),
                    ],
                  ),
                ),
              ),

              // Vertical divider
              const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE2E8F0)),

              // Right Column: Local Logged Alerts Feed
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildAlertsSectionHeader(),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _messageHistory.isEmpty
                            ? _buildEmptyAlertsState()
                            : ListView.builder(
                                itemCount: _messageHistory.length,
                                itemBuilder: (context, index) {
                                  return _buildAlertCard(_messageHistory[index]);
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Section Headers ---

  Widget _buildSendSosSectionHeader() {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: const Color(0xFFDC2626),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'SEND SOS',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildAlertsSectionHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              const Flexible(
                child: Text(
                  'LOCAL LOGGED ALERTS',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Text(
            '${_messageHistory.length} ${_messageHistory.length == 1 ? "alert" : "alerts"}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF475569),
            ),
          ),
        ),
      ],
    );
  }

  // --- Mesh Connection Status Banner ---
  Widget _buildMeshStatusBanner() {
    final mesh = MeshService.instance;
    final Color badgeBg;
    final Color borderColor;
    final Color textColor;
    final String titleText;
    final String subtitleText;
    final Widget indicator;

    switch (mesh.status) {
      case MeshStatus.connected:
        badgeBg = const Color(0xFFF0FDF4);
        borderColor = const Color(0xFFBBF7D0);
        textColor = const Color(0xFF15803D);
        titleText = '🟢 ${mesh.connectedPeerCount} nearby device${mesh.connectedPeerCount == 1 ? "" : "s"} connected';
        subtitleText = 'Emergency Mesh Active • Background relay ready';
        indicator = const Icon(Icons.link, size: 18, color: Color(0xFF15803D));
        break;
      case MeshStatus.searching:
        badgeBg = const Color(0xFFF0FDF4);
        borderColor = const Color(0xFFBBF7D0);
        textColor = const Color(0xFF15803D);
        titleText = '🟢 Emergency Mesh Active';
        subtitleText = 'Monitoring nearby peers • Ready to relay in background';
        indicator = const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF15803D)),
          ),
        );
        break;
      case MeshStatus.idle:
        badgeBg = const Color(0xFFF8FAFC);
        borderColor = const Color(0xFFE2E8F0);
        textColor = const Color(0xFF475569);
        titleText = '⚪ Emergency Mesh Inactive';
        subtitleText = 'Tap to enable background peer discovery & relay';
        indicator = TextButton(
          onPressed: _enableEmergencyMesh,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            backgroundColor: const Color(0xFF0F172A),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('ENABLE MESH', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
        );
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: badgeBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titleText,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitleText,
                  style: TextStyle(
                    fontSize: 11,
                    color: textColor.withAlpha(204),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          indicator,
        ],
      ),
    );
  }

  // --- Cloud Bridge Synchronization Status Banner ---
  Widget _buildSyncStatusBanner() {
    final sync = SyncService.instance;
    final Color badgeBg;
    final Color borderColor;
    final Color textColor;
    final String titleText;
    final String subtitleText;
    final Widget indicator;

    switch (sync.status) {
      case SyncStatus.synced:
        badgeBg = const Color(0xFFF0FDF4);
        borderColor = const Color(0xFFBBF7D0);
        textColor = const Color(0xFF15803D);
        titleText = '☁️ Cloud Bridge: Connected';
        subtitleText = 'All local SOS alerts are synchronized to Firebase Firestore';
        indicator = const Icon(Icons.cloud_done_rounded, size: 18, color: Color(0xFF15803D));
        break;
      case SyncStatus.syncing:
        badgeBg = const Color(0xFFEFF6FF);
        borderColor = const Color(0xFFBFDBFE);
        textColor = const Color(0xFF1D4ED8);
        titleText = '🔄 Synchronizing with Cloud';
        subtitleText = 'Uploading pending offline SOS reports to Firestore...';
        indicator = const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1D4ED8)),
          ),
        );
        break;
      case SyncStatus.checking:
        badgeBg = const Color(0xFFFFFBEB);
        borderColor = const Color(0xFFFDE68A);
        textColor = const Color(0xFFB45309);
        titleText = '🟡 Checking Internet Reachability';
        subtitleText = 'Testing Firestore connection on available network interface';
        indicator = const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFB45309)),
          ),
        );
        break;
      case SyncStatus.error:
        badgeBg = const Color(0xFFFEF2F2);
        borderColor = const Color(0xFFFECACA);
        textColor = const Color(0xFFDC2626);
        titleText = '⚠️ Cloud Sync Interrupted';
        subtitleText = sync.lastError ?? 'Could not complete Firestore upload batch';
        indicator = TextButton(
          onPressed: _manualSync,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('RETRY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        );
        break;
      case SyncStatus.offline:
        badgeBg = const Color(0xFFF8FAFC);
        borderColor = const Color(0xFFE2E8F0);
        textColor = const Color(0xFF475569);
        titleText = '📡 Offline Bridge Mode';
        subtitleText = 'No internet • SOS reports queued for cloud auto-sync';
        indicator = TextButton(
          onPressed: _manualSync,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('SYNC', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        );
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: badgeBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titleText,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitleText,
                  style: TextStyle(
                    fontSize: 11,
                    color: textColor.withAlpha(204),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          indicator,
        ],
      ),
    );
  }

  // --- SOS Incident Form Card ---
  Widget _buildSosFormCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'NEED CATEGORY',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFF64748B),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),

          // Category Dropdown (Responsive & non-overflowing)
          DropdownButtonFormField<String>(
            initialValue: _selectedCategory,
            isExpanded: true,
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            items: _categories.map((cat) {
              return DropdownMenuItem<String>(
                value: cat,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getCategoryIcon(cat),
                      size: 17,
                      color: const Color(0xFF1E293B),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        cat.toUpperCase(),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _selectedCategory = val;
                  _onDescriptionChanged();
                });
              }
            },
          ),
          const SizedBox(height: 14),

          const Text(
            'EMERGENCY DESCRIPTION',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFF64748B),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),

          // Incident details input
          TextFormField(
            controller: _descriptionController,
            maxLines: 3,
            maxLength: 250,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 13,
              height: 1.4,
            ),
            decoration: InputDecoration(
              hintText: 'Describe victims, trapped persons, severe injuries, immediate hazards, etc.',
              hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- EMERGENCY PRIORITY Card ---
  Widget _buildEmergencyPriorityCard() {
    final tierColor = _getTierColor(_currentTier);
    final tierBgColor = _getTierBgColor(_currentTier);
    final tierBorderColor = _getTierBorderColor(_currentTier);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: EMERGENCY PRIORITY and Tier Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Text(
                  'EMERGENCY PRIORITY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF64748B),
                    letterSpacing: 0.8,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tierBgColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: tierBorderColor),
                ),
                child: Text(
                  _currentTier.toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    color: tierColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Score bar & Text
          Row(
            children: [
              Text(
                'Priority $_currentScore/10',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: tierColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (_currentScore.clamp(1, 10)) / 10.0,
                    minHeight: 6,
                    backgroundColor: const Color(0xFFE2E8F0),
                    valueColor: AlwaysStoppedAnimation<Color>(tierColor),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Matched Keywords
          const Text(
            'Matched Keywords:',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 6),
          if (_matchedKeywords.isEmpty)
            const Text(
              'No high-severity keywords matched (Default low priority)',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF94A3B8),
                fontStyle: FontStyle.italic,
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _matchedKeywords.map((kw) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: tierBgColor,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: tierBorderColor),
                  ),
                  child: Text(
                    kw,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: tierColor,
                    ),
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 10),

          // Rationale Explanation
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _explanation,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF334155),
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Location & GPS Card ---
  Widget _buildLocationCard() {
    final bool hasCoords = _latitude != null && _longitude != null;
    final String coordText = hasCoords
        ? '${_latitude!.toStringAsFixed(6)}, ${_longitude!.toStringAsFixed(6)}'
        : (_isFetchingLocation ? 'Acquiring GPS fix...' : 'GPS Coordinates Unavailable');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Text(
                  'LOCATION STATUS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF64748B),
                    letterSpacing: 0.8,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              if (_isFetchingLocation)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                  ),
                )
              else
                Icon(
                  hasCoords ? Icons.gps_fixed : Icons.gps_off,
                  size: 16,
                  color: hasCoords ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Coordinates Box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.location_on,
                  size: 16,
                  color: hasCoords ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    coordText,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: hasCoords ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Action controls: GET GPS LOCATION and Demo Coordinates toggle (using Wrap to prevent overflow)
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _isFetchingLocation ? null : _fetchLocation,
                icon: const Icon(Icons.my_location, size: 14),
                label: const Text(
                  'GET GPS LOCATION',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1E293B),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              InkWell(
                onTap: () => _toggleDemoLocation(!_useDemoLocation),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: Checkbox(
                          value: _useDemoLocation,
                          onChanged: _toggleDemoLocation,
                          activeColor: const Color(0xFF2563EB),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Demo Mode',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- BROADCAST SOS Button ---
  Widget _buildBroadcastButton() {
    return ElevatedButton(
      onPressed: _broadcastSos,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFDC2626), // Crimson emergency red
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 15),
        elevation: 2,
        shadowColor: const Color(0x40DC2626),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.campaign_rounded, size: 22),
          SizedBox(width: 10),
          Text(
            'BROADCAST SOS',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  // --- Local Logged Alerts List & Empty State ---

  Widget _buildAlertsList() {
    if (_messageHistory.isEmpty) {
      return _buildEmptyAlertsState();
    }
    return Column(
      children: _messageHistory.map((msg) => _buildAlertCard(msg)).toList(),
    );
  }

  Widget _buildEmptyAlertsState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.inbox_outlined, size: 40, color: Color(0xFF94A3B8)),
            SizedBox(height: 10),
            Text(
              'No Local Alerts Logged',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Dispatched emergency broadcasts and received mesh packets will be displayed here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertCard(MessageModel msg) {
    final date = DateTime.fromMillisecondsSinceEpoch(msg.timestamp);
    final timeStr = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
    final hasLoc = msg.lat != null && msg.lng != null;
    final tierColor = _getTierColor(msg.priorityTier);
    final tierBgColor = _getTierBgColor(msg.priorityTier);
    final tierBorderColor = _getTierBorderColor(msg.priorityTier);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: tierColor, width: 4),
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Need Type, Priority Tier & Score, Hop Count (using Wrap to prevent overflow)
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Category Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getCategoryIcon(msg.needType),
                          size: 12,
                          color: const Color(0xFF1E293B),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          msg.needType?.toUpperCase() ?? 'BROADCAST',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Priority Tier & Score Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: tierBgColor,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: tierBorderColor),
                    ),
                    child: Text(
                      '${msg.priorityTier.toUpperCase()} • ${msg.priorityScore}/10',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: tierColor,
                      ),
                    ),
                  ),

                  // Hop Count Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      msg.hopCount == 0 ? 'Direct (Hop 0)' : 'Relayed (Hop ${msg.hopCount})',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),

                  // Phase 5A Mesh Delivery Status Badge (for locally generated broadcasts)
                  if (msg.hopCount == 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: msg.isMeshPending
                            ? const Color(0xFFFFFBEB)
                            : (msg.isMeshSending ? const Color(0xFFEFF6FF) : const Color(0xFFF0FDF4)),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: msg.isMeshPending
                              ? const Color(0xFFFDE68A)
                              : (msg.isMeshSending ? const Color(0xFFBFDBFE) : const Color(0xFFBBF7D0)),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            msg.isMeshPending
                                ? Icons.schedule_rounded
                                : (msg.isMeshSending ? Icons.sync_rounded : Icons.check_circle_outline_rounded),
                            size: 11,
                            color: msg.isMeshPending
                                ? const Color(0xFFB45309)
                                : (msg.isMeshSending ? const Color(0xFF1D4ED8) : const Color(0xFF15803D)),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            MeshDeliveryStatus.badgeText(msg.meshDeliveryStatus),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: msg.isMeshPending
                                  ? const Color(0xFFB45309)
                                  : (msg.isMeshSending ? const Color(0xFF1D4ED8) : const Color(0xFF15803D)),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Phase 3 Cloud Sync Status Badge (Cloud Synced vs Mesh Only)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: msg.synced ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: msg.synced ? const Color(0xFF86EFAC) : const Color(0xFFCBD5E1),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          msg.synced ? Icons.cloud_done_rounded : Icons.cell_tower_rounded,
                          size: 11,
                          color: msg.synced ? const Color(0xFF15803D) : const Color(0xFF475569),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          msg.synced ? 'Cloud Synced' : 'Mesh Only',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: msg.synced ? const Color(0xFF15803D) : const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Description Payload
              Text(
                msg.payload ?? '',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F172A),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 8),

              // Metadata Footer: Coordinates & Timestamp
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hasLoc ? Icons.location_on : Icons.location_off,
                        size: 12,
                        color: hasLoc ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        hasLoc
                            ? '${msg.lat!.toStringAsFixed(4)}, ${msg.lng!.toStringAsFixed(4)}'
                            : 'No Coordinates',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: hasLoc ? const Color(0xFF475569) : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.access_time, size: 11, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 4),
                      Text(
                        timeStr,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Manually trigger cloud bridge synchronization (for testing and on-demand sync).
  Future<void> _manualSync() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Checking network & syncing pending SOS reports...'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );

    final syncedCount = await SyncService.instance.manualSync();
    if (!mounted) return;

    await _loadMessageHistory();
    final status = SyncService.instance.status;
    final String msg;
    final Color bg;

    if (status == SyncStatus.synced) {
      msg = syncedCount > 0
          ? 'Cloud Sync Complete • $syncedCount report(s) uploaded to Firestore'
          : 'Cloud Sync • All local reports are up to date';
      bg = const Color(0xFF15803D);
    } else if (status == SyncStatus.offline) {
      msg = 'Device Offline • Reports preserved in local database and mesh';
      bg = const Color(0xFF1E293B);
    } else {
      msg = 'Sync Note: ${SyncService.instance.lastError ?? "Firestore unreachable"}';
      bg = const Color(0xFFDC2626);
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: bg,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
