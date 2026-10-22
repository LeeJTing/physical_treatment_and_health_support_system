import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Text that never breaks a word in two (23 Oct). With large phone text a word wider than its
/// box was split ("Blood press / ure", "Record exercis / e"); here the text is made just small
/// enough for its longest word to fit, and still wraps between words. At normal sizes it is
/// a plain [Text].
class WholeWordsText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;

  const WholeWordsText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final style = DefaultTextStyle.of(context).style.merge(this.style);
      final scaler = MediaQuery.textScalerOf(context);
      final width = box.maxWidth;
      var scaled = scaler;
      if (width.isFinite && width > 0) {
        var longest = 0.0;
        for (final word in text.split(RegExp(r'\s+'))) {
          if (word.isEmpty) continue;
          final tp = TextPainter(
            text: TextSpan(text: word, style: style),
            textDirection: Directionality.of(context),
            textScaler: scaler,
          )..layout();
          longest = math.max(longest, tp.width);
        }
        if (longest > width) {
          final size = style.fontSize ?? 14;
          final now = scaler.scale(size) / size;
          scaled = TextScaler.linear(math.max(0.5, now * width / longest * 0.98));
        }
      }
      return Text(
        text,
        style: this.style,
        textAlign: textAlign,
        maxLines: maxLines,
        textScaler: scaled,
      );
    },
  );
}
