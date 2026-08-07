import 'package:fluent_ui/fluent_ui.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  final AuthStatus status;
  const LoginScreen({super.key, required this.status});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _controller = TextEditingController();
  bool _busy = false;

  String get _title {
    switch (widget.status) {
      case AuthStatus.waitPhoneNumber:
        return 'شمارهٔ تلفن حساب تلگرام را وارد کن';
      case AuthStatus.waitCode:
        return 'کدی که تلگرام برایت فرستاد را وارد کن';
      case AuthStatus.waitPassword:
        return 'رمز عبور دو مرحله‌ای را وارد کن';
      default:
        return 'در حال اتصال…';
    }
  }

  String get _placeholder {
    switch (widget.status) {
      case AuthStatus.waitPhoneNumber:
        return '+98 912 000 0000';
      case AuthStatus.waitCode:
        return 'کد ۵ رقمی';
      case AuthStatus.waitPassword:
        return 'رمز عبور';
      default:
        return '';
    }
  }

  Future<void> _submit() async {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    setState(() => _busy = true);
    switch (widget.status) {
      case AuthStatus.waitPhoneNumber:
        await AuthService.instance.submitPhoneNumber(value);
        break;
      case AuthStatus.waitCode:
        await AuthService.instance.submitCode(value);
        break;
      case AuthStatus.waitPassword:
        await AuthService.instance.submitPassword(value);
        break;
      default:
        break;
    }
    _controller.clear();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final isPassword = widget.status == AuthStatus.waitPassword;
    return ScaffoldPage(
      content: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_title, style: FluentTheme.of(context).typography.subtitle),
              const SizedBox(height: 20),
              if (widget.status == AuthStatus.error)
                InfoBar(
                  title: Text(AuthService.instance.lastError ?? 'خطایی رخ داد'),
                  severity: InfoBarSeverity.error,
                )
              else ...[
                if (isPassword)
                  PasswordBox(
                    controller: _controller,
                    placeholder: _placeholder,
                    onSubmitted: (_) => _submit(),
                  )
                else
                  TextBox(
                    controller: _controller,
                    placeholder: _placeholder,
                    keyboardType: widget.status == AuthStatus.waitPhoneNumber
                        ? TextInputType.phone
                        : TextInputType.number,
                    onSubmitted: (_) => _submit(),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(width: 16, height: 16, child: ProgressRing(strokeWidth: 2))
                      : const Text('ادامه'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
