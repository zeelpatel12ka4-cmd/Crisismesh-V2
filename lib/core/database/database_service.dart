import 'dart:async';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/message_model.dart';
import '../models/contact_model.dart';
import '../models/private_message_model.dart';

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
      version: 4,
      onCreate: _createDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute(
              "ALTER TABLE messages ADD COLUMN mesh_delivery_status TEXT NOT NULL DEFAULT 'transmitted_to_peer'",
            );
          } catch (_) {}
        }
        if (oldVersion < 3) {
          try {
            await db.execute("ALTER TABLE messages ADD COLUMN public_key TEXT");
          } catch (_) {}
          try {
            await db.execute("ALTER TABLE messages ADD COLUMN signature_version TEXT DEFAULT '1'");
          } catch (_) {}
          try {
            await db.execute("ALTER TABLE messages ADD COLUMN authenticity_status TEXT NOT NULL DEFAULT 'unverified'");
          } catch (_) {}
        }
        if (oldVersion < 4) {
          await _createPhase8Tables(db);
        }
      },
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. Create messages table with Phase 5A mesh delivery and Phase 7 authenticity tracking
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
        public_key TEXT,
        signature_version TEXT DEFAULT '1',
        authenticity_status TEXT NOT NULL DEFAULT 'unverified',
        synced INTEGER NOT NULL DEFAULT 0,
        mesh_delivery_status TEXT NOT NULL DEFAULT 'transmitted_to_peer'
      )
    ''');

    // 2. Create seen_message_ids table for deduplication
    await db.execute('''
      CREATE TABLE seen_message_ids (
        id TEXT PRIMARY KEY,
        timestamp INTEGER NOT NULL
      )
    ''');

    // 3. Create Phase 8 contacts and private messages tables
    await _createPhase8Tables(db);
  }

  Future<void> _createPhase8Tables(Database db) async {
    // Contacts Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS contacts (
        device_id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        signing_public_key TEXT NOT NULL,
        encryption_public_key TEXT NOT NULL,
        fingerprint TEXT NOT NULL,
        trust_status TEXT NOT NULL DEFAULT 'UNVERIFIED',
        created_at INTEGER NOT NULL,
        last_seen_at INTEGER NOT NULL
      )
    ''');

    // Private Messages Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS private_messages (
        message_id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        sender_device_id TEXT NOT NULL,
        recipient_device_id TEXT NOT NULL,
        plaintext_body TEXT,
        ciphertext TEXT NOT NULL,
        nonce TEXT NOT NULL,
        auth_tag TEXT NOT NULL,
        sender_x25519_pub TEXT NOT NULL,
        sender_ed25519_pub TEXT NOT NULL,
        signature TEXT NOT NULL,
        status TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        is_outgoing INTEGER NOT NULL DEFAULT 0,
        acknowledged INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_private_messages_conv ON private_messages(conversation_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_private_messages_recipient ON private_messages(recipient_device_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_private_messages_expires ON private_messages(expires_at)');
  }

  // ===========================================================================
  // EXISTING SOS MESSAGE OPERATIONS (PRESERVED)
  // ===========================================================================

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

  /// Prunes stale SOS broadcast messages older than 48 hours (Master Spec)
  Future<int> purgeExpiredSosMessages({int? nowMs}) async {
    final db = await database;
    final current = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final threshold = current - const Duration(hours: 48).inMilliseconds;
    return await db.delete(
      'messages',
      where: 'timestamp < ?',
      whereArgs: [threshold],
    );
  }

  // ===========================================================================
  // PHASE 8: CONTACT MANAGEMENT OPERATIONS
  // ===========================================================================

  /// Saves or updates a contact.
  /// If keys have changed for an existing contact, sets status to KEY_CHANGED rather than silently overwriting.
  Future<void> saveContact(ContactModel contact) async {
    final db = await database;
    final existing = await getContact(contact.deviceId);

    if (existing != null) {
      if (existing.signingPublicKey != contact.signingPublicKey ||
          existing.encryptionPublicKey != contact.encryptionPublicKey) {
        // Key mismatch detected! Flag as KEY_CHANGED
        await db.update(
          'contacts',
          {
            'trust_status': ContactTrustStatus.keyChanged.value,
            'last_seen_at': contact.lastSeenAt,
          },
          where: 'device_id = ?',
          whereArgs: [contact.deviceId],
        );
        return;
      }
    }

    await db.insert(
      'contacts',
      contact.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retrieves a contact by device ID
  Future<ContactModel?> getContact(String deviceId) async {
    final db = await database;
    final maps = await db.query(
      'contacts',
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );

    if (maps.isEmpty) return null;
    return ContactModel.fromMap(maps.first);
  }

  /// Retrieves all contacts sorted by last seen descending
  Future<List<ContactModel>> getAllContacts() async {
    final db = await database;
    final maps = await db.query(
      'contacts',
      orderBy: 'last_seen_at DESC',
    );

    return maps.map((map) => ContactModel.fromMap(map)).toList();
  }

  /// Updates trust status for a contact
  Future<int> updateContactTrustStatus(String deviceId, ContactTrustStatus status) async {
    final db = await database;
    return await db.update(
      'contacts',
      {'trust_status': status.value},
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
  }

  /// Deletes a contact
  Future<int> deleteContact(String deviceId) async {
    final db = await database;
    return await db.delete(
      'contacts',
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
  }

  // ===========================================================================
  // PHASE 8: PRIVATE 1-TO-1 MESSAGE OPERATIONS
  // ===========================================================================

  /// Computes a deterministic conversation ID for two peer device IDs
  static String computeConversationId(String peerA, String peerB) {
    final sorted = [peerA, peerB]..sort();
    return 'conv-${sorted[0]}-${sorted[1]}';
  }

  /// Saves a private message to the local SQLite database
  Future<void> savePrivateMessage(PrivateMessageModel message) async {
    final db = await database;
    await db.insert(
      'private_messages',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retrieves messages in a conversation sorted by timestamp ascending
  Future<List<PrivateMessageModel>> getConversationMessages(String conversationId) async {
    final db = await database;
    final maps = await db.query(
      'private_messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'timestamp ASC',
    );

    return maps.map((map) => PrivateMessageModel.fromMap(map)).toList();
  }

  /// Retrieves pending outgoing private messages for store-and-forward flushing
  Future<List<PrivateMessageModel>> getPendingPrivateMessages() async {
    final db = await database;
    final maps = await db.query(
      'private_messages',
      where: 'status = ? AND is_outgoing = 1',
      whereArgs: [PrivateMessageStatus.pending],
      orderBy: 'timestamp ASC',
    );

    return maps.map((map) => PrivateMessageModel.fromMap(map)).toList();
  }

  /// Updates a private message's status
  Future<int> updatePrivateMessageStatus(String messageId, String status) async {
    final db = await database;
    return await db.update(
      'private_messages',
      {'status': status},
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
  }

  /// Marks a private message as DELIVERED upon receiving a delivery ACK
  Future<int> markPrivateMessageDelivered(String messageId) async {
    final db = await database;
    return await db.update(
      'private_messages',
      {
        'status': PrivateMessageStatus.delivered,
        'acknowledged': 1,
      },
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
  }

  /// Checks if a private message ID has already been recorded
  Future<bool> hasSeenPrivateMessageId(String messageId) async {
    final db = await database;
    final maps = await db.query(
      'private_messages',
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
    return maps.isNotEmpty;
  }

  /// Prunes expired private messages (older than 7 days) OR messages already acknowledged
  /// SOS messages are NOT pruned here (completely independent lifecycle).
  Future<int> purgeExpiredPrivateMessages({int? nowMs}) async {
    final db = await database;
    final current = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return await db.delete(
      'private_messages',
      where: 'expires_at < ? OR (acknowledged = 1 AND status = ?)',
      whereArgs: [current, PrivateMessageStatus.delivered],
    );
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
