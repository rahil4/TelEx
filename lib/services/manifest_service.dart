import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/manifest.dart';
import 'td_service.dart';

/// A locally-cached media message discovered while scanning Saved Messages,
/// independent of whether it has been filed into a folder yet. Combined with
/// [Manifest.items], this is what lets the explorer show a live
/// "دسته‌بندی‌نشده" listing without re-hitting Telegram on every screen.
class CachedMessage {
  final int messageId;
  final String fileName;
  final String? mimeType;
  final int? sizeBytes;
  final DateTime date;

  CachedMessage({
    required this.messageId,
    required this.fileName,
    this.mimeType,
    this.sizeBytes,
    required this.date,
  });

  @override
  bool operator ==(Object other) =>
      other is CachedMessage && other.messageId == messageId;

  @override
  int get hashCode => messageId.hashCode;
}

const _manifestMarker = '#kavoshgar_manifest';

class ManifestService {
  ManifestService._();
  static final ManifestService instance = ManifestService._();

  Database? _db;
  int? _savedMessagesChatId;
  int? _manifestMessageId;

  Manifest manifest = Manifest.empty();
  List<CachedMessage> _cachedMessages = [];

  final _changesController = StreamController<void>.broadcast();
  Stream<void> get changes => _changesController.stream;

  Future<Database> _openDb() async {
    if (_db != null) return _db!;
    final dir = await getApplicationSupportDirectory();
    final path = p.join(dir.path, 'manifest_cache.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE kv (k TEXT PRIMARY KEY, v TEXT)
        ''');
        await db.execute('''
          CREATE TABLE folders (
            id TEXT PRIMARY KEY, parent_id TEXT, name TEXT,
            color TEXT, sort_order INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE tags (id TEXT PRIMARY KEY, name TEXT, color TEXT)
        ''');
        await db.execute('''
          CREATE TABLE items (
            message_id INTEGER PRIMARY KEY, folder_id TEXT, display_name TEXT,
            tag_ids TEXT, note TEXT, added_at TEXT, sort_order INTEGER,
            mime_type TEXT, size_bytes INTEGER, original_file_name TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE cached_messages (
            message_id INTEGER PRIMARY KEY, file_name TEXT,
            mime_type TEXT, size_bytes INTEGER, date INTEGER
          )
        ''');
      },
    );
    return _db!;
  }

  Future<String?> _kvGet(String key) async {
    final db = await _openDb();
    final rows = await db.query('kv', where: 'k = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['v'] as String?;
  }

  Future<void> _kvSet(String key, String value) async {
    final db = await _openDb();
    await db.insert('kv', {'k': key, 'v': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------------------------------------------------------------------
  // local cache load / save
  // ---------------------------------------------------------------------

  Future<void> loadFromLocalCache() async {
    final db = await _openDb();
    final folderRows = await db.query('folders');
    final tagRows = await db.query('tags');
    final itemRows = await db.query('items');
    final msgRows = await db.query('cached_messages', orderBy: 'date DESC');

    manifest = Manifest(
      folders: folderRows.map((r) => ManifestFolder(
            id: r['id'] as String,
            parentId: r['parent_id'] as String?,
            name: r['name'] as String,
            color: r['color'] as String?,
            sortOrder: r['sort_order'] as int? ?? 0,
          )).toList(),
      tags: tagRows.map((r) => ManifestTag(
            id: r['id'] as String,
            name: r['name'] as String,
            color: r['color'] as String?,
          )).toList(),
      items: itemRows.map((r) => ManifestItem(
            telegramMessageId: r['message_id'] as int,
            folderId: r['folder_id'] as String?,
            displayName: r['display_name'] as String,
            tagIds: (jsonDecode(r['tag_ids'] as String? ?? '[]') as List).cast<String>(),
            note: r['note'] as String? ?? '',
            addedAt: DateTime.tryParse(r['added_at'] as String? ?? '') ?? DateTime.now(),
            sortOrder: r['sort_order'] as int? ?? 0,
            mimeType: r['mime_type'] as String?,
            sizeBytes: r['size_bytes'] as int?,
            originalFileName: r['original_file_name'] as String?,
          )).toList(),
    );

    _cachedMessages = msgRows
        .map((r) => CachedMessage(
              messageId: r['message_id'] as int,
              fileName: r['file_name'] as String,
              mimeType: r['mime_type'] as String?,
              sizeBytes: r['size_bytes'] as int?,
              date: DateTime.fromMillisecondsSinceEpoch((r['date'] as int) * 1000),
            ))
        .toList();

    final storedManifestMsg = await _kvGet('manifest_message_id');
    _manifestMessageId = storedManifestMsg == null ? null : int.tryParse(storedManifestMsg);

    _changesController.add(null);
  }

  Future<void> _persistLocalCache() async {
    final db = await _openDb();
    await db.transaction((txn) async {
      await txn.delete('folders');
      await txn.delete('tags');
      await txn.delete('items');
      for (final f in manifest.folders) {
        await txn.insert('folders', {
          'id': f.id, 'parent_id': f.parentId, 'name': f.name,
          'color': f.color, 'sort_order': f.sortOrder,
        });
      }
      for (final t in manifest.tags) {
        await txn.insert('tags', {'id': t.id, 'name': t.name, 'color': t.color});
      }
      for (final i in manifest.items) {
        await txn.insert('items', {
          'message_id': i.telegramMessageId,
          'folder_id': i.folderId,
          'display_name': i.displayName,
          'tag_ids': jsonEncode(i.tagIds),
          'note': i.note,
          'added_at': i.addedAt.toIso8601String(),
          'sort_order': i.sortOrder,
          'mime_type': i.mimeType,
          'size_bytes': i.sizeBytes,
          'original_file_name': i.originalFileName,
        });
      }
    });
  }

  /// Items not yet filed into any folder, derived by diffing every media
  /// message we've seen in Saved Messages against the manifest.
  List<CachedMessage> get uncategorizedMessages {
    final filed = manifest.items.map((i) => i.telegramMessageId).toSet();
    return _cachedMessages.where((m) => !filed.contains(m.messageId)).toList();
  }

  // ---------------------------------------------------------------------
  // mutations used by the explorer UI — each persists locally immediately
  // and pushes the updated manifest to Telegram in the background.
  // ---------------------------------------------------------------------

  Future<ManifestFolder> createFolder({required String name, String? parentId}) async {
    final id = 'f_${DateTime.now().microsecondsSinceEpoch}';
    final folder = ManifestFolder(id: id, parentId: parentId, name: name);
    manifest.folders.add(folder);
    await _persistLocalCache();
    _changesController.add(null);
    unawaited(pushManifest());
    return folder;
  }

  Future<void> fileMessageIntoFolder(CachedMessage msg, String? folderId) async {
    final existingIndex =
        manifest.items.indexWhere((i) => i.telegramMessageId == msg.messageId);
    if (existingIndex >= 0) {
      manifest.items[existingIndex].folderId = folderId;
    } else {
      manifest.items.add(ManifestItem(
        telegramMessageId: msg.messageId,
        folderId: folderId,
        displayName: msg.fileName,
        mimeType: msg.mimeType,
        sizeBytes: msg.sizeBytes,
        originalFileName: msg.fileName,
        addedAt: msg.date,
      ));
    }
    await _persistLocalCache();
    _changesController.add(null);
    unawaited(pushManifest());
  }

  Future<void> renameFolder(String folderId, String newName) async {
    final f = manifest.folders.firstWhere((f) => f.id == folderId);
    f.name = newName;
    await _persistLocalCache();
    _changesController.add(null);
    unawaited(pushManifest());
  }

  Future<void> deleteFolder(String folderId) async {
    manifest.folders.removeWhere((f) => f.id == folderId);
    // orphaned children/items fall back to the root rather than disappearing
    for (final f in manifest.folders) {
      if (f.parentId == folderId) f.parentId = null;
    }
    for (final i in manifest.items) {
      if (i.folderId == folderId) i.folderId = null;
    }
    await _persistLocalCache();
    _changesController.add(null);
    unawaited(pushManifest());
  }

  // ---------------------------------------------------------------------
  // Telegram sync
  // ---------------------------------------------------------------------

  Future<int> _resolveSavedMessagesChatId() async {
    if (_savedMessagesChatId != null) return _savedMessagesChatId!;
    final me = await TdService.instance.send({'@type': 'getMe'});
    final userId = (me['id'] as num).toInt();
    // getChat alone fails with "Chat not found" until TDLib has been
    // explicitly asked to create/load the private chat at least once.
    // createPrivateChat does that (and returns the Chat object, including
    // its id — used as-is rather than assumed to equal userId).
    final chat = await TdService.instance.send({
      '@type': 'createPrivateChat',
      'user_id': userId,
      'force': true,
    });
    final chatId = (chat['id'] as num).toInt();
    _savedMessagesChatId = chatId;
    return chatId;
  }

  /// Full sync: discovers (or creates) the pinned manifest document, then
  /// walks Saved Messages history to refresh the "uncategorized" set.
  Future<void> sync() async {
    final chatId = await _resolveSavedMessagesChatId();
    await _discoverOrCreateManifest(chatId);
    await _scanMedia(chatId);
    await _persistLocalCache();
    _changesController.add(null);
  }

  Future<void> _discoverOrCreateManifest(int chatId) async {
    if (_manifestMessageId != null) {
      await _downloadAndApplyManifest(_manifestMessageId!);
      return;
    }

    final found = await TdService.instance.send({
      '@type': 'searchChatMessages',
      'chat_id': chatId,
      'query': _manifestMarker,
      'from_message_id': 0,
      'offset': 0,
      'limit': 5,
    });
    final messages = (found['messages'] as List?) ?? [];
    if (messages.isNotEmpty) {
      final id = (messages.first['id'] as num).toInt();
      _manifestMessageId = id;
      await _kvSet('manifest_message_id', id.toString());
      await _downloadAndApplyManifest(id);
      return;
    }

    // nothing found — this account has no manifest yet, create an empty one
    manifest = Manifest.empty();
    await _pushManifest(chatId, create: true);
  }

  Future<void> _downloadAndApplyManifest(int messageId) async {
    final msg = await TdService.instance.send({
      '@type': 'getMessage',
      'chat_id': _savedMessagesChatId!,
      'message_id': messageId,
    });
    final content = msg['content'] as Map<String, dynamic>?;
    final text = (content?['text'] as Map<String, dynamic>?)?['text'] as String?;
    if (text == null) return;
    final jsonPart = text.startsWith(_manifestMarker)
        ? text.substring(_manifestMarker.length).trim()
        : text.trim();
    if (jsonPart.isEmpty) return;
    manifest = Manifest.fromJson(jsonDecode(jsonPart) as Map<String, dynamic>);
  }

  /// Serializes [manifest] to a plain-text message and sends/pins/edits it
  /// in Saved Messages. Call after any local edit (new folder, move file,
  /// ...). Stored as text rather than an attached file: it's simpler,
  /// avoids a local-file-upload step entirely, and a compact JSON manifest
  /// comfortably fits inside Telegram's ~4096 character message limit for
  /// a personal folder structure. If this ever becomes a real constraint
  /// (very large folder trees), this is the place to switch to a file.
  Future<void> pushManifest() async {
    final chatId = await _resolveSavedMessagesChatId();
    await _pushManifest(chatId, create: _manifestMessageId == null);
    await _persistLocalCache();
  }

  Future<void> _pushManifest(int chatId, {required bool create}) async {
    manifest.revision += 1;
    manifest.updatedAt = DateTime.now();

    final body = '$_manifestMarker\n${jsonEncode(manifest.toJson())}';
    if (body.length > 4000) {
      throw StateError(
        'منیفست به ${body.length} کاراکتر رسیده و به محدودیت پیام تلگرام نزدیک است. '
        'این نسخه هنوز از ذخیرهٔ فایلی پشتیبانی نمی‌کند — لازم است تعداد فولدر/فایل کم شود.',
      );
    }

    final content = <String, dynamic>{
      '@type': 'inputMessageText',
      'text': <String, dynamic>{'@type': 'formattedText', 'text': body},
    };

    if (create) {
      final sent = await TdService.instance.send({
        '@type': 'sendMessage',
        'chat_id': chatId,
        'input_message_content': content,
      });
      final tempId = (sent['id'] as num).toInt();
      final id = await _awaitMessageConfirmed(tempId);
      _manifestMessageId = id;
      await _kvSet('manifest_message_id', id.toString());
      await TdService.instance.send({
        '@type': 'pinChatMessage',
        'chat_id': chatId,
        'message_id': id,
        'disable_notification': true,
      });
    } else {
      await TdService.instance.send({
        '@type': 'editMessageText',
        'chat_id': chatId,
        'message_id': _manifestMessageId,
        'input_message_content': content,
      });
    }
  }

  /// sendMessage() returns immediately with a message carrying a temporary,
  /// client-local id — the server hasn't confirmed it yet, so operations
  /// like pinChatMessage will reject that id ("Message can't be pinned").
  /// This waits for the matching updateMessageSendSucceeded (or _Failed)
  /// event and resolves with the real, server-confirmed message id.
  Future<int> _awaitMessageConfirmed(int tempId) async {
    final completer = Completer<int>();
    late final StreamSubscription sub;
    sub = TdService.instance.updates.listen((u) {
      final type = u['@type'];
      if (type == 'updateMessageSendSucceeded') {
        final oldId = (u['old_message_id'] as num?)?.toInt();
        if (oldId == tempId) {
          final newMsg = u['message'] as Map<String, dynamic>;
          completer.complete((newMsg['id'] as num).toInt());
          sub.cancel();
        }
      } else if (type == 'updateMessageSendFailed') {
        final oldId = (u['old_message_id'] as num?)?.toInt();
        if (oldId == tempId) {
          completer.completeError(StateError('ارسال پیام منیفست به تلگرام ناموفق بود'));
          sub.cancel();
        }
      }
    });
    return completer.future.timeout(const Duration(seconds: 20), onTimeout: () {
      sub.cancel();
      // fall back to the temporary id rather than hanging forever — pin
      // may still fail, but sync as a whole can continue.
      return tempId;
    });
  }

  /// Walks Saved Messages backwards from the newest message, stopping once
  /// it reaches messages already seen in a previous sync. Extracts basic
  /// metadata for any media message so it can appear in "دسته‌بندی‌نشده"
  /// even before the person files it into a folder.
  Future<void> _scanMedia(int chatId) async {
    final lastSeenStr = await _kvGet('last_synced_message_id');
    final lastSeen = lastSeenStr == null ? 0 : int.tryParse(lastSeenStr) ?? 0;

    int fromMessageId = 0;
    int? newestSeenThisRun;
    bool reachedKnownHistory = false;
    final db = await _openDb();

    while (!reachedKnownHistory) {
      final page = await TdService.instance.send({
        '@type': 'getChatHistory',
        'chat_id': chatId,
        'from_message_id': fromMessageId,
        'offset': 0,
        'limit': 50,
        'only_local': false,
      });
      final messages = (page['messages'] as List?) ?? [];
      if (messages.isEmpty) break;

      for (final raw in messages) {
        final m = raw as Map<String, dynamic>;
        final id = (m['id'] as num).toInt();
        newestSeenThisRun ??= id;
        if (id <= lastSeen) {
          reachedKnownHistory = true;
          break;
        }
        if (id == _manifestMessageId) continue;

        final extracted = _extractMediaInfo(m);
        if (extracted != null) {
          await db.insert('cached_messages', {
            'message_id': id,
            'file_name': extracted.fileName,
            'mime_type': extracted.mimeType,
            'size_bytes': extracted.sizeBytes,
            'date': m['date'],
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      if (reachedKnownHistory) break;
      final lastInPage = messages.last as Map<String, dynamic>;
      fromMessageId = (lastInPage['id'] as num).toInt();
    }

    if (newestSeenThisRun != null) {
      await _kvSet('last_synced_message_id', newestSeenThisRun.toString());
    }

    final msgRows = await db.query('cached_messages', orderBy: 'date DESC');
    _cachedMessages = msgRows
        .map((r) => CachedMessage(
              messageId: r['message_id'] as int,
              fileName: r['file_name'] as String,
              mimeType: r['mime_type'] as String?,
              sizeBytes: r['size_bytes'] as int?,
              date: DateTime.fromMillisecondsSinceEpoch((r['date'] as int) * 1000),
            ))
        .toList();
  }

  /// Pulls (file name, mime type, size) out of the handful of TDLib message
  /// content types we treat as "files". Returns null for plain text notes,
  /// which are intentionally left out of the explorer.
  CachedMessage? _extractMediaInfo(Map<String, dynamic> message) {
    final content = message['content'] as Map<String, dynamic>?;
    if (content == null) return null;
    final type = content['@type'] as String?;
    final id = (message['id'] as num).toInt();

    Map<String, dynamic>? file;
    String? name;
    String? mime;

    switch (type) {
      case 'messageDocument':
        final doc = content['document'] as Map<String, dynamic>?;
        file = doc?['document'] as Map<String, dynamic>?;
        name = doc?['file_name'] as String?;
        mime = doc?['mime_type'] as String?;
        break;
      case 'messagePhoto':
        final sizes = (content['photo'] as Map<String, dynamic>?)?['sizes'] as List?;
        final biggest = sizes?.isNotEmpty == true ? sizes!.last as Map<String, dynamic> : null;
        file = biggest?['photo'] as Map<String, dynamic>?;
        name = 'عکس_$id.jpg';
        mime = 'image/jpeg';
        break;
      case 'messageVideo':
        final vid = content['video'] as Map<String, dynamic>?;
        file = vid?['video'] as Map<String, dynamic>?;
        name = vid?['file_name'] as String? ?? 'ویدیو_$id.mp4';
        mime = vid?['mime_type'] as String?;
        break;
      case 'messageAudio':
        final aud = content['audio'] as Map<String, dynamic>?;
        file = aud?['audio'] as Map<String, dynamic>?;
        name = aud?['file_name'] as String? ?? 'صدا_$id.mp3';
        mime = aud?['mime_type'] as String?;
        break;
      case 'messageVoiceNote':
        final vn = content['voice_note'] as Map<String, dynamic>?;
        file = vn?['voice'] as Map<String, dynamic>?;
        name = 'پیام‌صوتی_$id.ogg';
        mime = vn?['mime_type'] as String?;
        break;
      default:
        return null;
    }

    final size = (file?['size'] as num?)?.toInt();
    return CachedMessage(
      messageId: id,
      fileName: name ?? 'فایل_$id',
      mimeType: mime,
      sizeBytes: size,
      date: DateTime.fromMillisecondsSinceEpoch(((message['date'] as num?) ?? 0).toInt() * 1000),
    );
  }
}
