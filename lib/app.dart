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

class _RootRouter extends StatelessWidget {
  const _RootRouter();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthStatus>(
      stream: AuthService.instance.status,
      initialData: AuthService.instance.current,
      builder: (context, snapshot) {
        final status = snapshot.data ?? AuthStatus.starting;
        switch (status) {
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
            return LoginScreen(status: status);
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
      },
    );
  }
}
