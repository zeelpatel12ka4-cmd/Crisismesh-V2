import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

const String _keySeedStorageKey = 'crisis_mesh_ed25519_seed_v1';
const String _x25519SeedStorageKey = 'crisis_mesh_x25519_seed_v1';

// Configure Android Keystore and iOS Apple Keychain backed storage
const _secureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(
    encryptedSharedPreferences: true,
  ),
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  ),
);

// Fallback in-memory cache for test runners or environments where secure storage is mocked
Uint8List? _inMemorySeedCache;
Uint8List? _inMemoryX25519SeedCache;

/// Saves the 32-byte Ed25519 private seed to platform secure storage (Android Keystore)
Future<void> saveKeySeed(Uint8List seed) async {
  if (seed.length != 32) {
    throw ArgumentError('Ed25519 private key seed must be exactly 32 bytes.');
  }

  _inMemorySeedCache = Uint8List.fromList(seed);

  try {
    final b64 = base64Encode(seed);
    await _secureStorage.write(key: _keySeedStorageKey, value: b64);
  } catch (e) {
    debugPrint('[KeyStorage] Warning: platform secure storage write failed: $e');
  }

  // Ensure legacy file is purged if it exists to avoid plain-text data remanence
  await _purgeLegacySeedFile();
}

/// Loads the 32-byte Ed25519 private seed from platform secure storage, performing a one-time migration if needed
Future<Uint8List?> loadKeySeed() async {
  if (_inMemorySeedCache != null && _inMemorySeedCache!.length == 32) {
    return _inMemorySeedCache;
  }

  // 1. Try reading from platform secure storage (Android Keystore / EncryptedSharedPreferences)
  try {
    final b64 = await _secureStorage.read(key: _keySeedStorageKey);
    if (b64 != null && b64.isNotEmpty) {
      final decoded = base64Decode(b64);
      if (decoded.length == 32) {
        _inMemorySeedCache = Uint8List.fromList(decoded);
        return _inMemorySeedCache;
      }
    }
  } catch (e) {
    debugPrint('[KeyStorage] Warning: platform secure storage read failed: $e');
  }

  // 2. One-time Migration: Check for legacy file-based seed
  final migratedSeed = await _migrateLegacySeedFile();
  if (migratedSeed != null) {
    _inMemorySeedCache = migratedSeed;
    return migratedSeed;
  }

  return null;
}

/// Saves the 32-byte X25519 private seed to platform secure storage
Future<void> saveX25519Seed(Uint8List seed) async {
  if (seed.length != 32) {
    throw ArgumentError('X25519 private key seed must be exactly 32 bytes.');
  }

  _inMemoryX25519SeedCache = Uint8List.fromList(seed);

  try {
    final b64 = base64Encode(seed);
    await _secureStorage.write(key: _x25519SeedStorageKey, value: b64);
  } catch (e) {
    debugPrint('[KeyStorage] Warning: platform secure storage write failed for X25519: $e');
  }
}

/// Loads the 32-byte X25519 private seed from platform secure storage
Future<Uint8List?> loadX25519Seed() async {
  if (_inMemoryX25519SeedCache != null && _inMemoryX25519SeedCache!.length == 32) {
    return _inMemoryX25519SeedCache;
  }

  try {
    final b64 = await _secureStorage.read(key: _x25519SeedStorageKey);
    if (b64 != null && b64.isNotEmpty) {
      final decoded = base64Decode(b64);
      if (decoded.length == 32) {
        _inMemoryX25519SeedCache = Uint8List.fromList(decoded);
        return _inMemoryX25519SeedCache;
      }
    }
  } catch (e) {
    debugPrint('[KeyStorage] Warning: platform secure storage read failed for X25519: $e');
  }

  return null;
}

/// Safely migrates legacy file-based seed to secure storage and securely shreds the old file
Future<Uint8List?> _migrateLegacySeedFile() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/crisis_mesh_key.bin');
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      if (bytes.length == 32) {
        debugPrint('[KeyStorage] Migrating legacy private seed to platform secure storage...');
        try {
          await _secureStorage.write(
            key: _keySeedStorageKey,
            value: base64Encode(bytes),
          );
        } catch (e) {
          debugPrint('[KeyStorage] Could not write migrated seed to secure storage: $e');
        }

        await _purgeLegacySeedFile();
        debugPrint('[KeyStorage] Legacy seed file securely migrated and purged.');
        return Uint8List.fromList(bytes);
      }
    }
  } catch (e) {
    debugPrint('[KeyStorage] Error during legacy seed migration: $e');
  }
  return null;
}

/// Overwrites legacy file with zeros and removes it from disk
Future<void> _purgeLegacySeedFile() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/crisis_mesh_key.bin');
    if (await file.exists()) {
      await file.writeAsBytes(Uint8List(32), flush: true);
      await file.delete();
    }
  } catch (_) {}
}

@visibleForTesting
void clearInMemorySeedCacheForTest() {
  _inMemorySeedCache = null;
  _inMemoryX25519SeedCache = null;
}
