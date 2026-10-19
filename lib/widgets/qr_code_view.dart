import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

/// [data] as a QR code [size] pixels wide: black on white with the margin
/// scanners need, whatever the theme. [label] is what screen readers say.
class QrCodeView extends StatefulWidget {
  const QrCodeView({
    super.key,
    required this.data,
    required this.label,
    this.size = 200,
  });

  final String data;
  final String label;
  final double size;

  @override
  State<QrCodeView> createState() => _QrCodeViewState();
}

class _QrCodeViewState extends State<QrCodeView> {
  late QrImage _image = _encode(widget.data);

  static QrImage _encode(String data) => QrImage(
    QrCode(
      payload: QrPayload.fromString(data),
      errorCorrectLevel: QrErrorCorrectLevel.medium,
    ),
  );

  @override
  void didUpdateWidget(QrCodeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) _image = _encode(widget.data);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: widget.label,
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(painter: _QrPainter(_image)),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.image);

  final QrImage image;

  /// The light margin around the code, in modules (the standard asks for 4).
  static const _quietZone = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final count = image.moduleCount;
    final module = size.shortestSide / (count + 2 * _quietZone);
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    // One path, so neighbouring modules show no seams between them.
    final dark = Path();
    for (var row = 0; row < count; row++) {
      for (var col = 0; col < count; col++) {
        if (!image.isDark(row, col)) continue;
        dark.addRect(
          Rect.fromLTWH(
            (col + _quietZone) * module,
            (row + _quietZone) * module,
            module,
            module,
          ),
        );
      }
    }
    canvas.drawPath(
      dark,
      Paint()
        ..color = Colors.black
        ..isAntiAlias = false,
    );
  }

  @override
  bool shouldRepaint(_QrPainter oldDelegate) => oldDelegate.image != image;
}
