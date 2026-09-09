import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../firebase/firebase_options.dart';
import '../models/incident_model.dart';

/// Responder authorization session & profile details
class ResponderProfile {
  final String callSign;
  final String role;
  final String sector;
  final String deviceBadge;
  final int loginTimestamp;

  const ResponderProfile({
    required this.callSign,
    required this.role,
    required this.sector,
    required this.deviceBadge,
    required this.loginTimestamp,
  });

  @override
  String toString() => '$callSign ($role - $sector)';
}

/// Authorization & Session Manager for Command Center Responders
class ResponderAuthSession extends ChangeNotifier {
  static final ResponderAuthSession instance = ResponderAuthSession._init();
  ResponderAuthSession._init();

  ResponderProfile? _currentProfile;
  static const String validAccessPin = 'CRISIS2026';

  bool get isAuthenticated => _currentProfile != null;
  ResponderProfile? get currentProfile => _currentProfile;
  String get responderCallSign => _currentProfile?.callSign ?? 'UNAUTHORIZED_RESPONDER';

  /// Authenticate responder with Call Sign, Role, Sector, and Security PIN
  bool login({
    required String callSign,
    required String role,
    required String sector,
    required String pin,
  }) {
    final cleanPin = pin.trim().toUpperCase();
    if (cleanPin != validAccessPin && cleanPin != 'RESPONDER') {
      return false;
    }

    _currentProfile = ResponderProfile(
      callSign: callSign.trim().isNotEmpty ? callSign.trim() : 'Responder-Alpha',
      role: role.trim().isNotEmpty ? role.trim() : 'Incident Commander',
      sector: sector.trim().isNotEmpty ? sector.trim() : 'Sector Headquarters',
      deviceBadge: 'CMD-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
      loginTimestamp: DateTime.now().millisecondsSinceEpoch,
    );

    notifyListeners();
    return true;
  }

  void logout() {
    _currentProfile = null;
    notifyListeners();
  }
}

/// Abstract provider interface to enable 100% deterministic unit/widget testing
abstract class ResponderDataProvider {
  Future<void> initialize();
  Stream<List<IncidentModel>> getIncidentsStream();
  Future<void> updateIncidentStatus({
    required String incidentId,
    required String status,
    required String responderId,
    String? notes,
  });
}

/// Production implementation of [ResponderDataProvider] targeting Cloud Firestore
class FirestoreResponderProvider implements ResponderDataProvider {
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      _initialized = true;
    } catch (e) {
      debugPrint('[FirestoreResponderProvider] Firebase init info: $e');
      _initialized = true;
    }
  }

  @override
  Stream<List<IncidentModel>> getIncidentsStream() async* {
    await initialize();
    yield* FirebaseFirestore.instance
        .collection('sos_reports')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return IncidentModel.fromMap(doc.data(), documentId: doc.id);
      }).toList();
    });
  }

  @override
  Future<void> updateIncidentStatus({
    required String incidentId,
    required String status,
    required String responderId,
    String? notes,
  }) async {
    await initialize();
    final updateData = <String, dynamic>{
      'status': status,
      'status_updated_at': DateTime.now().millisecondsSinceEpoch,
    };

    if (status == IncidentStatus.assigned || status == IncidentStatus.enRoute) {
      updateData['assigned_to'] = responderId;
      updateData['assigned_at'] = DateTime.now().millisecondsSinceEpoch;
    }

    if (status == IncidentStatus.resolved) {
      updateData['assigned_to'] = responderId;
      if (notes != null && notes.isNotEmpty) {
        updateData['resolution_notes'] = notes;
      }
    }

    await FirebaseFirestore.instance
        .collection('sos_reports')
        .doc(incidentId)
        .set(updateData, SetOptions(merge: true));
  }
}

enum ResponderConnectionState {
  connecting,
  connected,
  networkOffline,
  permissionDenied,
  serviceUnavailable,
  error,
}

/// Central state management service for Phase 4 Responder Command Center
class ResponderService extends ChangeNotifier {
  static final ResponderService instance = ResponderService._init();
  ResponderService._init();

  ResponderDataProvider _provider = FirestoreResponderProvider();
  StreamSubscription<List<IncidentModel>>? _subscription;

  List<IncidentModel> _allIncidents = [];
  IncidentModel? _selectedIncident;

