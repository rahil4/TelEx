import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
  final String? thumbnailBase64;

  CachedMessage({
    required this.messageId,
    required this.fileName,
    this.mimeType,
    this.sizeBytes,
    required this.date,
    this.thumbnailBase64,
  });

  @override
  bool operator ==(Object other) =>
      other is CachedMessage && other.messageId == messageId;

  @override
  int get hashCode => messageId.hashCode;
}

class ManifestService {
  ManifestService._();
  static final ManifestService instance = ManifestService._();

  Database? _db;
  int? _savedMessagesChatId;
  // Kept only so accounts that tested the earlier Telegram-synced manifest
  // (before this went local-only) don't see that leftover message show up
  // as a stray file in this device's uncategorized list.
  int? _manifestMessageId;

  Manifest manifest = Manifest.empty();
  List<CachedMessage> _cachedMessages = [];

  /// message_id -> base64 minithumbnail data, kept in memory for fast list
  /// rendering. Populated during sync from Telegram's tiny embedded preview
  /// (no separate file download needed) — same idea as a phone gallery's
  /// grid, which never downloads full images just to show a thumbnail.
  final Map<int, String> _thumbnails = {};
  String? thumbnailFor(int messageId) => _thumbnails[messageId];

  final _changesController = StreamController<void>.broadcast();
  Stream<void> get changes => _changesController.stream;

