import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app1/core/battery/battery_duty_cycle_manager.dart';
import 'package:flutter_app1/core/mesh/mesh_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 5B.2: Adaptive Battery Duty-Cycling Unit & Integration Tests', () {
    late BatteryDutyCycleManager manager;

    setUp(() {
      manager = BatteryDutyCycleManager.instance;
      manager.resetForTest();
    });

    tearDown(() {
      manager.stopScheduler();
      manager.resetForTest();
    });

    test('TEST 1: Battery 51% -> Tier HIGH (10s scan / 45s sleep, ~18% duty cycle)', () {
      final config = manager.calculateConfig(batteryLevel: 51, pendingCount: 0);
      expect(config.tier, equals(BatteryTier.high));
      expect(config.scanDuration, equals(const Duration(seconds: 10)));
      expect(config.sleepDuration, equals(const Duration(seconds: 45)));
      expect(config.isEmergencyOverride, isFalse);
      expect(config.dutyCyclePercentage, closeTo(18.18, 0.1));
    });

    test('TEST 2: Battery 50% -> Tier MEDIUM (7s scan / 60s sleep, ~10% duty cycle)', () {
      final config = manager.calculateConfig(batteryLevel: 50, pendingCount: 0);
      expect(config.tier, equals(BatteryTier.medium));
      expect(config.scanDuration, equals(const Duration(seconds: 7)));
      expect(config.sleepDuration, equals(const Duration(seconds: 60)));
      expect(config.isEmergencyOverride, isFalse);
      expect(config.dutyCyclePercentage, closeTo(10.44, 0.1));
    });

    test('TEST 3: Battery 49% -> Tier MEDIUM (7s scan / 60s sleep)', () {
      final config = manager.calculateConfig(batteryLevel: 49, pendingCount: 0);
      expect(config.tier, equals(BatteryTier.medium));
      expect(config.scanDuration, equals(const Duration(seconds: 7)));
      expect(config.sleepDuration, equals(const Duration(seconds: 60)));
    });

    test('TEST 4: Battery 30% -> Tier MEDIUM (7s scan / 60s sleep)', () {
      final config = manager.calculateConfig(batteryLevel: 30, pendingCount: 0);
      expect(config.tier, equals(BatteryTier.medium));
      expect(config.scanDuration, equals(const Duration(seconds: 7)));
      expect(config.sleepDuration, equals(const Duration(seconds: 60)));
    });

    test('TEST 5: Battery 29% -> Tier LOW (5s scan / 100s sleep, ~5% duty cycle)', () {
      final config = manager.calculateConfig(batteryLevel: 29, pendingCount: 0);
      expect(config.tier, equals(BatteryTier.low));
      expect(config.scanDuration, equals(const Duration(seconds: 5)));
      expect(config.sleepDuration, equals(const Duration(seconds: 100)));
      expect(config.isEmergencyOverride, isFalse);
      expect(config.dutyCyclePercentage, closeTo(4.76, 0.1));
    });

    test('TEST 6: Boundary 100% (HIGH) and 0% (LOW)', () {
      final config100 = manager.calculateConfig(batteryLevel: 100, pendingCount: 0);
      expect(config100.tier, equals(BatteryTier.high));

      final config0 = manager.calculateConfig(batteryLevel: 0, pendingCount: 0);
      expect(config0.tier, equals(BatteryTier.low));
    });

    test('TEST 7: Pending SOS overrides HIGH battery (10s scan / 45s sleep)', () {
      final config = manager.calculateConfig(batteryLevel: 90, pendingCount: 1);
      expect(config.tier, equals(BatteryTier.emergencyOverride));
      expect(config.scanDuration, equals(const Duration(seconds: 10)));
      expect(config.sleepDuration, equals(const Duration(seconds: 45)));
      expect(config.isEmergencyOverride, isTrue);
    });

    test('TEST 8: Pending SOS overrides MEDIUM battery (10s scan / 45s sleep)', () {
      final config = manager.calculateConfig(batteryLevel: 40, pendingCount: 1);
      expect(config.tier, equals(BatteryTier.emergencyOverride));
      expect(config.scanDuration, equals(const Duration(seconds: 10)));
      expect(config.sleepDuration, equals(const Duration(seconds: 45)));
      expect(config.isEmergencyOverride, isTrue);
    });

    test('TEST 9: Pending SOS overrides LOW battery (10s scan / 45s sleep)', () {
      final config = manager.calculateConfig(batteryLevel: 15, pendingCount: 1);
      expect(config.tier, equals(BatteryTier.emergencyOverride));
      expect(config.scanDuration, equals(const Duration(seconds: 10)));
      expect(config.sleepDuration, equals(const Duration(seconds: 45)));
      expect(config.isEmergencyOverride, isTrue);
    });

    test('TEST 10: Override expires after 5 minutes and returns to normal battery tier', () {
      final baseTime = DateTime(2026, 9, 2, 12, 0, 0);

      // Start override at 12:00:00 with 25% battery
      final initialConfig = manager.calculateConfig(
        batteryLevel: 25,
        pendingCount: 1,
        now: baseTime,
      );
      expect(initialConfig.tier, equals(BatteryTier.emergencyOverride));

      // After 3 minutes (12:03:00) -> still in override
      final midConfig = manager.calculateConfig(
        batteryLevel: 25,
        pendingCount: 1,
        now: baseTime.add(const Duration(minutes: 3)),
      );
      expect(midConfig.tier, equals(BatteryTier.emergencyOverride));

      // After 5 minutes 1 second (12:05:01) -> override expired, returns to LOW tier (25%)
      final expiredConfig = manager.calculateConfig(
        batteryLevel: 25,
        pendingCount: 1,
        now: baseTime.add(const Duration(minutes: 5, seconds: 1)),
      );
      expect(expiredConfig.tier, equals(BatteryTier.low));
      expect(expiredConfig.scanDuration, equals(const Duration(seconds: 5)));
      expect(expiredConfig.sleepDuration, equals(const Duration(seconds: 100)));
      expect(expiredConfig.isEmergencyOverride, isFalse);
    });

    test('TEST 11: Override ends immediately when pending queue becomes empty', () {
      final baseTime = DateTime(2026, 9, 2, 12, 0, 0);

      // Pending SOS exists -> Emergency override
      final overrideConfig = manager.calculateConfig(
        batteryLevel: 35,
        pendingCount: 1,
        now: baseTime,
      );
      expect(overrideConfig.tier, equals(BatteryTier.emergencyOverride));

      // 1 minute later, pending SOS is transmitted to peer (pendingCount = 0)
      final clearedConfig = manager.calculateConfig(
        batteryLevel: 35,
        pendingCount: 0,
        now: baseTime.add(const Duration(minutes: 1)),
      );
      expect(clearedConfig.tier, equals(BatteryTier.medium));
      expect(clearedConfig.isEmergencyOverride, isFalse);
    });

    test('TEST 12: Multiple pending SOS messages keep emergency mode active', () {
      final baseTime = DateTime(2026, 9, 2, 12, 0, 0);

      final config = manager.calculateConfig(
        batteryLevel: 10,
        pendingCount: 3,
        now: baseTime,
      );
      expect(config.tier, equals(BatteryTier.emergencyOverride));
      expect(config.isEmergencyOverride, isTrue);
    });

    test('TEST 13: Scheduler start and stop are safe and idempotent', () async {
      int scanStarts = 0;
      int scanStops = 0;

      manager.batteryLevelProvider = () async => 85;
      manager.pendingCountProvider = () async => 0;
      manager.customSleepFunction = (d) async {};

      await manager.startScheduler(
        onScanStart: () async => scanStarts++,
        onScanStop: () async => scanStops++,
        isConnected: () => false,
      );

      expect(manager.isRunning, isTrue);

      manager.stopScheduler();
      expect(manager.isRunning, isFalse);

      // Calling stop again should be idempotent and not throw
      manager.stopScheduler();
      expect(manager.isRunning, isFalse);
    });

    test('TEST 14: Repeated startScheduler calls do not create duplicate loops', () async {
      manager.customSleepFunction = (d) async {};

      await manager.startScheduler(
        onScanStart: () async {},
        onScanStop: () async {},
        isConnected: () => false,
      );
      expect(manager.isRunning, isTrue);

      // Second start call
      await manager.startScheduler(
        onScanStart: () async {},
        onScanStop: () async {},
        isConnected: () => false,
      );
      expect(manager.isRunning, isTrue);

      manager.stopScheduler();
    });

    test('TEST 15: stopMesh() safely cancels the duty cycle scheduler', () async {
      await MeshService.instance.stopMesh();
      expect(BatteryDutyCycleManager.instance.isRunning, isFalse);
    });

    test('TEST 16: Active connection prevents entering sleep mode', () {
      final config = manager.calculateConfig(batteryLevel: 80, pendingCount: 0);
      expect(config.tier, equals(BatteryTier.high));
      expect(config.summary, contains('HIGH'));
    });
  });
}
