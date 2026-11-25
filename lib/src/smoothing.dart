import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';

/// How fast streamed text is revealed.
///
/// Replies arrive in uneven bursts. [Smoothing.adaptive] reveals them at a
/// steady pace instead, and speeds up when text is waiting, so the view
/// never falls more than about [maxLag] behind what has arrived.
/// What [Smoothing] reveals at a time.
enum RevealUnit {
  /// One letter (grapheme) at a time.
  character,

  /// Whole words only; a word shows once it is complete.
  word,
}

@immutable
class Smoothing {
  /// Shows text as soon as it arrives.
  const Smoothing.none()
    : enabled = false,
      charactersPerSecond = 0,
      maxLag = Duration.zero,
      fadeLength = 0,
      unit = RevealUnit.character;

  /// Reveals text at no less than [charactersPerSecond], and faster when
  /// more text is waiting than can be shown within [maxLag].
  ///
  /// The last [fadeLength] characters fade in as they appear; 0 turns the
  /// fade off.
  const Smoothing.adaptive({
    this.charactersPerSecond = 120,
    this.maxLag = const Duration(milliseconds: 500),
    this.fadeLength = 12,
    this.unit = RevealUnit.character,
  }) : enabled = true,
       assert(charactersPerSecond > 0, 'charactersPerSecond must be > 0');

  /// A steady [charactersPerSecond] that does not speed up, like typing.
  const Smoothing.typewriter({this.charactersPerSecond = 60})
    : enabled = true,
      maxLag = const Duration(days: 1),
      fadeLength = 0,
      unit = RevealUnit.character;

  /// Slow and soft: a long fade and a calm pace.
  const Smoothing.gentle()
    : enabled = true,
      charactersPerSecond = 80,
      maxLag = const Duration(milliseconds: 900),
      fadeLength = 18,
      unit = RevealUnit.character;

  /// Keeps right behind the model with a short fade.
  const Smoothing.fast()
    : enabled = true,
      charactersPerSecond = 300,
      maxLag = const Duration(milliseconds: 200),
      fadeLength = 6,
      unit = RevealUnit.character;

  /// Whole words, one after another.
  const Smoothing.wordByWord()
    : enabled = true,
      charactersPerSecond = 120,
      maxLag = const Duration(milliseconds: 600),
      fadeLength = 10,
      unit = RevealUnit.word;

  /// Whether text is revealed gradually.
  final bool enabled;

  /// The slowest reveal speed, in UTF-16 code units per second.
  final double charactersPerSecond;

  /// About how far the view may fall behind the text that has arrived.
  final Duration maxLag;

  /// How many of the newest characters fade in.
  final int fadeLength;

  /// Whether letters or whole words are revealed.
  final RevealUnit unit;

  /// The reveal speed, in code units per second, when [waiting] code units
  /// have arrived but are not shown yet.
  double speedFor(int waiting) {
    final lagSeconds = maxLag.inMicroseconds / Duration.microsecondsPerSecond;
    if (lagSeconds <= 0) return double.infinity;
    return math.max(charactersPerSecond, waiting / lagSeconds);
  }

  @override
  bool operator ==(Object other) =>
      other is Smoothing &&
      other.enabled == enabled &&
      other.charactersPerSecond == charactersPerSecond &&
      other.maxLag == maxLag &&
      other.fadeLength == fadeLength &&
      other.unit == unit;

  @override
  int get hashCode =>
      Object.hash(enabled, charactersPerSecond, maxLag, fadeLength, unit);
}

int graphemeBoundaryAtOrAfter(String text, int index) {
  if (index <= 0) return 0;
  if (index >= text.length) return text.length;
  final range = CharacterRange.at(text, index);
  return text.length - range.stringAfterLength;
}

final RegExp _space = RegExp(r'\s');

// For RevealUnit.word: the end of the word that [index] falls in, or
// [shown] when that word hasn't fully arrived yet.
int wordBoundaryAtOrAfter(String text, int index, int shown, bool complete) {
  if (index >= text.length) return complete ? text.length : shown;
  if (index > 0 && _space.hasMatch(text[index - 1])) return index;
  final next = text.indexOf(_space, index);
  if (next == -1) return complete ? text.length : shown;
  return next;
}

// For RevealUnit.word: [index] when it falls between words, otherwise the
// start of the word it cuts, so a limit inside a word shows none of it.
int wordBoundaryAtOrBefore(String text, int index) {
  if (index <= 0 || index >= text.length) return index.clamp(0, text.length);
  if (_space.hasMatch(text[index - 1]) || _space.hasMatch(text[index])) {
    return index;
  }
  var start = index;
  while (start > 0 && !_space.hasMatch(text[start - 1])) {
    start--;
  }
  return start;
}
