import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

/// Local SQLite storage engine for LiChat.
///
/// Stores messages locally on the device in WhatsApp-style:
/// - Messages are written locally upon receipt/send (zero-latency reads).
/// - Firestore is only used as a transit relay; delivered messages can be
///   purged from the server, slashing Firestore storage and billing.
/// - The local DB persists indefinitely across sessions.
class LocalDbService {
  static Database? _db;
  static const int _version = 1;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final fullPath = p.join(dbPath, 'lichat_vault.db');
    return await openDatabase(
      fullPath,
      version: _version,
      onCreate: _createTables,
      onUpgrade: _migrateTables,
    );
  }

  static Future<void> _createTables(Database db, int version) async {
    // Messages table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id             TEXT PRIMARY KEY,
        chat_id        TEXT NOT NULL,
        sender_id      TEXT NOT NULL,
        sender_name    TEXT,
        receiver_id    TEXT,
        text           TEXT,
        type           TEXT NOT NULL DEFAULT 'text',
        media_url      TEXT,
        local_path     TEXT,
        file_name      TEXT,
        file_size      INTEGER,
        duration       INTEGER,
        status         TEXT NOT NULL DEFAULT 'sent',
        is_read        INTEGER NOT NULL DEFAULT 0,
        timestamp      INTEGER NOT NULL,
        reply_to_id    TEXT,
        reply_to_text  TEXT,
        is_group       INTEGER NOT NULL DEFAULT 0,
        created_at     INTEGER NOT NULL DEFAULT (strftime('%s','now'))
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON messages(chat_id, timestamp DESC)');

    // Conversations table (chat list cache)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS conversations (
        chat_id            TEXT PRIMARY KEY,
        peer_uid           TEXT,
        peer_name          TEXT,
        peer_avatar        TEXT,
        last_message       TEXT,
        last_message_type  TEXT DEFAULT 'text',
        last_timestamp     INTEGER,
        unread_count       INTEGER NOT NULL DEFAULT 0,
        is_group           INTEGER NOT NULL DEFAULT 0,
        is_muted           INTEGER NOT NULL DEFAULT 0,
        is_pinned          INTEGER NOT NULL DEFAULT 0,
        updated_at         INTEGER NOT NULL DEFAULT (strftime('%s','now'))
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_conv_updated ON conversations(updated_at DESC)');

    // Media cache table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS media_cache (
        id           TEXT PRIMARY KEY,
        chat_id      TEXT NOT NULL,
        message_id   TEXT NOT NULL,
        remote_url   TEXT,
        local_path   TEXT NOT NULL,
        mime_type    TEXT,
        file_size    INTEGER,
        cached_at    INTEGER NOT NULL DEFAULT (strftime('%s','now'))
      )
    ''');
  }

  static Future<void> _migrateTables(
      Database db, int oldVersion, int newVersion) async {
    debugPrint('[LocalDB] Migrating v$oldVersion -> v$newVersion');
  }

  // ── Messages API ───────────────────────────────────────────────────────────

  static Future<void> upsertMessage(Map<String, dynamic> msg) async {
    final db = await database;
    await db.insert(
      'messages',
      {
        'id': msg['id'] ?? msg['messageId'],
        'chat_id': msg['chatId'],
        'sender_id': msg['senderId'],
        'sender_name': msg['senderName'],
        'receiver_id': msg['receiverId'],
        'text': msg['text'],
        'type': msg['type'] ?? 'text',
        'media_url': msg['mediaUrl'],
        'local_path': msg['localPath'],
        'file_name': msg['fileName'],
        'file_size': msg['fileSize'],
        'duration': msg['duration'],
        'status': msg['status'] ?? 'sent',
        'is_read': (msg['isRead'] == true) ? 1 : 0,
        'timestamp': msg['timestamp'] is int
            ? msg['timestamp']
            : DateTime.now().millisecondsSinceEpoch,
        'reply_to_id': msg['replyToId'],
        'reply_to_text': msg['replyToText'],
        'is_group': (msg['isGroup'] == true) ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Map<String, dynamic>>> loadMessages(
    String chatId, {
    int limit = 30,
    int? beforeTimestamp,
  }) async {
    final db = await database;
    final where = beforeTimestamp != null
        ? 'chat_id = ? AND timestamp < ?'
        : 'chat_id = ?';
    final whereArgs =
        beforeTimestamp != null ? [chatId, beforeTimestamp] : [chatId];

    final rows = await db.query(
      'messages',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.reversed.toList();
  }

  static Future<void> updateMessageStatus(String msgId, String status) async {
    final db = await database;
    await db.update(
      'messages',
      {'status': status},
      where: 'id = ?',
      whereArgs: [msgId],
    );
  }

  static Future<void> markChatRead(String chatId) async {
    final db = await database;
    await db.update(
      'messages',
      {'is_read': 1},
      where: 'chat_id = ? AND is_read = 0',
      whereArgs: [chatId],
    );
    await db.update(
      'conversations',
      {'unread_count': 0},
      where: 'chat_id = ?',
      whereArgs: [chatId],
    );
  }

  // ── Conversations API ──────────────────────────────────────────────────────

  static Future<void> upsertConversation(Map<String, dynamic> conv) async {
    final db = await database;
    await db.insert(
      'conversations',
      {
        'chat_id': conv['chatId'],
        'peer_uid': conv['peerUid'],
        'peer_name': conv['peerName'],
        'peer_avatar': conv['peerAvatar'],
        'last_message': conv['lastMessage'],
        'last_message_type': conv['lastMessageType'] ?? 'text',
        'last_timestamp': conv['lastTimestamp'],
        'unread_count': conv['unreadCount'] ?? 0,
        'is_group': (conv['isGroup'] == true) ? 1 : 0,
        'is_muted': (conv['isMuted'] == true) ? 1 : 0,
        'is_pinned': (conv['isPinned'] == true) ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Map<String, dynamic>>> loadConversations() async {
    final db = await database;
    return db.query(
      'conversations',
      orderBy: 'is_pinned DESC, last_timestamp DESC',
    );
  }

  // ── Media Cache API ────────────────────────────────────────────────────────

  static Future<void> cacheMedia({
    required String messageId,
    required String chatId,
    required String localPath,
    String? remoteUrl,
    String? mimeType,
    int? fileSize,
  }) async {
    final db = await database;
    await db.insert(
      'media_cache',
      {
        'id': messageId,
        'chat_id': chatId,
        'message_id': messageId,
        'remote_url': remoteUrl,
        'local_path': localPath,
        'mime_type': mimeType,
        'file_size': fileSize,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<String?> getLocalMediaPath(String messageId) async {
    final db = await database;
    final rows = await db.query(
      'media_cache',
      columns: ['local_path'],
      where: 'message_id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['local_path'] as String?;
  }

  // ── Utility API ────────────────────────────────────────────────────────────

  static Future<void> clearAll() async {
    final db = await database;
    await db.delete('messages');
    await db.delete('conversations');
    await db.delete('media_cache');
  }

  static Future<int> messageCount(String chatId) async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM messages WHERE chat_id = ?', [chatId]);
    return (result.first['count'] as int?) ?? 0;
  }
}
