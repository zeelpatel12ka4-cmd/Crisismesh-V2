import 'dart:async';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/message_model.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('crisis_mesh.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getApplicationDocumentsDirectory();
    final path = join(dbPath.path, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute(
              "ALTER TABLE messages ADD COLUMN mesh_delivery_status TEXT NOT NULL DEFAULT 'transmitted_to_peer'",
            );
          } catch (e) {
            // Column may already exist
          }
        }
      },
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // Create messages table with Phase 5A mesh delivery tracking
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        recipient_id TEXT,
        group_id TEXT,
        payload TEXT,
        need_type TEXT,
        lat REAL,
        lng REAL,
        timestamp INTEGER NOT NULL,
        hop_count INTEGER NOT NULL,
        priority_tier TEXT NOT NULL,
        priority_score INTEGER NOT NULL,
        signature TEXT,
        synced INTEGER NOT NULL DEFAULT 0,
        mesh_delivery_status TEXT NOT NULL DEFAULT 'transmitted_to_peer'
      )
    ''');

    // Create seen_message_ids table for deduplication
    await db.execute('''
      CREATE TABLE seen_message_ids (
        id TEXT PRIMARY KEY,
        timestamp INTEGER NOT NULL
      )
    ''');
  }

  /// Saves a message/SOS report to the local database.
  Future<void> saveMessage(MessageModel message) async {
    final db = await database;
    await db.insert(
      'messages',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retrieves all messages/SOS reports sorted by timestamp descending.
  Future<List<MessageModel>> getMessages() async {
    final db = await database;
    final maps = await db.query(
      'messages',
      orderBy: 'timestamp DESC',
    );

    return maps.map((map) => MessageModel.fromMap(map)).toList();
  }

  /// Records a seen message ID for duplicate drop checks.
  Future<void> saveSeenMessageId(String id) async {
    final db = await database;
    await db.insert(
      'seen_message_ids',
      {
        'id': id,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Checks if a message ID has already been seen and processed.
  Future<bool> hasSeenMessageId(String id) async {
    final db = await database;
    final maps = await db.query(
      'seen_message_ids',
      where: 'id = ?',
      whereArgs: [id],
    );
    return maps.isNotEmpty;
  }

  /// Retrieves all unsynced messages (synced = 0) sorted by timestamp ascending.
  Future<List<MessageModel>> getUnsyncedMessages() async {
    final db = await database;
    final maps = await db.query(
      'messages',
      where: 'synced = ?',
      whereArgs: [0],
      orderBy: 'timestamp ASC',
    );

    return maps.map((map) => MessageModel.fromMap(map)).toList();
  }

  /// Updates a message's synced status to 1 (synced).
  Future<int> markMessageSynced(String id) async {
    final db = await database;
    return await db.update(
      'messages',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Retrieves all pending mesh messages (mesh_delivery_status = 'pending') sorted by timestamp ascending (FIFO).
  Future<List<MessageModel>> getPendingMeshMessages() async {
    final db = await database;
    final maps = await db.query(
      'messages',
      where: 'mesh_delivery_status = ?',
      whereArgs: [MeshDeliveryStatus.pending],
      orderBy: 'timestamp ASC',
    );

    return maps.map((map) => MessageModel.fromMap(map)).toList();
  }

  /// Updates a message's mesh delivery status ('pending', 'sending', 'transmitted_to_peer').
  Future<int> updateMeshDeliveryStatus(String id, String status) async {
    final db = await database;
    return await db.update(
      'messages',
      {'mesh_delivery_status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Marks a message as successfully transmitted to at least one peer.
  Future<int> markMessageMeshTransmitted(String id) async {
    return await updateMeshDeliveryStatus(id, MeshDeliveryStatus.transmittedToPeer);
  }

  /// Clean up database connections (useful for testing or hot restarts).
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
