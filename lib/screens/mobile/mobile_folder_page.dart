import 'package:fluent_ui/fluent_ui.dart';
import 'package:shamsi_date/shamsi_date.dart';
import '../../models/manifest.dart';
import '../../services/manifest_service.dart';
import '../../services/auth_service.dart';
import '../widgets/file_icons.dart';
import 'mobile_file_page.dart';

enum _ViewMode { icons, list }

/// A single folder's contents. Root, every subfolder, and the virtual
/// "دسته‌بندی‌نشده" listing all reuse this same page — drilling into a
/// subfolder just pushes another instance of it, so the platform's normal
/// back button/gesture works for free.
class MobileFolderPage extends StatefulWidget {
  final String? folderId; // null = root
  final bool uncategorized;
  final String title;

  const MobileFolderPage({
    super.key,
    this.folderId,
    this.uncategorized = false,
    required this.title,
  });

  @override
  State<MobileFolderPage> createState() => _MobileFolderPageState();
}

class _MobileFolderPageState extends State<MobileFolderPage> {
  _ViewMode _viewMode = _ViewMode.list;
  bool _syncing = false;
  String? _syncError;

  @override
  void initState() {
    super.initState();
    ManifestService.instance.changes.listen((_) {
      if (mounted) setState(() {});
    });
    if (widget.folderId == null && !widget.uncategorized) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _syncing = true;
      _syncError = null;
    });
    await ManifestService.instance.loadFromLocalCache();
    try {
      await ManifestService.instance.sync().timeout(const Duration(seconds: 45));
    } catch (e) {
      _syncError = e.toString();
    }
    if (mounted) setState(() => _syncing = false);
  }

  Manifest get _manifest => ManifestService.instance.manifest;

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
        parentId: widget.uncategorized ? null : widget.folderId,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final folders = widget.uncategorized ? <ManifestFolder>[] : _manifest.childrenOf(widget.folderId);
    final items = widget.uncategorized
        ? <Object>[...ManifestService.instance.uncategorizedMessages]
        : <Object>[..._manifest.itemsInFolder(widget.folderId)];
    final entries = <Object>[...folders, ...items];
    final isRoot = widget.folderId == null && !widget.uncategorized;

    return ScaffoldPage(
      padding: EdgeInsets.zero,
      content: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context, isRoot),
            if (_syncError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: InfoBar(
                  title: const Text('همگام‌سازی ناموفق بود'),
                  content: Text(_syncError!),
                  severity: InfoBarSeverity.warning,
                  onClose: () => setState(() => _syncError = null),
                ),
              ),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text(
                        widget.uncategorized ? 'همه‌چیز دسته‌بندی شده — چیزی اینجا نیست' : 'این پوشه خالی است',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : (_viewMode == _ViewMode.list
                      ? _buildList(entries, isRoot)
                      : _buildGrid(entries, isRoot)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, bool isRoot) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: FluentTheme.of(context).resources.dividerStrokeColorDefault)),
      ),
      child: Row(
        children: [
          if (Navigator.of(context).canPop())
            IconButton(
              icon: const Icon(FluentIcons.back),
              onPressed: () => Navigator.of(context).pop(),
            )
          else
            const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
                if (isRoot)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 6, height: 6, margin: const EdgeInsets.only(left: 5),
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF0F9D58)),
                    ),
                    Text(_syncing ? 'در حال همگام‌سازی…' : 'همگام با تلگرام',
                        style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ]),
              ],
            ),
          ),
          IconButton(
            icon: Icon(_viewMode == _ViewMode.list ? FluentIcons.grid_view_medium : FluentIcons.list),
            onPressed: () => setState(
                () => _viewMode = _viewMode == _ViewMode.list ? _ViewMode.icons : _ViewMode.list),
          ),
          if (isRoot)
            IconButton(
              icon: _syncing
                  ? const SizedBox(width: 14, height: 14, child: ProgressRing(strokeWidth: 2))
                  : const Icon(FluentIcons.refresh),
              onPressed: _syncing ? null : _refresh,
            ),
          if (isRoot)
            IconButton(icon: const Icon(FluentIcons.sign_out), onPressed: _confirmLogOut),
        ],
      ),
    );
  }

  Future<void> _confirmLogOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('خروج از حساب'),
        content: const Text('اتصال به این حساب تلگرام قطع می‌شود. مطمئنی؟'),
        actions: [
          Button(child: const Text('انصراف'), onPressed: () => Navigator.pop(ctx, false)),
          FilledButton(child: const Text('خروج'), onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (confirmed == true) {
      await AuthService.instance.logOut();
    }
  }

  Widget _buildList(List<Object> entries, bool isRoot) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 90),
      itemCount: entries.length + (isRoot ? 1 : 0),
      itemBuilder: (context, i) {
        if (isRoot && i == 0) {
          final count = ManifestService.instance.uncategorizedMessages.length;
          return _rowCard(
            leading: const FolderIcon(size: 30),
            title: 'دسته‌بندی‌نشده',
            subtitle: count > 0 ? '$count مورد جدید' : 'چیزی برای دسته‌بندی نیست',
            accentBar: true,
            onTap: () => Navigator.of(context).push(_slideRoute(
              builder: (_) => const MobileFolderPage(uncategorized: true, title: 'دسته‌بندی‌نشده'),
            )),
          );
        }
        final entry = entries[i - (isRoot ? 1 : 0)];
        return _entryRow(entry);
      },
    );
  }

  Widget _entryRow(Object entry) {
    final isFolder = entry is ManifestFolder;
    final name = isFolder
        ? (entry as ManifestFolder).name
        : entry is ManifestItem
            ? entry.displayName
            : (entry as CachedMessage).fileName;
    final missing = false; // reserved: reconciliation flag surfaced elsewhere
    final subtitle = isFolder
        ? '${_manifest.childrenOf((entry as ManifestFolder).id).length + _manifest.itemsInFolder(entry.id).length} مورد'
        : entry is ManifestItem
            ? _formatSize(entry.sizeBytes)
            : _formatSize((entry as CachedMessage).sizeBytes);

    return _rowCard(
      leading: isFolder ? const FolderIcon(size: 30) : FileTypeIcon(fileName: name, size: 30),
      title: name,
      subtitle: subtitle,
      missing: missing,
      onTap: () {
        if (isFolder) {
          final f = entry as ManifestFolder;
          Navigator.of(context).push(_slideRoute(
            builder: (_) => MobileFolderPage(folderId: f.id, title: f.name),
          ));
        } else {
          Navigator.of(context).push(_slideRoute(
            builder: (_) => MobileFilePage(entry: entry),
          ));
        }
      },
    );
  }

  Widget _rowCard({
    required Widget leading,
    required String title,
    required String subtitle,
    bool accentBar = false,
    bool missing = false,
    required VoidCallback onTap,
  }) {
    final accent = FluentTheme.of(context).accentColor;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: FluentTheme.of(context).resources.dividerStrokeColorDefault),
          boxShadow: (accentBar || missing)
              ? [BoxShadow(color: (missing ? Colors.red : accent).withOpacity(0.6), offset: const Offset(3, 0))]
              : null,
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(subtitle, style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
                ],
              ),
            ),
            const Icon(FluentIcons.chevron_left, size: 10, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(List<Object> entries, bool isRoot) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 90),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 108, mainAxisSpacing: 6, crossAxisSpacing: 6, childAspectRatio: 0.82,
      ),
      itemCount: entries.length + (isRoot ? 1 : 0),
      itemBuilder: (context, i) {
        if (isRoot && i == 0) {
          return _tile(
            leading: const FolderIcon(size: 44),
            label: 'دسته‌بندی‌نشده',
            accent: true,
            onTap: () => Navigator.of(context).push(_slideRoute(
              builder: (_) => const MobileFolderPage(uncategorized: true, title: 'دسته‌بندی‌نشده'),
            )),
          );
        }
        final entry = entries[i - (isRoot ? 1 : 0)];
        final isFolder = entry is ManifestFolder;
        final name = isFolder
            ? (entry as ManifestFolder).name
            : entry is ManifestItem
                ? entry.displayName
                : (entry as CachedMessage).fileName;
        return _tile(
          leading: isFolder ? const FolderIcon(size: 44) : FileTypeIcon(fileName: name, size: 44),
          label: name,
          onTap: () {
            if (isFolder) {
              final f = entry as ManifestFolder;
              Navigator.of(context).push(_slideRoute(
                builder: (_) => MobileFolderPage(folderId: f.id, title: f.name),
              ));
            } else {
              Navigator.of(context).push(_slideRoute(builder: (_) => MobileFilePage(entry: entry)));
            }
          },
        );
      },
    );
  }

  Widget _tile({required Widget leading, required String label, bool accent = false, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(height: 6),
          Text(label,
              textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return '—';
    if (bytes < 1024) return '$bytes بایت';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} کیلوبایت';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} مگابایت';
  }
}

/// Small helper so file entries can carry a Jalali-formatted date without
/// pulling shamsi_date into every call site.
String jalaliOf(DateTime dt) {
  final j = Jalali.fromDateTime(dt);
  return '${j.year}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}';
}

/// Plain PageRouteBuilder with a simple slide-in transition — used instead
/// of a Fluent-specific route class so this doesn't depend on exactly which
/// route helpers the installed fluent_ui version happens to export.
Route<T> _slideRoute<T>({required WidgetBuilder builder}) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final offsetAnimation = Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
      return SlideTransition(position: offsetAnimation, child: child);
    },
    transitionDuration: const Duration(milliseconds: 220),
  );
}
