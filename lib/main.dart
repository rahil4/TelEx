import 'package:flutter/widgets.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // AuthService.instance.initialize() is triggered from inside _RootRouter
  // (app.dart), not here — it subscribes to the auth status stream first
  // and only then starts TDLib, which closes a race where a very fast
  // status change (e.g. resuming an already-authenticated session) could
  // fire before anything was listening and get lost.
  runApp(const TelegramExplorerApp());
}