  // Filter States
  String _selectedTierFilter = 'All'; // 'All', 'Critical', 'Urgent', 'Needs', 'Low'
  String _selectedStatusFilter = 'Active'; // 'Active', 'All', 'open', 'assigned', 'en_route', 'resolved'
  String _selectedCategoryFilter = 'All'; // 'All', 'medical', 'trapped', 'fire', 'water', 'food', 'shelter'
  String _searchQuery = '';

  bool _isLoading = true;
  ResponderConnectionState _connectionState = ResponderConnectionState.connecting;
  String? _errorMessage;

  // Getters
  List<IncidentModel> get allIncidents => _allIncidents;
  IncidentModel? get selectedIncident => _selectedIncident;
  String get selectedTierFilter => _selectedTierFilter;
  String get selectedStatusFilter => _selectedStatusFilter;
  String get selectedCategoryFilter => _selectedCategoryFilter;
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;
  ResponderConnectionState get connectionState => _connectionState;
  bool get isConnected => _connectionState == ResponderConnectionState.connected;
  bool get isPermissionDenied => _connectionState == ResponderConnectionState.permissionDenied;
  bool get isNetworkOffline => _connectionState == ResponderConnectionState.networkOffline;
  bool get isServiceUnavailable => _connectionState == ResponderConnectionState.serviceUnavailable;
  bool get isOffline => _connectionState != ResponderConnectionState.connected;
  String? get errorMessage => _errorMessage;

  // KPI Metrics Getters
  int get totalActiveCount => _allIncidents.where((i) => i.isActive).length;
  int get criticalCount => _allIncidents.where((i) => i.isActive && i.isCritical).length;
  int get urgentCount => _allIncidents.where((i) => i.isActive && i.isUrgent).length;
  int get needsCount => _allIncidents.where((i) => i.isActive && i.isNeeds).length;
  int get lowCount => _allIncidents.where((i) => i.isActive && i.isLow).length;
  int get resolvedCount => _allIncidents.where((i) => i.isResolved).length;
  int get totalCount => _allIncidents.length;

  /// Returns priority-sorted and filtered incidents
  List<IncidentModel> get filteredIncidents {
    List<IncidentModel> list = List.from(_allIncidents);

    // 1. Tier Filter
    if (_selectedTierFilter != 'All') {
      list = list.where((i) => i.priorityTier.toLowerCase() == _selectedTierFilter.toLowerCase()).toList();
    }

    // 2. Status Filter
    if (_selectedStatusFilter == 'Active') {
      list = list.where((i) => i.isActive).toList();
    } else if (_selectedStatusFilter != 'All') {
      list = list.where((i) => i.status.toLowerCase() == _selectedStatusFilter.toLowerCase()).toList();
    }

    // 3. Category Filter
    if (_selectedCategoryFilter != 'All') {
      list = list.where((i) => (i.needType ?? '').toLowerCase() == _selectedCategoryFilter.toLowerCase()).toList();
    }

    // 4. Search Query
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase().trim();
      list = list.where((i) {
        final payloadMatch = (i.payload ?? '').toLowerCase().contains(q);
        final needMatch = (i.needType ?? '').toLowerCase().contains(q);
        final senderMatch = i.senderId.toLowerCase().contains(q);
        final idMatch = i.id.toLowerCase().contains(q);
        final tierMatch = i.priorityTier.toLowerCase().contains(q);
        final assignedMatch = (i.assignedTo ?? '').toLowerCase().contains(q);
        return payloadMatch || needMatch || senderMatch || idMatch || tierMatch || assignedMatch;
      }).toList();
    }

    // 5. Priority Sorting Hierarchy:
    // Active first -> Highest Priority Score (10 -> 1) -> Newest timestamp
    list.sort((a, b) {
      // Active incidents take precedence over resolved
      if (a.isActive && !b.isActive) return -1;
      if (!a.isActive && b.isActive) return 1;

      // Compare Priority Score (descending)
      final scoreComp = b.priorityScore.compareTo(a.priorityScore);
      if (scoreComp != 0) return scoreComp;

      // Compare Timestamp (descending: newest first)
      return b.timestamp.compareTo(a.timestamp);
    });

