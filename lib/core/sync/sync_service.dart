import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../database/database_service.dart';
import '../firebase/firebase_options.dart';
import '../models/message_model.dart';

enum SyncStatus {
  networkOffline,
  firestoreUnavailable,
  firestorePermissionDenied,
  syncing,
  connected,
  syncError;

  // Backward compatibility helpers
  static const SyncStatus offline = SyncStatus.networkOffline;
  static const SyncStatus checking = SyncStatus.syncing;
  static const SyncStatus synced = SyncStatus.connected;
  static const SyncStatus error = SyncStatus.syncError;

  bool get isConnected => this == SyncStatus.connected;
  bool get isNetworkOffline => this == SyncStatus.networkOffline;
  bool get isPermissionDenied => this == SyncStatus.firestorePermissionDenied;
  bool get isFirestoreUnavailable => this == SyncStatus.firestoreUnavailable;
  bool get isSyncError => this == SyncStatus.syncError;
  bool get isSyncing => this == SyncStatus.syncing;
}

enum FirestoreReachability {
  connected,
  permissionDenied,
  unavailable,
}

/// Abstract provider to allow decoupling and mock-based unit/integration testing.
abstract class FirestoreSyncProvider {
  Future<void> initialize();
  Future<FirestoreReachability> checkFirestoreReachability();
  Future<void> uploadSosReport(String docId, Map<String, dynamic> data);
}

/// Production implementation of [FirestoreSyncProvider] targeting Cloud Firestore.
class DefaultFirestoreProvider implements FirestoreSyncProvider {
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
      debugPrint('[DefaultFirestoreProvider] Firebase initializeApp note: $e');
      _initialized = true; // Attempt to proceed even if default app already registered
    }
  }

  @override
  Future<FirestoreReachability> checkFirestoreReachability() async {
    try {
      await initialize();
      // Verify Firestore client can interact with server/network
      final instance = FirebaseFirestore.instance;
      // Lightweight probe with a short timeout to prevent blocking when offline
      await instance.collection('sos_reports').limit(1).get(
            const GetOptions(source: Source.server),
          ).timeout(const Duration(seconds: 4));
      return FirestoreReachability.connected;
    } on FirebaseException catch (e) {
      debugPrint('[DefaultFirestoreProvider] Firestore reachability FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        return FirestoreReachability.permissionDenied;
      }
      return FirestoreReachability.unavailable;
    } catch (e) {
      debugPrint('[DefaultFirestoreProvider] Firestore reachability probe error: $e');
      if (e.toString().contains('permission-denied')) {
        return FirestoreReachability.permissionDenied;
      }
      return FirestoreReachability.unavailable;
    }
  }

  @override
  Future<void> uploadSosReport(String docId, Map<String, dynamic> data) async {
    await initialize();
    // Idempotent upsert: doc ID is identical to origin message UUID
    await FirebaseFirestore.instance
        .collection('sos_reports')
        .doc(docId)
        .set(data, SetOptions(merge: true));
  }
}

/// Hybrid Transport Sync Service: manages offline-to-cloud bridge synchronization.
class SyncService extends ChangeNotifier {
  static final SyncService instance = SyncService._init();

  SyncService._init();

  String _localDeviceId = 'unknown';
  SyncStatus _status = SyncStatus.networkOffline;
  String? _lastError;
  int _lastSyncedCount = 0;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  FirestoreSyncProvider _provider = DefaultFirestoreProvider();

  SyncStatus get status => _status;
  String? get lastError => _lastError;
  int get lastSyncedCount => _lastSyncedCount;
  bool get isOnline => _status == SyncStatus.connected || _status == SyncStatus.syncing;

