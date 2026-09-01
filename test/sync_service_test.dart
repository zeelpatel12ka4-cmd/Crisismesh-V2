import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app1/core/models/message_model.dart';
import 'package:flutter_app1/core/sync/sync_service.dart';

/// Test mock implementation of [FirestoreSyncProvider] for deterministic in-memory tests.
class MockFirestoreProvider implements FirestoreSyncProvider {
  final Map<String, Map<String, dynamic>> uploadedDocuments = {};
  bool isReachable = true;
  String? failOnDocId;
  int uploadCallCount = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> checkFirestoreReachability() async {
    return isReachable;
  }

  @override
  Future<void> uploadSosReport(String docId, Map<String, dynamic> data) async {
    uploadCallCount++;
    if (failOnDocId != null && docId == failOnDocId) {
      throw Exception('Simulated network timeout/failure on doc: $docId');
    }
    uploadedDocuments[docId] = data;
  }
}

void main() {
  group('Phase 3: Hybrid Transport & Cloud Bridge Synchronization Tests', () {
    late MockFirestoreProvider mockProvider;
    late MessageModel unsyncedMessage1;
    late MessageModel unsyncedMessage2;
    late MessageModel alreadySyncedMessage;

    setUp(() {
      mockProvider = MockFirestoreProvider();

      unsyncedMessage1 = MessageModel(
        id: 'uuid-sos-001',
        type: 'broadcast',
        senderId: 'DEV-VICTIM-1',
        needType: 'medical',
        payload: 'Cardiac patient needs defibrillator',
        lat: 23.2874,
        lng: 72.3464,
        timestamp: 1700000000000,
        hopCount: 2,
        priorityTier: 'Critical',
        priorityScore: 9,
        synced: false,
      );

      unsyncedMessage2 = MessageModel(
        id: 'uuid-sos-002',
        type: 'broadcast',
        senderId: 'DEV-VICTIM-2',
        needType: 'trapped',
        payload: 'Two persons trapped under debris',
        lat: 23.2885,
        lng: 72.3475,
        timestamp: 1700000005000,
        hopCount: 1,
        priorityTier: 'Critical',
        priorityScore: 10,
        synced: false,
      );

      alreadySyncedMessage = MessageModel(
        id: 'uuid-sos-003',
        type: 'broadcast',
        senderId: 'DEV-VICTIM-3',
        needType: 'water',
        payload: 'Drinking water required at shelter',
        lat: 23.2890,
        lng: 72.3480,
        timestamp: 1700000010000,
        hopCount: 0,
        priorityTier: 'Needs',
        priorityScore: 4,
        synced: true,
      );
    });

    test('1. Unsynced filtering: Identifies only synced = 0 messages for sync batch', () {
      final allMessages = [unsyncedMessage1, unsyncedMessage2, alreadySyncedMessage];

      final unsyncedBatch = allMessages.where((m) => !m.synced).toList();

      expect(unsyncedBatch.length, equals(2));
      expect(unsyncedBatch.map((m) => m.id), contains('uuid-sos-001'));
      expect(unsyncedBatch.map((m) => m.id), contains('uuid-sos-002'));
      expect(unsyncedBatch.map((m) => m.id), isNot(contains('uuid-sos-003')));
    });

    test('2. Successful sync: Uploads to Firestore and produces valid cloud payload', () async {
      final firestoreData = unsyncedMessage1.toFirestoreMap(bridgeDeviceId: 'DEV-BRIDGE-PHONE-C');

      await mockProvider.uploadSosReport(unsyncedMessage1.id, firestoreData);

      expect(mockProvider.uploadedDocuments.containsKey('uuid-sos-001'), isTrue);
      final uploadedDoc = mockProvider.uploadedDocuments['uuid-sos-001']!;

      expect(uploadedDoc['id'], equals('uuid-sos-001'));
      expect(uploadedDoc['sender_id'], equals('DEV-VICTIM-1'));
      expect(uploadedDoc['need_type'], equals('medical'));
      expect(uploadedDoc['hop_count'], equals(2));
      expect(uploadedDoc['bridge_device_id'], equals('DEV-BRIDGE-PHONE-C'));
      expect(uploadedDoc['synced'], isTrue);
    });

    test('3. Marking synced only after success: Unsuccessful uploads remain unsynced = 0', () async {
      mockProvider.failOnDocId = 'uuid-sos-001';

      bool uploadSucceeded = false;
      var localMessage = unsyncedMessage1;

      try {
        await mockProvider.uploadSosReport(
          localMessage.id,
          localMessage.toFirestoreMap(bridgeDeviceId: 'BRIDGE-1'),
        );
        localMessage = localMessage.copyWith(synced: true);
        uploadSucceeded = true;
      } catch (e) {
        uploadSucceeded = false;
        // Keep synced as false
      }

      expect(uploadSucceeded, isFalse);
      expect(localMessage.synced, isFalse, reason: 'Message must remain unsynced on upload failure');
      expect(mockProvider.uploadedDocuments.containsKey('uuid-sos-001'), isFalse);
    });

    test('4. Deterministic Firestore document ID: Document ID exactly matches MessageModel.id', () async {
      final testId = 'uuid-exact-origin-98765';
      final testMessage = unsyncedMessage1.copyWith(id: testId);

      await mockProvider.uploadSosReport(
        testMessage.id,
        testMessage.toFirestoreMap(bridgeDeviceId: 'BRIDGE-TEST'),
      );

      // Verify the map key is the exact UUID
      expect(mockProvider.uploadedDocuments.keys.first, equals(testId));
      expect(mockProvider.uploadedDocuments[testId]!['id'], equals(testId));
    });

    test('5. Duplicate bridge handling: Multiple bridge uploads target the exact same document ID', () async {
      // Bridge Phone C encounters the message and uploads to Firestore
      final uploadFromBridgeC = unsyncedMessage1.toFirestoreMap(bridgeDeviceId: 'BRIDGE-PHONE-C');
      await mockProvider.uploadSosReport(unsyncedMessage1.id, uploadFromBridgeC);

      expect(mockProvider.uploadedDocuments.length, equals(1));
      expect(mockProvider.uploadedDocuments['uuid-sos-001']!['bridge_device_id'], equals('BRIDGE-PHONE-C'));

      // Bridge Phone D later encounters the same message and uploads to Firestore
      final uploadFromBridgeD = unsyncedMessage1.toFirestoreMap(bridgeDeviceId: 'BRIDGE-PHONE-D');
      await mockProvider.uploadSosReport(unsyncedMessage1.id, uploadFromBridgeD);

      // Total documents must remain 1 (no duplicate document created)
      expect(mockProvider.uploadedDocuments.length, equals(1));
      expect(mockProvider.uploadedDocuments['uuid-sos-001']!['bridge_device_id'], equals('BRIDGE-PHONE-D'));
    });

    test('6. Partial sync failure: Halts batch on error, marks only successful items', () async {
      final batch = [unsyncedMessage1, unsyncedMessage2];
      // Message 2 fails (e.g. connectivity lost mid-batch)
      mockProvider.failOnDocId = 'uuid-sos-002';

      final syncedResults = <String>[];
      final unsyncedResults = <String>[];

      for (final msg in batch) {
        try {
          await mockProvider.uploadSosReport(
            msg.id,
            msg.toFirestoreMap(bridgeDeviceId: 'BRIDGE-C'),
          );
          syncedResults.add(msg.id);
        } catch (e) {
          unsyncedResults.add(msg.id);
          break; // Stop batch on failure
        }
      }

      expect(syncedResults, contains('uuid-sos-001'));
      expect(syncedResults.length, equals(1));
      expect(unsyncedResults, contains('uuid-sos-002'));
      expect(mockProvider.uploadedDocuments.containsKey('uuid-sos-001'), isTrue);
      expect(mockProvider.uploadedDocuments.containsKey('uuid-sos-002'), isFalse);
    });
  });
}
