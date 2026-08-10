import 'package:fluent_ui/fluent_ui.dart';
import 'package:open_file/open_file.dart';
import '../../models/manifest.dart';
import '../../services/manifest_service.dart';
import '../widgets/file_icons.dart';
import 'mobile_folder_page.dart';

/// entry is a ManifestItem (already filed) or a CachedMessage (uncategorized).
class MobileFilePage extends StatefulWidget {
  final Object entry;
  const MobileFilePage({super.key, required this.entry});

  @override
  State<MobileFilePage> createState() => _MobileFilePageState();
}

class _MobileFilePageState extends State<MobileFilePage> {
  bool _opening = false;
  String? _openError;
  bool _deleting = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final name = entry is ManifestItem ? entry.displayName : (entry as CachedMessage).fileName;
    final size = entry is ManifestItem ? entry.sizeBytes : (entry as CachedMessage).sizeBytes;
    final date = entry is ManifestItem ? entry.addedAt : (entry as CachedMessage).date;
    final messageId = entry is ManifestItem ? entry.telegramMessageId : (entry as CachedMessage).messageId;
    final note = entry is ManifestItem ? entry.note : '';

    return ScaffoldPage(
      padding: EdgeInsets.zero,
      content: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: FluentTheme.of(context).resources.dividerStrokeColorDefault)),
              ),
              child: Row(
                children: [
                  IconButton(icon: const Icon(FluentIcons.back), onPressed: () => Navigator.of(context).pop()),
                  const Expanded(
                    child: Text('پیش‌نمایش', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    icon: _deleting
                        ? const SizedBox(width: 14, height: 14, child: ProgressRing(strokeWidth: 2))
                        : const Icon(FluentIcons.delete),
                    onPressed: _deleting ? null : _confirmDelete,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  GestureDetector(
                    onTap: _opening ? null : _openFile,
                    child: Container(
                      height: 200,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: FluentTheme.of(context).micaBackgroundColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _opening
                          ? const ProgressRing()
                          : FileTypeIcon(fileName: name, size: 64),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  _row('حجم', _formatSize(size)),
                  _row('تاریخ', '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}'),
                  _row('شناسهٔ پیام', '#$messageId'),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text('یادداشت', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    Text(note),
                  ],
                  if (_openError != null) ...[
                    const SizedBox(height: 14),
                    InfoBar(
                      title: const Text('باز کردن فایل ناموفق بود'),
                      content: Text(_openError!),
                      severity: InfoBarSeverity.error,
                      onClose: () => setState(() => _openError = null),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 46,
                    child: FilledButton(
                      onPressed: _opening ? null : _openFile,
                      child: _opening
                          ? const SizedBox(width: 16, height: 16, child: ProgressRing(strokeWidth: 2))
                          : const Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(FluentIcons.open_file, size: 14),
                              SizedBox(width: 8),
                              Text('باز کردن فایل'),
                            ]),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 46,
                    child: Button(
                      onPressed: _pickFolderAndMove,
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(FluentIcons.move, size: 14),
                        SizedBox(width: 8),
                        Text('انتقال به پوشه'),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
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

  Widget _pickerRow(BuildContext ctx, {required Widget icon, required String label, required String? value}) {
    return GestureDetector(
      onTap: () => Navigator.pop(ctx, value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: FluentTheme.of(ctx).resources.dividerStrokeColorDefault)),
        ),
        child: Row(children: [icon, const SizedBox(width: 10), Expanded(child: Text(label))]),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('حذف فایل'),
        content: const Text('این فایل کاملاً از Saved Messages تلگرام حذف می‌شود و قابل بازگشت نیست. مطمئنی؟'),
        actions: [
          Button(child: const Text('انصراف'), onPressed: () => Navigator.pop(ctx, false)),
          FilledButton(child: const Text('حذف'), onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (confirmed != true) return;

    final entry = widget.entry;
    final messageId = entry is ManifestItem ? entry.telegramMessageId : (entry as CachedMessage).messageId;
    setState(() => _deleting = true);
    try {
      await ManifestService.instance.deleteMessage(messageId);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _deleting = false;
          _openError = 'حذف ناموفق بود: $e';
        });
      }
    }
  }

  Future<void> _openFile() async {
    final entry = widget.entry;
    final messageId = entry is ManifestItem ? entry.telegramMessageId : (entry as CachedMessage).messageId;
    setState(() {
      _opening = true;
      _openError = null;
    });
    try {
      final path = await ManifestService.instance.downloadFileForMessage(messageId);
      final result = await OpenFile.open(path);
      if (result.type != ResultType.done) {
        setState(() => _openError = result.message);
      }
    } catch (e) {
      setState(() => _openError = e.toString());
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _pickFolderAndMove() async {
    final manifest = ManifestService.instance.manifest;
    final folderId = await showDialog<String?>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('انتقال به کدام پوشه؟'),
        content: SizedBox(
          width: double.maxFinite,
          height: 320,
          child: ListView(
            shrinkWrap: true,
            children: [
              _pickerRow(ctx, icon: const Icon(FluentIcons.home, size: 16), label: 'ریشه (بدون پوشه)', value: null),
              for (final f in manifest.folders)
                _pickerRow(ctx, icon: const FolderIcon(size: 18), label: f.name, value: f.id),
            ],
          ),
        ),
        actions: [Button(child: const Text('انصراف'), onPressed: () => Navigator.pop(ctx))],
      ),
    );

    // Navigator.pop(ctx, null) for "root" is indistinguishable from the
    // dialog's own barrier-dismiss (which also returns null). We treat
    // both as "root" here since accidentally filing something to root
    // is harmless and easy to move again.
    final entry = widget.entry;
    if (entry is ManifestItem) {
      entry.folderId = folderId;
      await ManifestService.instance.pushManifest();
    } else if (entry is CachedMessage) {
      await ManifestService.instance.fileMessageIntoFolder(entry, folderId);
    }
    if (mounted) Navigator.of(context).pop();
  }
}
