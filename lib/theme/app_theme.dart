import 'package:fluent_ui/fluent_ui.dart';

/// Windows lets a person set any accent colour for their system — File
/// Explorer's selection highlight, links, and toggles all follow it. We use
/// that same mechanism to carry the Parshan brand's warm gold through an
/// otherwise fully-native Fluent UI, on both Windows and Android.
final AccentColor goldAccent = AccentColor.swatch(const {
  'darkest': Color(0xFF3d2f1a),
  'darker': Color(0xFF5f4a28),
  'dark': Color(0xFF7c5f30),
  'normal': Color(0xFF96733c),
  'light': Color(0xFFb08d57),
  'lighter': Color(0xFFd9b787),
  'lightest': Color(0xFFf0ddbb),
});

// NOTE: for the exact typography used in the design mockups (Vazirmatn),
// download the font files and register them under pubspec.yaml's `fonts:`
// section, then set `fontFamily: 'Vazirmatn'` below. Left as a follow-up
// since binary font files can't be fetched from this environment — without
// bundling them, Flutter falls back to the platform's default Persian font,
// which still renders correctly.
FluentThemeData buildAppTheme() {
  return FluentThemeData(
    brightness: Brightness.light,
    accentColor: goldAccent,
    visualDensity: VisualDensity.standard,
  );
}
