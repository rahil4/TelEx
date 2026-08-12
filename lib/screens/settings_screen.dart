import 'package:fluent_ui/fluent_ui.dart';
import '../services/settings_service.dart';
import '../services/auth_service.dart';
import 'widgets/ltr_text.dart';

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
    try {
      await SettingsService.instance.saveCredentials(apiId: id, apiHash: hash);
      // Defensive timeout: if connecting to Telegram ever hangs for any
      // reason, this surfaces a clear error instead of a spinner that
      // never stops.
      await AuthService.instance.initialize().timeout(
        const Duration(seconds: 25),
        onTimeout: () => throw Exception('اتصال به تلگرام بیش از حد طول کشید. اینترنت/VPN را چک کن.'),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      padding: EdgeInsets.zero,
      content: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                const Text('تنظیمات اتصال به تلگرام',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 18),
                _card(
                  child: InfoBar(
                    title: const Text('شناسه اتصال شخصی'),
                    content: const Text(
                      'برای استفاده از این برنامه به یک api_id و api_hash نیاز داری که '
                      'به‌صورت رایگان و مخصوص حساب خودت از my.telegram.org می‌گیری. '
                      'این مقادیر فقط روی همین دستگاه، به‌صورت رمزنگاری‌شده ذخیره می‌شن.',
                    ),
                    severity: InfoBarSeverity.info,
                  ),
                ),
                const SizedBox(height: 16),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('شناسه برنامه (api_id)', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 44,
                        child: TextBox(
                          controller: _apiIdController,
                          placeholder: 'مثلاً 1234567',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text('رمز برنامه (api_hash)', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 44,
                        child: TextBox(
                          controller: _apiHashController,
                          placeholder: 'رشتهٔ ۳۲ کاراکتری',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  InfoBar(title: TechnicalText(_error!), severity: InfoBarSeverity.error),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  height: 46,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 16, height: 16, child: ProgressRing(strokeWidth: 2))
                        : const Text('ذخیره و ادامه'),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: FluentTheme.of(context).resources.dividerStrokeColorDefault),
        ),
        child: child,
      );
}
