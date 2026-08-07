import 'package:fluent_ui/fluent_ui.dart';
import 'package:shamsi_date/shamsi_date.dart';
import '../models/manifest.dart';
import '../services/manifest_service.dart';
import 'widgets/file_icons.dart';

/// sentinel folderId meaning "the virtual دسته‌بندی‌نشده listing"
const _kUncategorized = '__uncategorized__';

enum ViewMode { icons, list }

class ExplorerScreen extends StatefulWidget {
  const ExplorerScreen({super.key});

  @override
  State<ExplorerScreen> createState() => _ExplorerScreenState();
}

class _ExplorerScreenState extends State<ExplorerScreen> {
  String? _currentFolderId; // null = root
  bool _atUncategorized = false;
  ViewMode _viewMode = ViewMode.icons;
  Object? _selected; // ManifestFolder | ManifestItem | CachedMessage
  bool _syncing = false;
  final Set<String> _expandedFolders = {};

  @override
  void initState() {
    super.initState();
    ManifestService.instance.changes.listen((_) {
      if (mounted) setState(() {});
    });
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _syncing = true);
    await ManifestService.instance.loadFromLocalCache();
    try {
      await ManifestService.instance.sync();
    } catch (_) {
      // offline or transient error — local cache still shown
    }
    if (mounted) setState(() => _syncing = false);
  }

  Manifest get _manifest => ManifestService.instance.manifest;

  List<ManifestFolder> get _breadcrumbTrail {
    if (_atUncategorized) return [];
    final trail = <ManifestFolder>[];
    String? id = _currentFolderId;
    while (id != null) {
      final f = _manifest.folders.where((f) => f.id == id).firstOrNull;
      if (f == null) break;
      trail.insert(0, f);
      id = f.parentId;
    }
    return trail;
  }

  void _openFolder(String? id) {
    setState(() {
      _currentFolderId = id;
      _atUncategorized = false;
      _selected = null;
    });
  }

  void _openUncategorized() {
    setState(() {
      _atUncategorized = true;
      _selected = null;
    });
  }

  Future<void> _newFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('پوشهٔ جدید'),
        content: TextBox(controller: controller, placeholder: 'نام پوشه', autofocus: true),
        actions: [
          Button(child: const Text('انصراف'), onPressed: () => Navigator.pop(ctx)),
          FilledButton(
            child: const Text('ایجاد'),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await ManifestService.instance.createFolder(
        name: name,
        parentId: _atUncategorized ? null : _currentFolderId,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      padding: EdgeInsets.zero,
      content: Column(
        children: [
          _buildCommandBar(),
          _buildAddressBar(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 300, child: _buildDetailsPane()),
                _vDivider(),
                Expanded(child: _buildContent()),
                _vDivider(),
                SizedBox(width: 260, child: _buildNavPane()),
              ],
            ),
          ),
          _buildStatusBar(),
        ],
      ),
    );
  }

  Widget _vDivider() => Container(
        width: 1,
        color: FluentTheme.of(context).resources.dividerStrokeColorDefault,
      );

  // --- command bar -------------------------------------------------

  Widget _buildCommandBar() {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: FluentTheme.of(context).resources.dividerStrokeColorDefault)),
      ),
      child: Row(
        children: [
          FilledButton(
            onPressed: _newFolder,
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(FluentIcons.folder_horizontal, size: 14),
              SizedBox(width: 6),
              Text('پوشهٔ جدید'),
            ]),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: _syncing
                ? SizedBox(width: 14, height: 14, child: ProgressRing(strokeWidth: 2))
                : const Icon(FluentIcons.refresh),
            onPressed: _syncing ? null : _refresh,
          ),
          const Spacer(),
          ToggleButton(
            checked: _viewMode == ViewMode.icons,
            onChanged: (v) => setState(() => _viewMode = ViewMode.icons),
            child: const Icon(FluentIcons.grid_view_medium),
          ),
          const SizedBox(width: 4),
          ToggleButton(
            checked: _viewMode == ViewMode.list,
            onChanged: (v) => setState(() => _viewMode = ViewMode.list),
            child: const Icon(FluentIcons.list),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressBar() {
    final trail = _breadcrumbTrail;
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: FluentTheme.of(context).resources.dividerStrokeColorDefault)),
      ),
      alignment: Alignment.centerRight,
      child: Row(
        children: [
          const Icon(FluentIcons.home, size: 14),
          const SizedBox(width: 6),
          const Text('Saved Messages'),
          if (_atUncategorized) ...[
            const SizedBox(width: 6),
            const Icon(FluentIcons.chevron_left, size: 10),
            const SizedBox(width: 6),
            const Text('دسته‌بندی‌نشده', style: TextStyle(fontWeight: FontWeight.w600)),
          ] else
            for (final f in trail) ...[
              const SizedBox(width: 6),
              const Icon(FluentIcons.chevron_left, size: 10),
              const SizedBox(width: 6),
              Text(f.name,
                  style: f == trail.last ? const TextStyle(fontWeight: FontWeight.w600) : null),
            ],
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    final count = _currentItemCount;
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: FluentTheme.of(context).resources.dividerStrokeColorDefault)),
      ),
      alignment: Alignment.centerRight,
      child: Text('$count مورد', style: FluentTheme.of(context).typography.caption),
    );
  }

  int get _currentItemCount {
    if (_atUncategorized) return ManifestService.instance.uncategorizedMessages.length;
    return _manifest.childrenOf(_currentFolderId).length +
        _manifest.itemsInFolder(_currentFolderId).length;
  }

  // --- nav pane ------------------------------------------------------

  Widget _buildNavPane() {
    return Container(
      color: FluentTheme.of(context).micaBackgroundColor,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: ListView(
        children: [
          _navRow(
            icon: FluentIcons.inbox,
            label: 'دسته‌بندی‌نشده',
            badge: ManifestService.instance.uncategorizedMessages.length,
            active: _atUncategorized,
            onTap: _openUncategorized,
            accentBar: true,
          ),
          const SizedBox(height: 4),
          ..._manifest.childrenOf(null).map((f) => _navFolder(f, depth: 0)),
        ],
      ),
    );
  }

  Widget _navFolder(ManifestFolder folder, {required int depth}) {
    final children = _manifest.childrenOf(folder.id);
    final expanded = _expandedFolders.contains(folder.id);
    return Column(
      children: [
        DragTarget<Object>(
          onWillAcceptWithDetails: (d) => true,
          onAcceptWithDetails: (d) => _handleDrop(d.data, folder.id),
          builder: (context, candidate, rejected) => _navRow(
            icon: children.isNotEmpty
                ? (expanded ? FluentIcons.chevron_down : FluentIcons.chevron_left)
                : null,
            folderColorIcon: true,
            label: folder.name,
            active: !_atUncategorized && _currentFolderId == folder.id,
            depth: depth,
            highlighted: candidate.isNotEmpty,
            onTap: () => _openFolder(folder.id),
            onChevronTap: children.isNotEmpty
                ? () => setState(() {
                      expanded ? _expandedFolders.remove(folder.id) : _expandedFolders.add(folder.id);
                    })
                : null,
          ),
        ),
        if (expanded)
          ...children.map((c) => _navFolder(c, depth: depth + 1)),
      ],
    );
  }

  Widget _navRow({
    IconData? icon,
    bool folderColorIcon = false,
    required String label,
    int? badge,
    bool active = false,
    bool highlighted = false,
    bool accentBar = false,
    int depth = 0,
    VoidCallback? onTap,
    VoidCallback? onChevronTap,
  }) {
    final accent = FluentTheme.of(context).accentColor;
    return Padding(
      padding: EdgeInsets.only(right: depth * 16.0),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 34,
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: active || highlighted ? accent.withOpacity(0.15) : null,
            border: accentBar ? Border(right: BorderSide(color: accent, width: 3)) : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              if (onChevronTap != null)
                GestureDetector(
                  onTap: onChevronTap,
                  child: Icon(icon, size: 10),
                )
              else if (icon != null)
                Icon(icon, size: 14, color: accent.normal),
              if (folderColorIcon) ...[
                const SizedBox(width: 4),
                const FolderIcon(size: 16),
              ],
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: active ? TextStyle(color: accent.dark, fontWeight: FontWeight.w600) : null),
              ),
              if (badge != null && badge > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(9)),
                  child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 10)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleDrop(Object data, String targetFolderId) {
    if (data is CachedMessage) {
      ManifestService.instance.fileMessageIntoFolder(data, targetFolderId);
    } else if (data is ManifestItem) {
      data.folderId = targetFolderId;
      ManifestService.instance.pushManifest();
    }
  }

  // --- content ---------------------------------------------------------

  Widget _buildContent() {
    final folders = _atUncategorized ? <ManifestFolder>[] : _manifest.childrenOf(_currentFolderId);
    final items = _atUncategorized
        ? <Object>[...ManifestService.instance.uncategorizedMessages]
        : <Object>[..._manifest.itemsInFolder(_currentFolderId)];

    final entries = <Object>[...folders, ...items];

    if (entries.isEmpty) {
      return const Center(
        child: Text('این پوشه خالی است', style: TextStyle(color: Colors.grey)),
      );
    }

    return _viewMode == ViewMode.icons ? _iconGrid(entries) : _listView(entries);
  }

  Widget _iconGrid(List<Object> entries) {
    return GridView.builder(
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 116,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 0.85,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) => _tile(entries[i]),
    );
  }

  Widget _tile(Object entry) {
    final isFolder = entry is ManifestFolder;
    final name = isFolder
        ? (entry as ManifestFolder).name
        : entry is ManifestItem
            ? entry.displayName
            : (entry as CachedMessage).fileName;
    final selected = identical(_selected, entry);

    Widget content = GestureDetector(
      onTap: () => setState(() => _selected = entry),
      onDoubleTap: isFolder ? () => _openFolder((entry as ManifestFolder).id) : null,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? FluentTheme.of(context).accentColor.withOpacity(0.15) : null,
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            isFolder ? const FolderIcon(size: 48) : FileTypeIcon(fileName: name, size: 44),
            const SizedBox(height: 6),
            Text(name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );

    if (!isFolder) {
      content = Draggable<Object>(
        data: entry,
        feedback: Opacity(
          opacity: 0.8,
          child: SizedBox(width: 90, child: content),
        ),
        childWhenDragging: Opacity(opacity: 0.4, child: content),
        child: content,
      );
    }
    return content;
  }

  Widget _listView(List<Object> entries) {
    return ListView.builder(
      itemCount: entries.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: FluentTheme.of(context).resources.dividerStrokeColorDefault)),
            ),
            child: const Row(children: [
              Expanded(flex: 4, child: Text('نام', style: TextStyle(fontWeight: FontWeight.w600))),
              Expanded(flex: 2, child: Text('تاریخ ویرایش', style: TextStyle(fontWeight: FontWeight.w600))),
              Expanded(flex: 2, child: Text('نوع', style: TextStyle(fontWeight: FontWeight.w600))),
              Expanded(flex: 2, child: Text('اندازه', style: TextStyle(fontWeight: FontWeight.w600))),
            ]),
          );
        }
        final entry = entries[i - 1];
        final isFolder = entry is ManifestFolder;
        final name = isFolder
            ? (entry as ManifestFolder).name
            : entry is ManifestItem
                ? entry.displayName
                : (entry as CachedMessage).fileName;
        final date = isFolder
            ? null
            : entry is ManifestItem
                ? entry.addedAt
                : (entry as CachedMessage).date;
        final size = entry is ManifestItem
            ? entry.sizeBytes
            : entry is CachedMessage
                ? entry.sizeBytes
                : null;
        final selected = identical(_selected, entry);

        return GestureDetector(
          onTap: () => setState(() => _selected = entry),
          onDoubleTap: isFolder ? () => _openFolder((entry as ManifestFolder).id) : null,
          child: Container(
            color: selected ? FluentTheme.of(context).accentColor.withOpacity(0.15) : null,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Row(children: [
                    isFolder ? const FolderIcon(size: 18) : FileTypeIcon(fileName: name, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
                Expanded(flex: 2, child: Text(date == null ? '—' : _jalali(date))),
                Expanded(flex: 2, child: Text(isFolder ? 'پوشهٔ فایل' : styleForFileName(name).label)),
                Expanded(flex: 2, child: Text(_formatSize(size))),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- details pane ------------------------------------------------

  Widget _buildDetailsPane() {
    if (_selected == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('یک فایل را برای مشاهدهٔ جزئیات انتخاب کنید',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    final entry = _selected!;
    final isFolder = entry is ManifestFolder;
    final name = isFolder
        ? (entry as ManifestFolder).name
        : entry is ManifestItem
            ? entry.displayName
            : (entry as CachedMessage).fileName;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 160,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: FluentTheme.of(context).micaBackgroundColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: isFolder ? const FolderIcon(size: 60) : FileTypeIcon(fileName: name, size: 56),
          ),
          const SizedBox(height: 12),
          Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          if (!isFolder) ...[
            if (entry is ManifestItem) ...[
              _detailRow('حجم', _formatSize(entry.sizeBytes)),
              _detailRow('تاریخ افزوده‌شدن', _jalali(entry.addedAt)),
              _detailRow('شناسهٔ پیام', '#${entry.telegramMessageId}'),
              if (entry.note.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('یادداشت', style: TextStyle(fontSize: 11, color: Colors.grey)),
                Text(entry.note),
              ],
            ] else if (entry is CachedMessage) ...[
              _detailRow('حجم', _formatSize(entry.sizeBytes)),
              _detailRow('تاریخ', _jalali(entry.date)),
              _detailRow('شناسهٔ پیام', '#${entry.messageId}'),
            ],
          ],
        ],
      ),
    );
  }

  Widget _detailRow(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(color: Colors.grey)),
            Text(v),
          ],
        ),
      );

  String _formatSize(int? bytes) {
    if (bytes == null) return '—';
    if (bytes < 1024) return '$bytes بایت';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} کیلوبایت';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} مگابایت';
  }

  String _jalali(DateTime dt) {
    final j = Jalali.fromDateTime(dt);
    return '${j.year}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}';
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
