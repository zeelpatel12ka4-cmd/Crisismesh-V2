import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app1/ui/sos_screen.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter_app1/core/crypto/crypto_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<Map<String, dynamic>> mockDbMessages = [
    {
      'id': 'msg-1',
      'type': 'broadcast',
      'sender_id': 'DEV-a1b2c3d4',
      'payload': 'Severe structural collapse with 3 victims trapped under concrete beams. Medical trauma kits and heavy rescue extraction urgently required.',
      'need_type': 'trapped',
      'lat': 23.287434,
      'lng': 72.346430,
      'timestamp': DateTime.now().millisecondsSinceEpoch - 360000,
      'hop_count': 0,
      'priority_tier': 'Critical',
      'priority_score': 10,
      'synced': 0,
    },
    {
      'id': 'msg-2',
      'type': 'broadcast',
      'sender_id': 'DEV-e5f6g7h8',
      'payload': 'Urgent medical assistance required. Multiple elderly patients in critical condition.',
      'need_type': 'medical',
      'lat': 23.289100,
      'lng': 72.348200,
      'timestamp': DateTime.now().millisecondsSinceEpoch - 180000,
      'hop_count': 1,
      'priority_tier': 'Urgent',
      'priority_score': 7,
      'synced': 1,
    },
    {
      'id': 'msg-3',
      'type': 'broadcast',
      'sender_id': 'DEV-i9j0k1l2',
      'payload': 'Clean drinking water and blankets needed for community shelter of 40 people.',
      'need_type': 'water',
      'lat': null,
      'lng': null,
      'timestamp': DateTime.now().millisecondsSinceEpoch - 60000,
      'hop_count': 3,
      'priority_tier': 'Needs',
      'priority_score': 4,
      'synced': 0,
    },
  ];

  setUpAll(() async {
    // Set databaseFactory to sqflite plugin's default databaseFactorySqflitePlugin
    databaseFactory = databaseFactorySqflitePlugin;

    // Initialize CryptoService with deterministic test key
    await CryptoService.instance.init(
      customSeed: Uint8List.fromList(List.generate(32, (i) => i + 1)),
    );

    // Set up mock method channels for geolocator, nearby_connections, permission_handler, path_provider
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return '.';
      },
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'isLocationServiceEnabled') return true;
        if (methodCall.method == 'checkPermission') return 3; // whileInUse
        if (methodCall.method == 'getCurrentPosition') {
          return {
            'latitude': 23.287434,
            'longitude': 72.346430,
            'timestamp': 0,
            'altitude': 0.0,
            'accuracy': 1.0,
            'heading': 0.0,
            'speed': 0.0,
            'speed_accuracy': 0.0,
          };
        }
        return null;
      },
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (MethodCall methodCall) async {
        return {
          0: 1, // location: granted
          28: 1, // bluetoothScan: granted
          29: 1, // bluetoothAdvertise: granted
          30: 1, // bluetoothConnect: granted
          31: 1, // nearbyWifiDevices: granted
        };
      },
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('nearby_connections'),
      (MethodCall methodCall) async {
        return true;
      },
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.tekartik.sqflite'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getDatabasesPath') return '/fake/db/path';
        if (methodCall.method == 'openDatabase') return 1;
        if (methodCall.method == 'query') {
          if (methodCall.arguments != null && methodCall.arguments['sql'] != null) {
            final sql = methodCall.arguments['sql'] as String;
            if (sql.contains('seen_message_ids')) {
              return <Map<String, dynamic>>[];
            }
          }
          return mockDbMessages;
        }
        if (methodCall.method == 'insert') return 1;
        if (methodCall.method == 'execute') return null;
        if (methodCall.method == 'closeDatabase') return null;
        return null;
      },
    );
  });

  group('SosScreen Responsive UI Tests', () {
    testWidgets('Renders properly on small 320px phone layout with populated alert feed and ZERO RenderFlex overflow', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: SosScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify core UI elements exist
      expect(find.text('Crisis Mesh'), findsOneWidget);
      expect(find.text('SEND SOS'), findsOneWidget);
      expect(find.text('EMERGENCY PRIORITY'), findsOneWidget);
      expect(find.text('LOCATION STATUS'), findsOneWidget);
      expect(find.text('BROADCAST SOS'), findsOneWidget);
      expect(find.text('LOCAL LOGGED ALERTS'), findsOneWidget);

      // Verify populated alert cards render on 320px without overflow
      expect(find.textContaining('CRITICAL • 10/10'), findsOneWidget);
      expect(find.textContaining('URGENT • 7/10'), findsOneWidget);
      expect(find.textContaining('NEEDS • 4/10'), findsOneWidget);

      // Verify no exceptions were thrown during build/layout
      expect(tester.takeException(), isNull);
    });

    testWidgets('Renders properly on 360px, 390px, and 414px phone layouts with zero overflow', (WidgetTester tester) async {
      for (final width in [360.0, 390.0, 414.0]) {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          const MaterialApp(
            home: SosScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Crisis Mesh'), findsOneWidget);
        expect(find.text('SEND SOS'), findsOneWidget);
        expect(find.text('EMERGENCY PRIORITY'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('Renders two-column layout on tablet layout (>= 720px)', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: SosScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Crisis Mesh'), findsOneWidget);
      expect(find.text('SEND SOS'), findsOneWidget);
      expect(find.text('EMERGENCY PRIORITY'), findsOneWidget);
      expect(find.text('LOCAL LOGGED ALERTS'), findsOneWidget);
      expect(find.textContaining('CRITICAL • 10/10'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Real-time triage calculates keywords and severity when typing in description', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: SosScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Initially score is 1 (Low)
      expect(find.text('Priority 1/10'), findsOneWidget);
      expect(find.text('LOW'), findsOneWidget);

      // Enter critical text
      final inputFinder = find.byType(TextFormField);
      expect(inputFinder, findsOneWidget);

      await tester.enterText(inputFinder, 'Two victims trapped and bleeding heavily in collapsed basement');
      await tester.pumpAndSettle();

      // Score should update to 10 (Critical)
      expect(find.text('Priority 10/10'), findsOneWidget);
      expect(find.text('CRITICAL'), findsOneWidget);
      expect(find.text('trapped'), findsOneWidget);
      expect(find.text('bleeding heavily'), findsOneWidget);
      expect(find.text('collapsed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Demo coordinates toggle updates coordinates display', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: SosScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final demoToggleFinder = find.text('Demo Mode');
      expect(demoToggleFinder, findsOneWidget);

      await tester.ensureVisible(demoToggleFinder);
      await tester.tap(demoToggleFinder);
      await tester.pumpAndSettle();

      expect(find.textContaining('37.774900, -122.419400'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Broadcast SOS validates empty input and shows warning', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: SosScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final broadcastButton = find.text('BROADCAST SOS');
      expect(broadcastButton, findsOneWidget);

      await tester.ensureVisible(broadcastButton);
      await tester.tap(broadcastButton);
      await tester.pump();

      expect(find.text('Please describe the emergency incident.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Broadcast SOS creates message, saves to database, and shows SOS SAVED LOCALLY confirmation', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: SosScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Enter description
      final inputFinder = find.byType(TextFormField);
      await tester.enterText(inputFinder, 'Flash flood surge entering ground floor clinic');
      await tester.pumpAndSettle();

      // Tap broadcast
      final broadcastButton = find.text('BROADCAST SOS');
      await tester.ensureVisible(broadcastButton);
      await tester.tap(broadcastButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify clear feedback stating "SOS SAVED LOCALLY"
      expect(find.textContaining('SOS SAVED LOCALLY'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
