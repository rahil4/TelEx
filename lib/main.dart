import 'package:flutter/widgets.dart';
import 'app.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Not awaited on purpose: the UI reacts to AuthService.status as it
  // changes over time (starting on the Settings screen if no credentials
  // are stored yet, then walking through the login steps).
  // ignore: discarded_futures
  AuthService.instance.initialize();
  runApp(const TelegramExplorerApp());
}
