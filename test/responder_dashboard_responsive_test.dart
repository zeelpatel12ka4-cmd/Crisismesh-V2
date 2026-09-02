import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app1/core/models/incident_model.dart';
import 'package:flutter_app1/core/services/responder_service.dart';
import 'package:flutter_app1/ui/responder/responder_auth_dialog.dart';
import 'package:flutter_app1/ui/responder/responder_dashboard_screen.dart';
import 'package:flutter_app1/ui/responder/widgets/incident_card.dart';
import 'package:flutter_app1/ui/responder/widgets/incident_details_panel.dart';
import 'package:flutter_app1/ui/responder/widgets/incident_queue_list.dart';
import 'package:flutter_app1/ui/responder/widgets/kpi_summary_cards.dart';
import 'package:flutter_app1/ui/responder/widgets/live_incident_map.dart';
import 'package:flutter_app1/ui/responder/widgets/responder_header.dart';
import 'responder_service_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockResponderDataProvider mockProvider;
  late IncidentModel mockIncident1;
  late IncidentModel mockIncident2;

  setUp(() {
    mockProvider = MockResponderDataProvider();

    mockIncident1 = IncidentModel(
      id: 'inc-test-001',
      senderId: 'DEV-TEST-1',
      needType: 'trapped',
      payload: '3 persons trapped in basement with rising water',
      lat: 23.287434,
      lng: 72.346430,
      timestamp: DateTime.now().millisecondsSinceEpoch - 120000,
      hopCount: 2,
      priorityTier: 'Critical',
      priorityScore: 10,
      status: IncidentStatus.open,
    );

    mockIncident2 = IncidentModel(
      id: 'inc-test-002',
      senderId: 'DEV-TEST-2',
      needType: 'medical',
      payload: 'Oxygen tank needed for asthmatic victim',
      lat: 23.289000,
      lng: 72.348000,
      timestamp: DateTime.now().millisecondsSinceEpoch - 60000,
      hopCount: 0,
      priorityTier: 'Urgent',
      priorityScore: 7,
      status: IncidentStatus.assigned,
      assignedTo: 'Medic-Alpha',
    );

    mockProvider.initialIncidents = [mockIncident1, mockIncident2];
  });

  tearDown(() {
    mockProvider.dispose();
    ResponderAuthSession.instance.logout();
  });

  Widget createTestWidget({
    required Size screenSize,
    bool preAuthenticate = true,
  }) {
    if (preAuthenticate) {
      ResponderAuthSession.instance.login(
        callSign: 'Commander Alpha',
        role: 'Incident Commander',
        sector: 'Sector North (HQ)',
        pin: 'CRISIS2026',
      );
    } else {
      ResponderAuthSession.instance.logout();
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MediaQuery(
        data: MediaQueryData(size: screenSize),
        child: SizedBox(
          width: screenSize.width,
          height: screenSize.height,
          child: ResponderDashboardScreen(customProvider: mockProvider),
        ),
      ),
    );
  }

  testWidgets('1. Unauthenticated state displays Responder Authorization Gate', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(createTestWidget(screenSize: const Size(1200, 800), preAuthenticate: false));
    await tester.pump();

    // Verify Auth Screen is shown
    expect(find.byType(ResponderAuthScreen), findsOneWidget);
    expect(find.text('Crisis Mesh Command'), findsOneWidget);
    expect(find.text('Responder Authorization Gate'), findsOneWidget);
    expect(find.text('Authorize & Launch Command Center'), findsOneWidget);

    // Dashboard widgets should not be visible yet
    expect(find.byType(ResponderHeader), findsNothing);
  });

  testWidgets('2. Authenticating unlocks full command center dashboard', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(createTestWidget(screenSize: const Size(1200, 800), preAuthenticate: false));
    await tester.pump();

    // Tap Authorize Button (default pre-filled fields)
    await tester.tap(find.text('Authorize & Launch Command Center'));
    await tester.pump(const Duration(milliseconds: 200));

    // Verify Dashboard rendered
    expect(find.byType(ResponderHeader), findsOneWidget);
    expect(find.byType(KpiSummaryCards), findsOneWidget);
    expect(find.text('CRISIS MESH'), findsOneWidget);
    expect(find.text('Commander Alpha'), findsOneWidget);
  });

  testWidgets('3. Desktop Layout (1440x900): 3-Column split view with Queue, Map, and Dossier', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(createTestWidget(screenSize: const Size(1440, 900)));
    await tester.pump(const Duration(milliseconds: 200));

    // Verify Header & KPI summary cards
    expect(find.byType(ResponderHeader), findsOneWidget);
    expect(find.byType(KpiSummaryCards), findsOneWidget);
    expect(find.text('CRITICAL'), findsOneWidget);
    expect(find.text('URGENT'), findsOneWidget);
    expect(find.text('NEEDS'), findsOneWidget);

    // Verify 3 Columns
    expect(find.byType(IncidentQueueList), findsOneWidget);
    expect(find.byType(LiveIncidentMap), findsOneWidget);
    expect(find.byType(IncidentDetailsPanel), findsOneWidget);

    // Verify Incidents rendered in the queue
    expect(find.byType(IncidentCard), findsNWidgets(2));
    expect(find.textContaining('3 persons trapped'), findsOneWidget);
  });

  testWidgets('4. Tablet Layout (800x1024): 2-Column split view with Tabbed Map/Dossier', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1024));
    await tester.pumpWidget(createTestWidget(screenSize: const Size(800, 1024)));
    await tester.pump(const Duration(milliseconds: 200));

    // Verify Queue List is present
    expect(find.byType(IncidentQueueList), findsOneWidget);

    // Verify Tablet Tab Switchers
    expect(find.text('🗺️ Live Map'), findsOneWidget);
    expect(find.text('📋 Incident Dossier'), findsOneWidget);
    expect(find.byType(LiveIncidentMap), findsOneWidget);

    // Switch to Dossier Tab
    await tester.tap(find.text('📋 Incident Dossier'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(IncidentDetailsPanel), findsOneWidget);
  });

  testWidgets('5. Mobile Layout (390x844): Single-Column with Navigation Tabs', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(createTestWidget(screenSize: const Size(390, 844)));
    await tester.pump(const Duration(milliseconds: 200));

    // Verify Mobile Navigation Tabs
    expect(find.text('Queue'), findsOneWidget);
    expect(find.text('Live Map'), findsOneWidget);
    expect(find.text('Dossier'), findsOneWidget);

    // Queue tab active initially
    expect(find.byType(IncidentQueueList), findsOneWidget);
    expect(find.byType(IncidentCard), findsNWidgets(2));

    // Switch to Live Map tab
    await tester.tap(find.text('Live Map'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(LiveIncidentMap), findsOneWidget);

    // Switch to Dossier tab
    await tester.tap(find.text('Dossier'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(IncidentDetailsPanel), findsOneWidget);
  });

  testWidgets('6. Incident Selection and Status Workflow Interaction', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(createTestWidget(screenSize: const Size(1440, 900)));
    await tester.pump(const Duration(milliseconds: 200));

    // Tap on the first incident card in the queue
    await tester.tap(find.textContaining('3 persons trapped'));
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Details panel shows selected incident details
    expect(find.textContaining('SOS Report ID: inc-test-001'), findsOneWidget);
    expect(find.text('EMERGENCY SITUATION REPORT'), findsOneWidget);
    expect(find.text('Automated Triage Analysis'), findsOneWidget);
    expect(find.text('Assign Response Unit'), findsOneWidget);

    // Tap Assign Response Unit button
    await tester.tap(find.text('Assign Response Unit'));
    await tester.pump(const Duration(milliseconds: 100));

    // Verify provider received the assignment
    expect(mockProvider.recordedUpdates.containsKey('inc-test-001'), isTrue);
    expect(mockProvider.recordedUpdates['inc-test-001']!['status'], equals(IncidentStatus.assigned));
  });
}
