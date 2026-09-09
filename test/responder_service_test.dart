import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app1/core/models/incident_model.dart';
import 'package:flutter_app1/core/services/responder_service.dart';

class MockResponderDataProvider implements ResponderDataProvider {
  final StreamController<List<IncidentModel>> _controller = StreamController<List<IncidentModel>>.broadcast();
  final Map<String, Map<String, dynamic>> recordedUpdates = {};
  List<IncidentModel> initialIncidents = [];

  @override
  Future<void> initialize() async {}

  @override
  Stream<List<IncidentModel>> getIncidentsStream() async* {
    if (initialIncidents.isNotEmpty) {
      yield initialIncidents;
    }
    yield* _controller.stream;
  }

  void emitIncidents(List<IncidentModel> incidents) {
    initialIncidents = incidents;
    _controller.add(incidents);
  }

  @override
  Future<void> updateIncidentStatus({
    required String incidentId,
    required String status,
    required String responderId,
    String? notes,
  }) async {
    recordedUpdates[incidentId] = {
      'status': status,
      'responderId': responderId,
      'notes': notes,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  void dispose() {
    _controller.close();
  }
}

void main() {
  group('Phase 4: ResponderService & State Tests', () {
    late MockResponderDataProvider mockProvider;
    late IncidentModel incCritical1;
    late IncidentModel incCritical2;
    late IncidentModel incUrgent;
    late IncidentModel incNeeds;
    late IncidentModel incResolved;

    setUp(() {
      mockProvider = MockResponderDataProvider();

      // Reset singleton state
      final service = ResponderService.instance;
      service.setStatusFilter('Active');
      service.setTierFilter('All');
      service.setCategoryFilter('All');
      service.setSearchQuery('');

      incCritical1 = IncidentModel(
        id: 'inc-crit-1',
        senderId: 'DEV-VICTIM-1',
        needType: 'trapped',
        payload: 'Two persons trapped under concrete beam',
        lat: 23.2874,
        lng: 72.3464,
        timestamp: 1000,
        hopCount: 2,
        priorityTier: 'Critical',
        priorityScore: 10,
        status: IncidentStatus.open,
      );

      incCritical2 = IncidentModel(
        id: 'inc-crit-2',
        senderId: 'DEV-VICTIM-2',
        needType: 'medical',
        payload: 'Severe bleeding trauma after glass cut',
        lat: 23.2880,
        lng: 72.3470,
        timestamp: 2000,
        hopCount: 1,
        priorityTier: 'Critical',
        priorityScore: 9,
        status: IncidentStatus.open,
      );

      incUrgent = IncidentModel(
        id: 'inc-urg-1',
        senderId: 'DEV-VICTIM-3',
        needType: 'medical',
        payload: 'Elderly patient with broken arm',
        lat: 23.2890,
        lng: 72.3480,
        timestamp: 1500,
        hopCount: 0,
        priorityTier: 'Urgent',
        priorityScore: 7,
        status: IncidentStatus.assigned,
        assignedTo: 'Medic-Alpha',
      );

      incNeeds = IncidentModel(
        id: 'inc-need-1',
        senderId: 'DEV-VICTIM-4',
        needType: 'water',
        payload: 'Clean water bottles needed for 20 children',
        lat: null,
        lng: null,
        timestamp: 500,
        hopCount: 3,
        priorityTier: 'Needs',
        priorityScore: 4,
        status: IncidentStatus.open,
      );

      incResolved = IncidentModel(
        id: 'inc-res-1',
        senderId: 'DEV-VICTIM-5',
        needType: 'food',
        payload: 'Emergency food rations delivered',
        lat: 23.2850,
        lng: 72.3450,
        timestamp: 3000,
        hopCount: 0,
        priorityTier: 'Needs',
        priorityScore: 4,
        status: IncidentStatus.resolved,
        assignedTo: 'Logistics-1',
        resolutionNotes: 'Rations successfully distributed.',
      );
    });

    tearDown(() {
      mockProvider.dispose();
    });

    test('1. KPI Metric calculations: Active, Critical, Urgent, Needs, Resolved totals', () {
      final service = ResponderService.instance;
      service.setIncidentsDirectly([
        incCritical1,
        incCritical2,
        incUrgent,
        incNeeds,
        incResolved,
      ]);

      expect(service.totalCount, equals(5));
      expect(service.totalActiveCount, equals(4)); // all except resolved
      expect(service.criticalCount, equals(2));
      expect(service.urgentCount, equals(1));
      expect(service.needsCount, equals(1)); // active needs (incResolved is resolved)
      expect(service.resolvedCount, equals(1));
    });

    test('2. Priority Queue Sorting: Active before Resolved, Score 10 -> 9 -> 7 -> 4', () {
      final service = ResponderService.instance;
      service.setStatusFilter('All');
      service.setTierFilter('All');
      service.setCategoryFilter('All');
      service.setSearchQuery('');

      service.setIncidentsDirectly([
        incNeeds,
        incResolved,
        incCritical2,
        incUrgent,
        incCritical1,
      ]);

      final sorted = service.filteredIncidents;

      // Active Critical score 10 first
      expect(sorted[0].id, equals('inc-crit-1'));
      expect(sorted[0].priorityScore, equals(10));

      // Active Critical score 9 second
      expect(sorted[1].id, equals('inc-crit-2'));
      expect(sorted[1].priorityScore, equals(9));

      // Active Urgent score 7 third
      expect(sorted[2].id, equals('inc-urg-1'));
      expect(sorted[2].priorityScore, equals(7));

      // Active Needs score 4 fourth
      expect(sorted[3].id, equals('inc-need-1'));
      expect(sorted[3].priorityScore, equals(4));

      // Resolved last
      expect(sorted[4].id, equals('inc-res-1'));
      expect(sorted[4].isResolved, isTrue);
    });

    test('3. Tier Filtering: Filters exclusively for Critical, Urgent, or Needs', () {
      final service = ResponderService.instance;
      service.setStatusFilter('Active');
      service.setCategoryFilter('All');
      service.setSearchQuery('');

      service.setIncidentsDirectly([
        incCritical1,
        incCritical2,
        incUrgent,
        incNeeds,
        incResolved,
      ]);

      service.setTierFilter('Critical');
      expect(service.filteredIncidents.length, equals(2));
      expect(service.filteredIncidents.every((i) => i.isCritical), isTrue);

      service.setTierFilter('Urgent');
      expect(service.filteredIncidents.length, equals(1));
      expect(service.filteredIncidents.first.id, equals('inc-urg-1'));

      service.setTierFilter('Needs');
      expect(service.filteredIncidents.length, equals(1)); // only active needs
      expect(service.filteredIncidents.first.id, equals('inc-need-1'));

      // If Status filter is 'All', both active and resolved needs are included
      service.setStatusFilter('All');
      expect(service.filteredIncidents.length, equals(2));
    });

    test('4. Status Filtering: Filters Active, Open, Assigned, En Route, Resolved', () {
      final service = ResponderService.instance;
      service.setIncidentsDirectly([
        incCritical1,
        incCritical2,
        incUrgent,
        incNeeds,
        incResolved,
      ]);

      service.setTierFilter('All');
      service.setStatusFilter('open');
      expect(service.filteredIncidents.length, equals(3)); // incCritical1, incCritical2, incNeeds

      service.setStatusFilter('assigned');
      expect(service.filteredIncidents.length, equals(1));
      expect(service.filteredIncidents.first.id, equals('inc-urg-1'));

      service.setStatusFilter('resolved');
      expect(service.filteredIncidents.length, equals(1));
      expect(service.filteredIncidents.first.id, equals('inc-res-1'));
    });

    test('5. Multi-Keyword Search Query Filtering', () {
      final service = ResponderService.instance;
      service.setIncidentsDirectly([
        incCritical1,
        incCritical2,
        incUrgent,
        incNeeds,
        incResolved,
      ]);

      service.setTierFilter('All');
      service.setStatusFilter('Active');

      // Search keyword 'concrete'
      service.setSearchQuery('concrete');
      expect(service.filteredIncidents.length, equals(1));
      expect(service.filteredIncidents.first.id, equals('inc-crit-1'));

      // Search category 'medical'
      service.setSearchQuery('medical');
      expect(service.filteredIncidents.length, equals(2)); // incCritical2 and incUrgent

      // Search victim sender 'DEV-VICTIM-4'
      service.setSearchQuery('DEV-VICTIM-4');
      expect(service.filteredIncidents.length, equals(1));
      expect(service.filteredIncidents.first.id, equals('inc-need-1'));
    });

    test('6. Status Transition Mutations: Assign -> En Route -> Resolve', () async {
      final service = ResponderService.instance;
      service.setProvider(mockProvider);
      service.setIncidentsDirectly([incCritical1]);

      // 1. Assign
      await service.assignIncident(
        incidentId: 'inc-crit-1',
        responderId: 'Commander-Alpha',
      );

      expect(mockProvider.recordedUpdates.containsKey('inc-crit-1'), isTrue);
      expect(mockProvider.recordedUpdates['inc-crit-1']!['status'], equals('assigned'));
      expect(mockProvider.recordedUpdates['inc-crit-1']!['responderId'], equals('Commander-Alpha'));
      expect(service.allIncidents.first.status, equals(IncidentStatus.assigned));
      expect(service.allIncidents.first.assignedTo, equals('Commander-Alpha'));

      // 2. En Route
      await service.markEnRoute(
        incidentId: 'inc-crit-1',
        responderId: 'Commander-Alpha',
      );

      expect(mockProvider.recordedUpdates['inc-crit-1']!['status'], equals('en_route'));
      expect(service.allIncidents.first.status, equals(IncidentStatus.enRoute));

      // 3. Resolve
      await service.resolveIncident(
        incidentId: 'inc-crit-1',
        responderId: 'Commander-Alpha',
        notes: 'Victims successfully rescued.',
      );

      expect(mockProvider.recordedUpdates['inc-crit-1']!['status'], equals('resolved'));
      expect(mockProvider.recordedUpdates['inc-crit-1']!['notes'], equals('Victims successfully rescued.'));
      expect(service.allIncidents.first.status, equals(IncidentStatus.resolved));
      expect(service.allIncidents.first.resolutionNotes, equals('Victims successfully rescued.'));
    });

    test('7. Responder Authorization Session Security', () {
      final auth = ResponderAuthSession.instance;
      auth.logout();
      expect(auth.isAuthenticated, isFalse);

      // Attempt invalid PIN
      final failLogin = auth.login(
        callSign: 'Unknown Agent',
        role: 'Triage',
        sector: 'Sector 1',
        pin: 'WRONG_PIN_123',
      );
      expect(failLogin, isFalse);
      expect(auth.isAuthenticated, isFalse);

      // Successful login with valid crisis pin
      final successLogin = auth.login(
        callSign: 'Commander Bravo',
        role: 'Incident Commander',
        sector: 'Sector North',
        pin: 'CRISIS2026',
      );
      expect(successLogin, isTrue);
      expect(auth.isAuthenticated, isTrue);
      expect(auth.responderCallSign, equals('Commander Bravo'));
      expect(auth.currentProfile?.sector, equals('Sector North'));

      // Logout
      auth.logout();
      expect(auth.isAuthenticated, isFalse);
    });

    test('8. State Distinction: ResponderConnectionState reflects permissionDenied and connected states', () {
      final service = ResponderService.instance;
      service.setIncidentsDirectly([]);

      // Directly set incidents sets connected state
      expect(service.connectionState, equals(ResponderConnectionState.connected));
      expect(service.isConnected, isTrue);
      expect(service.isPermissionDenied, isFalse);
      expect(service.isNetworkOffline, isFalse);
    });
  });
}
