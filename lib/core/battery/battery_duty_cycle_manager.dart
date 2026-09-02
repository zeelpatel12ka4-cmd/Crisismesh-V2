import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../database/database_service.dart';

/// Exact battery tiers specified in Crisis Mesh Master Specification
enum BatteryTier {
  /// Battery > 50% -> 10s scan, 45s sleep (~18% duty cycle)
  high,

  /// Battery 30%–50% -> 7s scan, 60s sleep (~10% duty cycle)
  medium,

  /// Battery < 30% -> 5s scan, 100s sleep (~5% duty cycle)
  low,

  /// Pending SOS in queue -> 10s scan, 45s sleep (temporary emergency override up to 5 min)
  emergencyOverride,
}

/// Duty cycle configuration parameters for a specific tier
class DutyCycleConfig {
  final BatteryTier tier;
  final Duration scanDuration;
  final Duration sleepDuration;
  final bool isEmergencyOverride;
  final int batteryPercentage;

  const DutyCycleConfig({
    required this.tier,
    required this.scanDuration,
    required this.sleepDuration,
    required this.isEmergencyOverride,
    required this.batteryPercentage,
  });

  /// Approximate duty cycle ratio (scan / (scan + sleep)) as percentage
  double get dutyCyclePercentage {
    final totalSec = scanDuration.inSeconds + sleepDuration.inSeconds;
    if (totalSec == 0) return 100.0;
    return (scanDuration.inSeconds / totalSec) * 100.0;
  }

  String get summary =>
      '${tier.name.toUpperCase()} (${scanDuration.inSeconds}s scan / ${sleepDuration.inSeconds}s sleep • ${dutyCyclePercentage.toStringAsFixed(0)}% duty cycle)';
}

/// Centralized controller responsible for calculating and scheduling adaptive battery duty-cycling
class BatteryDutyCycleManager extends ChangeNotifier {
  static final BatteryDutyCycleManager instance = BatteryDutyCycleManager._init();

  BatteryDutyCycleManager._init();

  static const MethodChannel _backgroundChannel = MethodChannel('com.crisismesh.app/background_service');
  static const Duration emergencyOverrideMaxDuration = Duration(minutes: 5);

  int _cachedBatteryLevel = 100;
  int _cachedPendingCount = 0;
  DateTime? _emergencyOverrideStartTime;
  bool _isRunning = false;
  bool _isScanning = false;
  Completer<void>? _activeSleepCompleter;

  // Test injection hooks
  Future<int> Function()? batteryLevelProvider;
  Future<int> Function()? pendingCountProvider;
  DateTime Function() nowProvider = DateTime.now;
  Future<void> Function(Duration duration)? customSleepFunction;

  int get batteryLevel => _cachedBatteryLevel;
  int get pendingCount => _cachedPendingCount;
  bool get isRunning => _isRunning;
  bool get isScanning => _isScanning;
  bool get isEmergencyOverrideActive => _emergencyOverrideStartTime != null;

  DutyCycleConfig get currentConfig => calculateConfig(
        batteryLevel: _cachedBatteryLevel,
        pendingCount: _cachedPendingCount,
        now: nowProvider(),
      );