  Future<Database> _openDb() async {
    if (_db != null) return _db!;
    final dir = await getApplicationSupportDirectory();
    final path = p.join(dir.path, 'manifest_cache.db');
    _db = await openDatabase(
      path,
      version: 2,
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
        await db.execute('''
          CREATE TABLE thumbnails (message_id INTEGER PRIMARY KEY, data TEXT)
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS thumbnails (message_id INTEGER PRIMARY KEY, data TEXT)
          ''');
        }
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
    final thumbRows = await db.query('thumbnails');

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

    _thumbnails.clear();
    for (final r in thumbRows) {
      _thumbnails[r['message_id'] as int] = r['data'] as String;
    }

    _cachedMessages = msgRows
        .map((r) => CachedMessage(
              messageId: r['message_id'] as int,
              fileName: r['file_name'] as String,
              mimeType: r['mime_type'] as String?,
              sizeBytes: r['size_bytes'] as int?,
              date: DateTime.fromMillisecondsSinceEpoch((r['date'] as int) * 1000),
              thumbnailBase64: _thumbnails[r['message_id'] as int],
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

  /// Persists the current in-memory [manifest] state (folders/tags/items)
  /// and notifies listeners. Use after directly mutating a model object
  /// (e.g. `item.folderId = x`) at a call site that doesn't have a more
  /// specific ManifestService method for the change being made.
  Future<void> saveChanges() async {
    await _persistLocalCache();
    _changesController.add(null);
  }

  /// Items not yet filed into any folder, derived by diffing every media
  /// message we've seen in Saved Messages against the manifest.
  List<CachedMessage> get uncategorizedMessages {
    final filed = manifest.items.map((i) => i.telegramMessageId).toSet();
    return _cachedMessages.where((m) => !filed.contains(m.messageId)).toList();
  }

  // ---------------------------------------------------------------------
  // mutations used by the explorer UI — local-only for now (see note on
  // sync() below for why multi-device sync via Saved Messages is paused).
  // ---------------------------------------------------------------------

  Future<ManifestFolder> createFolder({required String name, String? parentId}) async {
    final id = 'f_${DateTime.now().microsecondsSinceEpoch}';
    final folder = ManifestFolder(id: id, parentId: parentId, name: name);
    manifest.folders.add(folder);
    await _persistLocalCache();
    _changesController.add(null);
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
  }

  Future<void> renameFolder(String folderId, String newName) async {
    final f = manifest.folders.firstWhere((f) => f.id == folderId);
    f.name = newName;
    await _persistLocalCache();
    _changesController.add(null);
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

  /// Refreshes the "دسته‌بندی‌نشده" set by walking Saved Messages history.
  ///
  /// NOTE: multi-device sync of the folder structure itself (via a manifest
  /// message in Saved Messages) is paused for now — folders/tags/items live
  /// only in this device's local SQLite cache. Files themselves are always
  /// safe in Telegram regardless; only the *organization* (which folder
  /// something is filed into) is local-only until this is revisited.
  Future<void> sync() async {
    final chatId = await _resolveSavedMessagesChatId();
    await _scanMedia(chatId);
    await _persistLocalCache();
    _changesController.add(null);
  }

  /// Walks Saved Messages backwards from the newest message, stopping once
  /// it reaches messages already seen in a previous sync. Extracts basic
  /// metadata for any media message so it can appear in "دسته‌بندی‌نشده"
  /// even before the person files it into a folder.
  Future<void> _scanMedia(int chatId) async {
    final lastSeenStr = await _kvGet('last_synced_message_id');
    final lastSeen = lastSeenStr == null ? 0 : int.tryParse(lastSeenStr) ?? 0;

    int fromMessageId = 0;
    int? lastRequestedId; // the from_message_id we last asked for
    int? newestSeenThisRun;
    bool reachedKnownHistory = false;
    final db = await _openDb();

    // Safety net: even with correct pagination logic this guarantees the
    // sync can never hang forever — 400 pages * 50 messages covers a very
    // large history; if somehow still not done, stop rather than spin.
    const maxPages = 400;
    var pageCount = 0;

    while (!reachedKnownHistory && pageCount < maxPages) {
      pageCount++;
      final page = await TdService.instance.send({
        '@type': 'getChatHistory',
        'chat_id': chatId,
        'from_message_id': fromMessageId,
        'offset': 0,
        'limit': 50,
        'only_local': false,
      });
      var messages = ((page['messages'] as List?) ?? [])
          .cast<Map<String, dynamic>>();

      // With offset:0, TDLib includes the from_message_id message itself as
      // the first result — which we already processed in the previous
      // iteration (it was the last item of the previous page). Drop it here
      // to avoid reprocessing it and, critically, to detect when we've hit
      // the true start of history: if after dropping it nothing remains,
      // there is nothing older left and we must stop.
      if (lastRequestedId != null &&
          messages.isNotEmpty &&
          (messages.first['id'] as num).toInt() == lastRequestedId) {
        messages = messages.sublist(1);
      }

      if (messages.isEmpty) break;

      for (final m in messages) {
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
          if (extracted.thumbnailBase64 != null) {
            await db.insert('thumbnails', {
              'message_id': id,
              'data': extracted.thumbnailBase64,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
            _thumbnails[id] = extracted.thumbnailBase64!;
          }
        }
      }

      if (reachedKnownHistory) break;
      final lastInPage = messages.last;
      final nextFrom = (lastInPage['id'] as num).toInt();
      if (nextFrom == fromMessageId) {
        // no progress made — defensive stop, shouldn't happen given the
        // dedup above, but avoids any possibility of looping forever.
        break;
      }
      lastRequestedId = nextFrom;
      fromMessageId = nextFrom;
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
              thumbnailBase64: _thumbnails[r['message_id'] as int],
            ))
        .toList();
  }

  /// Pulls (file name, mime type, size) out of the handful of TDLib message
  /// content types we treat as "files". Returns null for plain text notes,
  /// which are intentionally left out of the explorer.
  CachedMessage? _extractMediaInfo(Map<String, dynamic> message) {
    final content = message['content'] as Map<String, dynamic>?;
    if (content == null) return null;
    final id = (message['id'] as num).toInt();
    final extracted = _extractFileFromContent(content, id);
    if (extracted == null) return null;

    final size = (extracted.file['size'] as num?)?.toInt();
    return CachedMessage(
      messageId: id,
      fileName: extracted.name,
      mimeType: extracted.mime,
      sizeBytes: size,
      date: DateTime.fromMillisecondsSinceEpoch(((message['date'] as num?) ?? 0).toInt() * 1000),
      thumbnailBase64: _extractMinithumbnail(content),
    );
  }

  /// Telegram embeds a tiny (a few hundred bytes) low-res JPEG directly in
  /// photo/video messages specifically so clients can show an instant
  /// preview without downloading anything — exactly what a phone gallery's
  /// grid does. TDLib delivers its `data` field already base64-encoded.
  String? _extractMinithumbnail(Map<String, dynamic> content) {
    Map<String, dynamic>? mini;
    switch (content['@type']) {
      case 'messagePhoto':
        mini = (content['photo'] as Map<String, dynamic>?)?['minithumbnail'] as Map<String, dynamic>?;
        break;
      case 'messageVideo':
        mini = (content['video'] as Map<String, dynamic>?)?['minithumbnail'] as Map<String, dynamic>?;
        break;
    }
    return mini?['data'] as String?;
  }

  /// Downloads the actual file behind a Saved Messages entry (by re-fetching
  /// the message fresh rather than trusting any previously cached file id,
  /// which keeps this correct even for items synced before this feature
  /// existed) and returns the local path once the download completes.
  Future<String> downloadFileForMessage(int messageId) async {
    final chatId = await _resolveSavedMessagesChatId();
    final msg = await TdService.instance.send({
      '@type': 'getMessage',
      'chat_id': chatId,
      'message_id': messageId,
    });
    final content = msg['content'] as Map<String, dynamic>?;
    if (content == null) {
      throw StateError('محتوای پیام یافت نشد');
    }
    final extracted = _extractFileFromContent(content, messageId);
    if (extracted == null) {
      throw StateError('این پیام فایل قابل‌بازکردنی ندارد');
    }
    final fileId = (extracted.file['id'] as num).toInt();
    final downloaded = await TdService.instance.send({
      '@type': 'downloadFile',
      'file_id': fileId,
      'priority': 32,
      'synchronous': true,
    });
    final localPath = (downloaded['local'] as Map<String, dynamic>?)?['path'] as String?;
    if (localPath == null) {
      throw StateError('دانلود فایل ناموفق بود');
    }
    return localPath;
  }

  ({Map<String, dynamic> file, String name, String? mime})? _extractFileFromContent(
    Map<String, dynamic> content,
    int messageId,
  ) {
    final type = content['@type'] as String?;
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
        name = 'عکس_$messageId.jpg';
        mime = 'image/jpeg';
        break;
      case 'messageVideo':
        final vid = content['video'] as Map<String, dynamic>?;
        file = vid?['video'] as Map<String, dynamic>?;
        name = vid?['file_name'] as String? ?? 'ویدیو_$messageId.mp4';
        mime = vid?['mime_type'] as String?;
        break;
      case 'messageAudio':
        final aud = content['audio'] as Map<String, dynamic>?;
        file = aud?['audio'] as Map<String, dynamic>?;
        name = aud?['file_name'] as String? ?? 'صدا_$messageId.mp3';
        mime = aud?['mime_type'] as String?;
        break;
      case 'messageVoiceNote':
        final vn = content['voice_note'] as Map<String, dynamic>?;
        file = vn?['voice'] as Map<String, dynamic>?;
        name = 'پیام‌صوتی_$messageId.ogg';
        mime = vn?['mime_type'] as String?;
        break;
      default:
        return null;
    }
    if (file == null) return null;
    return (file: file, name: name ?? 'فایل_$messageId', mime: mime);
  }

  // ---------------------------------------------------------------------
  // import from device
  // ---------------------------------------------------------------------

  /// Uploads a file picked from the device's own storage into Saved
  /// Messages as a new document message. If [intoFolderId] is given, the
  /// new item is filed straight into that folder instead of landing in
  /// دسته‌بندی‌نشده like a freshly-discovered message would.
  ///
  /// Re-enabled after adding READ/WRITE_EXTERNAL_STORAGE permissions to
  /// the Android manifest (see build-apk.yml) — flutter_libtdjson's own
  /// README notes TDLib file operations need these, which we never had.
  /// Three earlier attempts using different JSON shapes all failed with
  /// "InputFile is not specified" regardless of structure, which pointed
  /// away from a request-shape problem and toward something environmental
  /// like this.
  Future<void> importLocalFile(String localPath, String fileName, {String? intoFolderId}) async {
    final chatId = await _resolveSavedMessagesChatId();

    final sent = await TdService.instance.send({
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': <String, dynamic>{
        '@type': 'inputMessageDocument',
        'document': <String, dynamic>{'@type': 'inputFileLocal', 'path': localPath},
      },
    });
    final tempId = (sent['id'] as num).toInt();
    final messageId = await _awaitMessageConfirmed(tempId);

    // Record it locally right away so it shows up immediately without
    // waiting for the next full sync.
    final fileSize = await File(localPath).length();
    final db = await _openDb();
    await db.insert('cached_messages', {
      'message_id': messageId,
      'file_name': fileName,
      'mime_type': null,
      'size_bytes': fileSize,
      'date': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    if (intoFolderId != null) {
      manifest.items.add(ManifestItem(
        telegramMessageId: messageId,
        folderId: intoFolderId,
        displayName: fileName,
        sizeBytes: fileSize,
        originalFileName: fileName,
      ));
    }

    await loadFromLocalCache();
    _changesController.add(null);
  }

  /// sendMessage() returns immediately with a message carrying a temporary,
  /// client-local id — the server hasn't confirmed it yet. This waits for
  /// the matching updateMessageSendSucceeded (or _Failed) event and
  /// resolves with the real, server-confirmed message id.
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
          completer.completeError(StateError('ارسال فایل به تلگرام ناموفق بود'));
          sub.cancel();
        }
      }
    });
    return completer.future.timeout(const Duration(seconds: 30), onTimeout: () {
      sub.cancel();
      return tempId; // fall back rather than hanging forever
    });
  }

  /// Deletes a message from Saved Messages entirely (not just from this
  /// app's organization) and cleans up every local trace of it.
  Future<void> deleteMessage(int messageId) async {
    final chatId = await _resolveSavedMessagesChatId();
    await TdService.instance.send({
      '@type': 'deleteMessages',
      'chat_id': chatId,
      'message_ids': [messageId],
      'revoke': true,
    });

    manifest.items.removeWhere((i) => i.telegramMessageId == messageId);

    final db = await _openDb();
    await db.delete('cached_messages', where: 'message_id = ?', whereArgs: [messageId]);
    await db.delete('thumbnails', where: 'message_id = ?', whereArgs: [messageId]);
    _thumbnails.remove(messageId);
    _cachedMessages.removeWhere((m) => m.messageId == messageId);

    await _persistLocalCache();
    _changesController.add(null);
  }
}
