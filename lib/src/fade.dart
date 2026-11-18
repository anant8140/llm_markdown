import 'package:flutter/widgets.dart';

// Fades the last [length] characters of [spans] in, newest the faintest.
// Called on every frame while text streams, so the characters brighten as
// new ones push them back.
List<InlineSpan> fadeTail(
  List<InlineSpan> spans,
  TextStyle inherited,
  int length,
) {
  if (length <= 0) return spans;
  var fromEnd = 0;

  double alphaAt(int distance) => 0.15 + 0.85 * (distance / length);

  List<InlineSpan> walk(List<InlineSpan> list, TextStyle style) {
    final out = List<InlineSpan>.of(list);
    for (var i = out.length - 1; i >= 0 && fromEnd < length; i--) {
      final span = out[i];
      if (span is! TextSpan) continue;
      final merged = style.merge(span.style);
      final children = span.children == null
          ? null
          : walk(span.children!, merged);

      final text = span.text;
      if (text == null || fromEnd >= length) {
        out[i] = TextSpan(
          text: text,
          style: span.style,
          recognizer: span.recognizer,
          mouseCursor: span.mouseCursor,
          children: children,
        );
        continue;
      }

      final characters = text.characters.toList();
      final keep = (characters.length - (length - fromEnd)).clamp(
        0,
        characters.length,
      );
      final color = merged.color ?? const Color(0xFF000000);
      final tail = <InlineSpan>[];
      for (var c = characters.length - 1; c >= keep; c--) {
        tail.insert(
          0,
          TextSpan(
            text: characters[c],
            style: TextStyle(
              color: color.withValues(alpha: color.a * alphaAt(fromEnd++)),
            ),
            recognizer: span.recognizer,
          ),
        );
      }
      out[i] = TextSpan(
        style: span.style,
        recognizer: span.recognizer,
        mouseCursor: span.mouseCursor,
        children: [
          if (keep > 0)
            TextSpan(
              text: characters.take(keep).join(),
              recognizer: span.recognizer,
            ),
          ...tail,
          ...?children,
        ],
      );
    }
    return out;
  }

  return walk(spans, inherited);
}