  /// Pure calculation of duty cycle tier based on battery percentage, pending queue, and timestamp
  DutyCycleConfig calculateConfig({
    required int batteryLevel,
    required int pendingCount,
    DateTime? now,
  }) {
    final currentTime = now ?? nowProvider();

    // Check emergency override condition (at least 1 pending SOS message in queue)
    if (pendingCount > 0) {
      _emergencyOverrideStartTime ??= currentTime;

      final elapsed = currentTime.difference(_emergencyOverrideStartTime!);
      if (elapsed < emergencyOverrideMaxDuration) {
        // Active emergency override: 10s scan / 45s sleep (same as high tier)
        return DutyCycleConfig(
          tier: BatteryTier.emergencyOverride,
          scanDuration: const Duration(seconds: 10),
          sleepDuration: const Duration(seconds: 45),
          isEmergencyOverride: true,
          batteryPercentage: batteryLevel,
        );
      } else {
        // 5-minute override expired; fall back to normal battery tier
        debugPrint('[BatteryManager] 5-minute emergency override expired. Returning to normal battery tier.');
      }
    } else {
      // Pending queue is empty; reset override timer immediately
      _emergencyOverrideStartTime = null;
    }

    // Normal Battery Tiers based on exact Master Spec thresholds
    if (batteryLevel > 50) {
      // Tier HIGH: > 50% (51%–100%) -> 10s scan / 45s sleep
      return DutyCycleConfig(
        tier: BatteryTier.high,
        scanDuration: const Duration(seconds: 10),
        sleepDuration: const Duration(seconds: 45),
        isEmergencyOverride: false,
        batteryPercentage: batteryLevel,
      );
    } else if (batteryLevel >= 30 && batteryLevel <= 50) {
      // Tier MEDIUM: 30%–50% (30%–50%) -> 7s scan / 60s sleep
      return DutyCycleConfig(
        tier: BatteryTier.medium,
        scanDuration: const Duration(seconds: 7),
        sleepDuration: const Duration(seconds: 60),
        isEmergencyOverride: false,
        batteryPercentage: batteryLevel,
      );
    } else {
      // Tier LOW: < 30% (0%–29%) -> 5s scan / 100s sleep
      return DutyCycleConfig(
        tier: BatteryTier.low,
        scanDuration: const Duration(seconds: 5),
        sleepDuration: const Duration(seconds: 100),
        isEmergencyOverride: false,
        batteryPercentage: batteryLevel,
      );
    }
  }