  /// Initializes the sync service with local device ID and optional custom provider.
  void init({
    required String localDeviceId,
    FirestoreSyncProvider? provider,
  }) {
    _localDeviceId = localDeviceId;
    if (provider != null) {
      _provider = provider;
    }

    _connectivitySubscription?.cancel();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      _onConnectivityChanged(results);
    });

    // Check initial connectivity status
    checkConnectivityAndSync();
  }

  /// Sets a custom provider (useful for unit and integration testing).
  void setProvider(FirestoreSyncProvider provider) {
    _provider = provider;
  }

  Future<void> _onConnectivityChanged(List<ConnectivityResult> results) async {
    final hasNetworkInterface = results.any((r) => r != ConnectivityResult.none);
    if (!hasNetworkInterface) {
      _status = SyncStatus.networkOffline;
      _lastError = 'No network interface available';
      notifyListeners();
    } else {
      // Transitioned to a network interface: check reachability and sync
      await checkConnectivityAndSync();
    }
  }

  /// Checks connectivity, verifies Firestore reachability, and triggers sync if online.
  Future<int> checkConnectivityAndSync() async {
    final connectivityResults = await Connectivity().checkConnectivity();
    final hasInterface = connectivityResults.any((r) => r != ConnectivityResult.none);

    if (!hasInterface) {
      _status = SyncStatus.networkOffline;
      _lastError = 'No network interface available';
      notifyListeners();
      return 0;
    }

    _status = SyncStatus.syncing;
    notifyListeners();

    final reachability = await _provider.checkFirestoreReachability();
    if (reachability == FirestoreReachability.permissionDenied) {
      debugPrint('[SyncService] Firestore permission denied for /sos_reports.');
      _status = SyncStatus.firestorePermissionDenied;
      _lastError = 'Cloud security rules rejected access to /sos_reports';
      notifyListeners();
      return 0;
    } else if (reachability == FirestoreReachability.unavailable) {
      debugPrint('[SyncService] Network interface active but Firestore unreachable.');
      _status = SyncStatus.firestoreUnavailable;
      _lastError = 'Unable to reach Cloud Firestore servers';
      notifyListeners();
      return 0;
    }

    return await syncPendingMessages();
  }

  /// Queries all unsynced messages from SQLite and synchronizes them to Firestore.
  Future<int> syncPendingMessages() async {
    _status = SyncStatus.syncing;
    _lastError = null;
    notifyListeners();

    try {
      final unsyncedMessages = await DatabaseService.instance.getUnsyncedMessages();
      if (unsyncedMessages.isEmpty) {
        debugPrint('[SyncService] No pending messages to sync.');
        _status = SyncStatus.connected;
        notifyListeners();
        return 0;
      }

      debugPrint('[SyncService] Found ${unsyncedMessages.length} unsynced message(s). Starting bridge upload...');
      int syncedCount = 0;
      bool hasPartialFailure = false;

      for (final MessageModel message in unsyncedMessages) {
        try {
          final firestoreData = message.toFirestoreMap(bridgeDeviceId: _localDeviceId);
          // 1. Upload to Firestore /sos_reports/{originalMessageId}
          await _provider.uploadSosReport(message.id, firestoreData);

          // 2. Mark local message synced = 1 only after Firestore confirmation
          await DatabaseService.instance.markMessageSynced(message.id);
          syncedCount++;
          debugPrint('[SyncService] Successfully synced message ${message.id} to Firestore.');
        } catch (e) {
          debugPrint('[SyncService] Partial batch failure on message ${message.id}: $e');
          _lastError = e.toString();
          hasPartialFailure = true;
          if (e is FirebaseException && e.code == 'permission-denied' || e.toString().contains('permission-denied')) {
            _status = SyncStatus.firestorePermissionDenied;
            notifyListeners();
            return syncedCount;
          }
          // Halt batch on failure to allow clean retry without data loss
          break;
        }
      }

      _lastSyncedCount = syncedCount;
      if (hasPartialFailure) {
        _status = SyncStatus.syncError;
      } else {
        _status = SyncStatus.connected;
      }
      notifyListeners();
      return syncedCount;
    } catch (e) {
      debugPrint('[SyncService] Fatal sync loop error: $e');
      _lastError = e.toString();
      _status = SyncStatus.syncError;
      notifyListeners();
      return 0;
    }
  }

  /// Manually triggers a sync attempt (for testing and user pull-to-refresh).
  Future<int> manualSync() async {
    return await checkConnectivityAndSync();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
