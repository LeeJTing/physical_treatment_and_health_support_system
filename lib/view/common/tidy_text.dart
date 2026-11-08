import 'package:flutter/material.dart';

/// Text that wraps tidily for older patients reading at large text sizes: the last two words of
/// a sentence stay together, so no line ends with a single word alone below it, and a number stays
/// with its unit ("250 g", "1,600 kcal", "85 %"). The spaces become non-breaking spaces; nothing
/// else changes.
String tidy(String s) {
  var t = s.replaceAllMapped(
    RegExp(r'(\d) (g|kg|mg|kcal|ml|%|min|kcal\.|g\.|mg\.)(?=[\s.,;:)]|$)'),
    (m) => '${m[1]}\u00A0${m[2]}',
  );
  // The last two words of every sentence (and of the whole text) are kept together.
  t = t.replaceAllMapped(RegExp(r' ([^\s\u00A0]{1,20}[.!?:])(?=\s|$)'), (m) => '\u00A0${m[1]}');
  // Text that does not end a sentence (a heading, a label) keeps its last two words together too.
  final end = t.trimRight();
  final i = end.lastIndexOf(' ');
  if (i > 0 && end.split(' ').length >= 3 && !RegExp(r'[.!?:]$').hasMatch(end)) {
    t = '${end.substring(0, i)}\u00A0${end.substring(i + 1)}${t.substring(end.length)}';
  }
  return t;
}

/// A label that always stays on one line, so the words of a button, chip, heading or value line
/// up side by side: at very large text sizes it shrinks a little instead of breaking a word onto
/// a second line.
class OneLineText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final AlignmentGeometry alignment;
  final String? semanticsLabel;
  const OneLineText(this.text, {super.key, this.style, this.alignment = Alignment.centerLeft, this.semanticsLabel});

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: alignment,
    child: Text(text, style: style, maxLines: 1, softWrap: false, semanticsLabel: semanticsLabel),
  );
}

/// A line of facts joined by " · " ("250 g · 410 kcal · 600 mg sodium"): each fact stays whole on
/// one line, and a long line breaks only between facts.
String keepGroups(String s) => s.split(' · ').map((g) => g.replaceAll(' ', '\u00A0')).join(' · ');