  /// Refreshes the battery level from native platform or custom provider
  Future<int> refreshBatteryLevel() async {
    try {
      if (batteryLevelProvider != null) {
        _cachedBatteryLevel = await batteryLevelProvider!.call();
      } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final level = await _backgroundChannel.invokeMethod<int>('getBatteryLevel');
        if (level != null && level >= 0 && level <= 100) {
          _cachedBatteryLevel = level;
        }
      }
    } catch (e) {
      debugPrint('[BatteryManager] Could not read battery level: $e (using fallback $_cachedBatteryLevel%)');
    }
    notifyListeners();
    return _cachedBatteryLevel;
  }

  /// Refreshes pending count from SQLite DatabaseService or custom provider
  Future<int> refreshPendingCount() async {
    try {
      if (pendingCountProvider != null) {
        _cachedPendingCount = await pendingCountProvider!.call();
      } else {
        final pending = await DatabaseService.instance.getPendingMeshMessages();
        _cachedPendingCount = pending.length;
      }
    } catch (e) {
      debugPrint('[BatteryManager] Error checking pending messages: $e');
    }
    notifyListeners();
    return _cachedPendingCount;
  }

  /// Notifies the manager that a pending SOS was created or cleared
  void notifyPendingCountChanged(int count) {
    final prevCount = _cachedPendingCount;
    _cachedPendingCount = count;
    if (count > 0 && prevCount == 0) {
      _emergencyOverrideStartTime = nowProvider();
      debugPrint('[BatteryManager] Emergency override triggered by $count pending SOS message(s).');
    } else if (count == 0) {
      _emergencyOverrideStartTime = null;
      debugPrint('[BatteryManager] Pending SOS queue cleared. Returned to normal battery tier.');
    }
    notifyListeners();
  }

  /// Starts the adaptive duty-cycle scheduler loop
  Future<void> startScheduler({
    required Future<void> Function() onScanStart,
    required Future<void> Function() onScanStop,
    required bool Function() isConnected,
  }) async {
    if (_isRunning) {
      debugPrint('[BatteryManager] Duty-cycle scheduler already running.');
      return;
    }

    _isRunning = true;
    notifyListeners();
    debugPrint('[BatteryManager] Adaptive Battery Duty-Cycle Scheduler started.');

    unawaited(_runSchedulerLoop(
      onScanStart: onScanStart,
      onScanStop: onScanStop,
      isConnected: isConnected,
    ));
  }

  /// Main asynchronous scheduling loop
  Future<void> _runSchedulerLoop({
    required Future<void> Function() onScanStart,
    required Future<void> Function() onScanStop,
    required bool Function() isConnected,
  }) async {
    while (_isRunning) {
      await refreshBatteryLevel();
      await refreshPendingCount();

      // If already connected to an active peer, maintain connection and check periodically
      if (isConnected()) {
        _isScanning = false;
        notifyListeners();
        await _interruptibleSleep(const Duration(seconds: 5));
        continue;
      }

      final config = currentConfig;
      debugPrint('[BatteryManager] Starting Scan phase: ${config.summary}');

      // Scan phase
      _isScanning = true;
      notifyListeners();
      try {
        await onScanStart();
      } catch (e) {
        debugPrint('[BatteryManager] Error starting scan: $e');
      }

      await _interruptibleSleep(config.scanDuration);
      if (!_isRunning) break;

      // If peer connected during scan, do not enter sleep phase
      if (isConnected()) {
        _isScanning = false;
        notifyListeners();
        continue;
      }

      // Sleep phase (discovery pause to conserve radio energy)
      debugPrint('[BatteryManager] Entering Sleep phase for ${config.sleepDuration.inSeconds}s');
      _isScanning = false;
      notifyListeners();
      try {
        await onScanStop();
      } catch (e) {
        debugPrint('[BatteryManager] Error stopping scan: $e');
      }

      await _interruptibleSleep(config.sleepDuration);
    }

    _isScanning = false;
    notifyListeners();
    debugPrint('[BatteryManager] Adaptive Battery Duty-Cycle Scheduler loop stopped.');
  }

  /// Sleep helper that can be interrupted immediately when stopScheduler is called
  Future<void> _interruptibleSleep(Duration duration) async {
    if (!_isRunning) return;

    if (customSleepFunction != null) {
      await customSleepFunction!(duration);
      return;
    }

    _activeSleepCompleter = Completer<void>();
    final timer = Timer(duration, () {
      if (_activeSleepCompleter != null && !_activeSleepCompleter!.isCompleted) {
        _activeSleepCompleter!.complete();
      }
    });

    await _activeSleepCompleter!.future;
    timer.cancel();
    _activeSleepCompleter = null;
  }

  /// Clean shutdown of the duty-cycle scheduler
  void stopScheduler() {
    if (!_isRunning) return;

    _isRunning = false;
    _isScanning = false;

    // Wake up any sleeping loop immediately
    if (_activeSleepCompleter != null && !_activeSleepCompleter!.isCompleted) {
      _activeSleepCompleter!.complete();
      _activeSleepCompleter = null;
    }

    notifyListeners();
    debugPrint('[BatteryManager] Adaptive Battery Duty-Cycle Scheduler stopped.');
  }

  /// Reset manager state (useful for tests)
  void resetForTest({
    int batteryLevel = 100,
    int pendingCount = 0,
    DateTime? now,
  }) {
    _isRunning = false;
    _isScanning = false;
    _cachedBatteryLevel = batteryLevel;
    _cachedPendingCount = pendingCount;
    _emergencyOverrideStartTime = pendingCount > 0 ? (now ?? DateTime.now()) : null;
    batteryLevelProvider = null;
    pendingCountProvider = null;
    nowProvider = now != null ? (() => now) : DateTime.now;
    customSleepFunction = null;
    if (_activeSleepCompleter != null && !_activeSleepCompleter!.isCompleted) {
      _activeSleepCompleter!.complete();
      _activeSleepCompleter = null;
    }
  }
}
