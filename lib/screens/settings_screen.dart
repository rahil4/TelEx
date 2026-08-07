import 'package:fluent_ui/fluent_ui.dart';
import '../services/settings_service.dart';
import '../services/auth_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiIdController = TextEditingController();
  final _apiHashController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    final id = await SettingsService.instance.getApiId();
    final hash = await SettingsService.instance.getApiHash();
    if (id != null) _apiIdController.text = id.toString();
    if (hash != null) _apiHashController.text = hash;
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final id = int.tryParse(_apiIdController.text.trim());
    final hash = _apiHashController.text.trim();
    if (id == null || hash.isEmpty) {
      setState(() => _error = 'شناسه (api_id) باید عدد باشد و رمز (api_hash) نباید خالی باشد.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    await SettingsService.instance.saveCredentials(apiId: id, apiHash: hash);
    await AuthService.instance.initialize();
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: const PageHeader(title: Text('تنظیمات اتصال به تلگرام')),
      content: Padding(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InfoBar(
                title: const Text('شناسه اتصال شخصی'),
                content: const Text(
                  'برای استفاده از این برنامه به یک api_id و api_hash نیاز داری که '
                  'به‌صورت رایگان و مخصوص حساب خودت از my.telegram.org می‌گیری. '
                  'این مقادیر فقط روی همین دستگاه، به‌صورت رمزنگاری‌شده ذخیره می‌شن.',
                ),
                severity: InfoBarSeverity.info,
              ),
              const SizedBox(height: 20),
              const Text('شناسه برنامه (api_id)'),
              const SizedBox(height: 6),
              TextBox(
                controller: _apiIdController,
                placeholder: 'مثلاً 1234567',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              const Text('رمز برنامه (api_hash)'),
              const SizedBox(height: 6),
              TextBox(
                controller: _apiHashController,
                placeholder: 'رشتهٔ ۳۲ کاراکتری',
              ),
              const SizedBox(height: 20),
              if (_error != null) ...[
                InfoBar(
                  title: Text(_error!),
                  severity: InfoBarSeverity.error,
                ),
                const SizedBox(height: 12),
              ],
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 16, height: 16, child: ProgressRing(strokeWidth: 2))
                    : const Text('ذخیره و ادامه'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
