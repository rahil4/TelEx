/// Data models for the "manifest" — the JSON document that stores our folder /
/// tag / organization structure. The manifest itself lives as a pinned file
/// message inside the user's own Saved Messages chat (see manifest_service.dart),
/// so it travels with the Telegram account and needs no separate backend.
///
/// This mirrors the schema agreed on earlier in the design conversation.
library;

class ManifestFolder {
  final String id;
  String? parentId;
  String name;
  String? color;
  int sortOrder;

  ManifestFolder({
    required this.id,
    this.parentId,
    required this.name,
    this.color,
    this.sortOrder = 0,
  });

  factory ManifestFolder.fromJson(Map<String, dynamic> j) => ManifestFolder(
        id: j['id'] as String,
        parentId: j['parent_id'] as String?,
        name: j['name'] as String,
        color: j['color'] as String?,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'parent_id': parentId,
        'name': name,
        'color': color,
        'sort_order': sortOrder,
      };

  @override
  bool operator ==(Object other) => other is ManifestFolder && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class ManifestTag {
  final String id;
  String name;
  String? color;

  ManifestTag({required this.id, required this.name, this.color});

  factory ManifestTag.fromJson(Map<String, dynamic> j) => ManifestTag(
        id: j['id'] as String,
        name: j['name'] as String,
        color: j['color'] as String?,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'color': color};
}

class ManifestItem {
  final int telegramMessageId;
  String? folderId;
  String displayName;
  List<String> tagIds;
  String note;
  DateTime addedAt;
  int sortOrder;

  // cached metadata — for fast UI rendering without re-hitting the Telegram
  // API for every item; always safely re-derivable from Telegram if stale.
  String? mimeType;
  int? sizeBytes;
  String? originalFileName;

  /// True when the local index still has this item, but a re-sync could not
  /// find the message in Saved Messages anymore (user deleted it in Telegram
  /// directly). We keep the row and flag it instead of silently dropping it,
  /// so the person can decide whether to remove it from the manifest.
  bool missing;

  ManifestItem({
    required this.telegramMessageId,
    this.folderId,
    required this.displayName,
    List<String>? tagIds,
    this.note = '',
    DateTime? addedAt,
    this.sortOrder = 0,
    this.mimeType,
    this.sizeBytes,
    this.originalFileName,
    this.missing = false,
  })  : tagIds = tagIds ?? [],
        addedAt = addedAt ?? DateTime.now();

  factory ManifestItem.fromJson(Map<String, dynamic> j) {
    final cached = j['cached'] as Map<String, dynamic>?;
    return ManifestItem(
      telegramMessageId: (j['telegram_message_id'] as num).toInt(),
      folderId: j['folder_id'] as String?,
      displayName: j['display_name'] as String,
      tagIds: (j['tag_ids'] as List?)?.cast<String>() ?? [],
      note: j['note'] as String? ?? '',
      addedAt: DateTime.tryParse(j['added_at'] as String? ?? '') ?? DateTime.now(),
      sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      mimeType: cached?['mime_type'] as String?,
      sizeBytes: (cached?['size_bytes'] as num?)?.toInt(),
      originalFileName: cached?['original_file_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'telegram_message_id': telegramMessageId,
        'folder_id': folderId,
        'display_name': displayName,
        'tag_ids': tagIds,
        'note': note,
        'added_at': addedAt.toIso8601String(),
        'sort_order': sortOrder,
        'cached': {
          'mime_type': mimeType,
          'size_bytes': sizeBytes,
          'original_file_name': originalFileName,
        },
      };

  @override
  bool operator ==(Object other) =>
      other is ManifestItem && other.telegramMessageId == telegramMessageId;

  @override
  int get hashCode => telegramMessageId.hashCode;
}

class Manifest {
  int schemaVersion;
  DateTime updatedAt;
  int revision;
  List<ManifestFolder> folders;
  List<ManifestTag> tags;
  List<ManifestItem> items;

  Manifest({
    this.schemaVersion = 1,
    DateTime? updatedAt,
    this.revision = 0,
    List<ManifestFolder>? folders,
    List<ManifestTag>? tags,
    List<ManifestItem>? items,
  })  : updatedAt = updatedAt ?? DateTime.now(),
        folders = folders ?? [],
        tags = tags ?? [],
        items = items ?? [];

  factory Manifest.empty() => Manifest();

  factory Manifest.fromJson(Map<String, dynamic> j) => Manifest(
        schemaVersion: (j['schema_version'] as num?)?.toInt() ?? 1,
        updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '') ?? DateTime.now(),
        revision: (j['revision'] as num?)?.toInt() ?? 0,
        folders: (j['folders'] as List? ?? [])
            .map((e) => ManifestFolder.fromJson(e as Map<String, dynamic>))
            .toList(),
        tags: (j['tags'] as List? ?? [])
            .map((e) => ManifestTag.fromJson(e as Map<String, dynamic>))
            .toList(),
        items: (j['items'] as List? ?? [])
            .map((e) => ManifestItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'updated_at': updatedAt.toIso8601String(),
        'revision': revision,
        'folders': folders.map((f) => f.toJson()).toList(),
        'tags': tags.map((t) => t.toJson()).toList(),
        'items': items.map((i) => i.toJson()).toList(),
      };

  List<ManifestFolder> childrenOf(String? parentId) =>
      folders.where((f) => f.parentId == parentId).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  List<ManifestItem> itemsInFolder(String? folderId) =>
      items.where((i) => i.folderId == folderId).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
}
