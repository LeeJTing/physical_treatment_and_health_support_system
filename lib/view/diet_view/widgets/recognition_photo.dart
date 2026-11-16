import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';

/// Normalised regions are painted on the full, uncropped photo.
class RecognitionPhoto extends StatefulWidget {
  final Uint8List bytes;
  final List<MealItem> items;
  const RecognitionPhoto({super.key, required this.bytes, required this.items});
  @override
  State<RecognitionPhoto> createState() => _RecognitionPhotoState();
}

class _RecognitionPhotoState extends State<RecognitionPhoto> {
  double? _ratio;
  @override
  void initState() {
    super.initState();
    _readRatio();
  }

  @override
  void didUpdateWidget(covariant RecognitionPhoto old) {
    super.didUpdateWidget(old);
    if (old.bytes != widget.bytes) {
      _ratio = null;
      _readRatio();
    }
  }

  Future<void> _readRatio() async {
    final bytes = widget.bytes;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        final ratio = frame.image.width / frame.image.height;
        frame.image.dispose();
        if (mounted && identical(bytes, widget.bytes)) {
          setState(() => _ratio = ratio);
        }
      } finally {
        codec.dispose();
      }
    } catch (_) {
      /* Image.memory presents its readable fallback. */
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final ratio = _ratio ?? 1;
      final width = math.min(c.maxWidth, 320 * ratio);
      return Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            width: width,
            height: width / ratio,
            child: CustomPaint(
              foregroundPainter: _ratio == null
                  ? null
                  : _RegionPainter(widget.items),
              child: Image.memory(
                widget.bytes,
                fit: BoxFit.contain,
                semanticLabel: 'Meal photo with numbered food regions',
                errorBuilder: (_, _, _) =>
                    const Center(child: Text('Photo preview unavailable')),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _RegionPainter extends CustomPainter {
  final List<MealItem> items;
  _RegionPainter(this.items);
  @override
  void paint(Canvas canvas, Size size) {
    final border = Paint()
      ..color = AppTokens.brandDeep
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var i = 0; i < items.length; i++) {
      for (final box
          in items[i].recognitionDetails?.boxes ?? const <List<double>>[]) {
        final rect = Rect.fromLTRB(
          box[1] * size.width,
          box[0] * size.height,
          box[3] * size.width,
          box[2] * size.height,
        );
        canvas.drawRect(rect, border);
        final text = TextPainter(
          text: TextSpan(
            text: '${i + 1}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final label = Rect.fromLTWH(
          rect.left.clamp(
            0.0,
            (size.width - text.width - 8).clamp(0.0, size.width),
          ),
          rect.top.clamp(
            0.0,
            (size.height - text.height - 4).clamp(0.0, size.height),
          ),
          text.width + 8,
          text.height + 4,
        );
        canvas.drawRect(label, Paint()..color = AppTokens.brandDeep);
        text.paint(canvas, Offset(label.left + 4, label.top + 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RegionPainter old) => old.items != items;
}
