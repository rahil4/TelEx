import 'dart:async';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:fluent_ui/fluent_ui.dart';
import 'theme/app_theme.dart';
import 'services/auth_service.dart';
import 'screens/settings_screen.dart';
import 'screens/login_screen.dart';
import 'screens/explorer_screen.dart';
import 'screens/mobile/mobile_folder_page.dart';

class TelegramExplorerApp extends StatelessWidget {
  const TelegramExplorerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: 'کاوشگر تلگرام',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const _RootRouter(),
    );
  }
}

class _RootRouter extends StatefulWidget {
  const _RootRouter();

  @override
  State<_RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<_RootRouter> {
  AuthStatus _status = AuthStatus.starting;
  late final StreamSubscription<AuthStatus> _sub;

  @override
  void initState() {
    super.initState();
    // Subscribe FIRST, then kick off initialize(). On a cold start with an
    // already-authenticated session, TDLib can resolve straight to "ready"
    // almost instantly — if initialize() were called before this widget
    // (and its subscription) existed, that status change could fire into
    // an empty broadcast stream and be lost forever, leaving the app stuck
    // on the loading spinner. This ordering makes that impossible.
    _sub = AuthService.instance.status.listen((s) {
      if (mounted) setState(() => _status = s);
    });
    _status = AuthService.instance.current;
    AuthService.instance.initialize();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_status) {
      case AuthStatus.starting:
        return ScaffoldPage(
          content: Center(child: ProgressRing()),
        );
      case AuthStatus.needCredentials:
        return const SettingsScreen();
      case AuthStatus.waitPhoneNumber:
      case AuthStatus.waitCode:
      case AuthStatus.waitPassword:
      case AuthStatus.error:
        return LoginScreen(status: _status);
      case AuthStatus.ready:
        final isMobilePlatform = defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS;
        return isMobilePlatform
            ? const MobileFolderPage(title: 'کاوشگر تلگرام')
            : const ExplorerScreen();
      case AuthStatus.loggingOut:
        return const ScaffoldPage(
          content: Center(child: Text('در حال خروج…')),
        );
    }
  }
}
