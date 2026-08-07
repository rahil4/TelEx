import 'package:fluent_ui/fluent_ui.dart';

/// Two-tone Fluent-style folder icon (matches the yellow folder used across
/// File Explorer), drawn as a small custom painter rather than an asset so
/// the project has zero image dependencies to fetch.
class FolderIcon extends StatelessWidget {
  final double size;
  const FolderIcon({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _FolderPainter()),
    );
  }
}

class _FolderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final back = Paint()..color = const Color(0xFFFFC83D);
    final front = Paint()..color = const Color(0xFFFFB300);

    final tab = Path()
      ..moveTo(w * 0.08, h * 0.30)
      ..lineTo(w * 0.08, h * 0.22)
      ..quadraticBezierTo(w * 0.08, h * 0.18, w * 0.14, h * 0.18)
      ..lineTo(w * 0.38, h * 0.18)
      ..lineTo(w * 0.48, h * 0.28)
      ..lineTo(w * 0.86, h * 0.28)
      ..quadraticBezierTo(w * 0.92, h * 0.28, w * 0.92, h * 0.34)
      ..lineTo(w * 0.92, h * 0.40)
      ..lineTo(w * 0.08, h * 0.40)
      ..close();
    canvas.drawPath(tab, back);

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.06, h * 0.38, w * 0.88, h * 0.46),
      Radius.circular(w * 0.05),
    );
    canvas.drawRRect(body, front);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class FileTypeStyle {
  final Color color;
  final String label;
  const FileTypeStyle(this.color, this.label);
}

const Map<String, FileTypeStyle> kFileTypeStyles = {
  'dwg': FileTypeStyle(Color(0xFF2B6CA8), 'DWG'),
  'dxf': FileTypeStyle(Color(0xFF2B6CA8), 'DXF'),
  'pdf': FileTypeStyle(Color(0xFFC42B1C), 'PDF'),
  'doc': FileTypeStyle(Color(0xFF185ABD), 'DOC'),
  'docx': FileTypeStyle(Color(0xFF185ABD), 'DOC'),
  'xls': FileTypeStyle(Color(0xFF107C41), 'XLS'),
  'xlsx': FileTypeStyle(Color(0xFF107C41), 'XLS'),
  'csv': FileTypeStyle(Color(0xFF107C41), 'CSV'),
  'jpg': FileTypeStyle(Color(0xFF7A4FA3), 'JPG'),
  'jpeg': FileTypeStyle(Color(0xFF7A4FA3), 'JPG'),
  'png': FileTypeStyle(Color(0xFF7A4FA3), 'PNG'),
  'mp3': FileTypeStyle(Color(0xFF5F5E5C), 'MP3'),
  'ogg': FileTypeStyle(Color(0xFF5F5E5C), 'AUD'),
  'mp4': FileTypeStyle(Color(0xFF5F5E5C), 'VID'),
};

FileTypeStyle styleForFileName(String fileName) {
  final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
  return kFileTypeStyles[ext] ?? const FileTypeStyle(Color(0xFF5F5E5C), 'FILE');
}

/// Colored rounded-rect file-type icon with a folded corner + short label,
/// mirroring the desktop Explorer mockup.
class FileTypeIcon extends StatelessWidget {
  final String fileName;
  final double size;
  const FileTypeIcon({super.key, required this.fileName, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final style = styleForFileName(fileName);
    final isImage = ['jpg', 'jpeg', 'png'].contains(
      fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '',
    );
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: style.color,
              borderRadius: BorderRadius.circular(size * 0.12),
            ),
          ),
          if (isImage)
            Positioned(
              left: size * 0.14,
              top: size * 0.18,
              child: Icon(FluentIcons.picture_center, size: size * 0.32, color: Colors.white.withOpacity(0.9)),
            )
          else
            Center(
              child: Text(
                style.label,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: size * 0.22,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
