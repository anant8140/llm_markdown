import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';

/// How fast streamed text is revealed.
///
/// Replies arrive in uneven bursts. [Smoothing.adaptive] reveals them at a
/// steady pace instead, and speeds up when text is waiting, so the view
/// never falls more than about [maxLag] behind what has arrived.
@immutable
class Smoothing {
  /// Shows text as soon as it arrives.
  const Smoothing.none()
    : enabled = false,
      charactersPerSecond = 0,
      maxLag = Duration.zero,
      fadeLength = 0;

  /// Reveals text at no less than [charactersPerSecond], and faster when
  /// more text is waiting than can be shown within [maxLag].
  ///
  /// The last [fadeLength] characters fade in as they appear; 0 turns the
  /// fade off.
  const Smoothing.adaptive({
    this.charactersPerSecond = 120,
    this.maxLag = const Duration(milliseconds: 500),
    this.fadeLength = 12,
  }) : enabled = true,
       assert(charactersPerSecond > 0, 'charactersPerSecond must be > 0');

  /// Whether text is revealed gradually.
  final bool enabled;

  /// The slowest reveal speed, in UTF-16 code units per second.
  final double charactersPerSecond;

  /// About how far the view may fall behind the text that has arrived.
  final Duration maxLag;

  /// How many of the newest characters fade in.
  final int fadeLength;

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
      other.fadeLength == fadeLength;

  @override
  int get hashCode =>
      Object.hash(enabled, charactersPerSecond, maxLag, fadeLength);
}

int graphemeBoundaryAtOrAfter(String text, int index) {
  if (index <= 0) return 0;
  if (index >= text.length) return text.length;
  final range = CharacterRange.at(text, index);
  return text.length - range.stringAfterLength;
}
