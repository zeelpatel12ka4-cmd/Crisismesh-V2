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
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // Create messages table
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
        synced INTEGER NOT NULL DEFAULT 0
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

  /// Clean up database connections (useful for testing or hot restarts).
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