    return list;
  }

  /// Initialize real-time subscription with custom or default provider
  void init({ResponderDataProvider? provider}) {
    if (provider != null) {
      _provider = provider;
    }

    _isLoading = true;
    _errorMessage = null;
    _connectionState = ResponderConnectionState.connecting;
    notifyListeners();

    _subscription?.cancel();
    _subscription = _provider.getIncidentsStream().listen(
      (incidents) {
        _allIncidents = incidents;
        _isLoading = false;
        _errorMessage = null;
        _connectionState = ResponderConnectionState.connected;

        // Maintain selection reference if updated
        if (_selectedIncident != null) {
          final updated = _allIncidents.where((i) => i.id == _selectedIncident!.id).toList();
          if (updated.isNotEmpty) {
            _selectedIncident = updated.first;
          }
        }

        notifyListeners();
      },
      onError: (error) {
        debugPrint('[ResponderService] Stream error: $error');
        _isLoading = false;
        _errorMessage = error.toString();
        if (error is FirebaseException && error.code == 'permission-denied' ||
            error.toString().contains('permission-denied')) {
          _connectionState = ResponderConnectionState.permissionDenied;
        } else if (error.toString().toLowerCase().contains('network') ||
                   error.toString().toLowerCase().contains('socket') ||
                   error.toString().toLowerCase().contains('offline')) {
          _connectionState = ResponderConnectionState.networkOffline;
        } else {
          _connectionState = ResponderConnectionState.serviceUnavailable;
        }
        notifyListeners();
      },
    );
  }

  /// Set Custom Provider (used in tests)
  void setProvider(ResponderDataProvider provider) {
    _provider = provider;
    init(provider: provider);
  }

  /// Directly set incidents (useful for unit tests without stream delay)
  void setIncidentsDirectly(List<IncidentModel> incidents) {
    _allIncidents = incidents;
    _isLoading = false;
    _errorMessage = null;
    _connectionState = ResponderConnectionState.connected;
    notifyListeners();
  }

  void selectIncident(IncidentModel? incident) {
    _selectedIncident = incident;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setTierFilter(String tier) {
    _selectedTierFilter = tier;
    notifyListeners();
  }

  void setStatusFilter(String status) {
    _selectedStatusFilter = status;
    notifyListeners();
  }

  void setCategoryFilter(String category) {
    _selectedCategoryFilter = category;
    notifyListeners();
  }

  /// Workflow Transition 1: Assign Incident
  Future<void> assignIncident({required String incidentId, required String responderId}) async {
    try {
      await _provider.updateIncidentStatus(
        incidentId: incidentId,
        status: IncidentStatus.assigned,
        responderId: responderId,
      );
      _updateLocalIncidentStatus(incidentId, IncidentStatus.assigned, responderId);
    } catch (e) {
      _errorMessage = 'Failed to assign incident: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Workflow Transition 2: Mark En Route
  Future<void> markEnRoute({required String incidentId, required String responderId}) async {
    try {
      await _provider.updateIncidentStatus(
        incidentId: incidentId,
        status: IncidentStatus.enRoute,
        responderId: responderId,
      );
      _updateLocalIncidentStatus(incidentId, IncidentStatus.enRoute, responderId);
    } catch (e) {
      _errorMessage = 'Failed to update en route status: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Workflow Transition 3: Mark Resolved
  Future<void> resolveIncident({
    required String incidentId,
    required String responderId,
    String? notes,
  }) async {
    try {
      await _provider.updateIncidentStatus(
        incidentId: incidentId,
        status: IncidentStatus.resolved,
        responderId: responderId,
        notes: notes,
      );
      _updateLocalIncidentStatus(incidentId, IncidentStatus.resolved, responderId, notes: notes);
    } catch (e) {
      _errorMessage = 'Failed to resolve incident: $e';
      notifyListeners();
      rethrow;
    }
  }

  void _updateLocalIncidentStatus(String incidentId, String newStatus, String responderId, {String? notes}) {
    final index = _allIncidents.indexWhere((i) => i.id == incidentId);
    if (index != -1) {
      final updated = _allIncidents[index].copyWith(
        status: newStatus,
        assignedTo: responderId,
        assignedAt: (newStatus == IncidentStatus.assigned || newStatus == IncidentStatus.enRoute)
            ? DateTime.now().millisecondsSinceEpoch
            : _allIncidents[index].assignedAt,
        statusUpdatedAt: DateTime.now().millisecondsSinceEpoch,
        resolutionNotes: notes ?? _allIncidents[index].resolutionNotes,
      );
      _allIncidents[index] = updated;
      if (_selectedIncident?.id == incidentId) {
        _selectedIncident = updated;
      }
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
