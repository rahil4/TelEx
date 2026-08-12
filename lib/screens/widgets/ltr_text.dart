import 'package:fluent_ui/fluent_ui.dart';

/// Wraps technical text (exception messages, JSON payloads, file paths)
/// that must render in strict left-to-right order regardless of the app's
/// global RTL directionality. Without this, Unicode's bidi algorithm
/// reorders "weak"/neutral characters (braces, quotes, colons) when they
/// sit inside an RTL paragraph, making JSON snippets look corrupted even
/// though the underlying string is completely correct — this bit us for
/// real once already, hence the comment.
class TechnicalText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const TechnicalText(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text(text, style: style, textAlign: TextAlign.left),
    );
  }
}
