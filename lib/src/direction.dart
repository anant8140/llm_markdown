import 'package:flutter/widgets.dart';

final RegExp _letter = RegExp(r'\p{L}', unicode: true);
final RegExp _rtl = RegExp(
  r'[֐-ࣿיִ-﷿ﹰ-﻿\u{10800}-\u{10FFF}\u{1E800}-\u{1EFFF}]',
  unicode: true,
);

// Like dir="auto": the first letter decides. Null when there is none.
TextDirection? detectTextDirection(String text) {
  final match = _letter.firstMatch(text);
  if (match == null) return null;
  return _rtl.hasMatch(match[0]!) ? TextDirection.rtl : TextDirection.ltr;
}
