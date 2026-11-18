/// The thinking part and the answer of a reply.
class ThinkingSplit {
  /// Creates a split.
  const ThinkingSplit(this.thinking, this.answer, {required this.done});

  /// The text inside `<think>`, or null when the reply has none.
  final String? thinking;

  /// The reply after the thinking part.
  final String answer;

  /// Whether the thinking part is over.
  final bool done;
}

const _tags = [('<think>', '</think>'), ('<thinking>', '</thinking>')];
final RegExp _leadingBlankLines = RegExp(r'^(?:[ \t]*\r?\n)+');

/// Splits the `<think>...</think>` part that models such as DeepSeek R1
/// and Qwen put at the start of a reply off the answer.
ThinkingSplit splitThinking(String text, {required bool complete}) {
  final start = text.length - text.trimLeft().length;
  final rest = text.substring(start);
  for (final (open, close) in _tags) {
    if (rest.startsWith(open)) {
      final body = rest.substring(open.length);
      final end = body.indexOf(close);
      if (end == -1) {
        return ThinkingSplit(
          complete ? body : _withoutPartial(body, close),
          '',
          done: complete,
        );
      }
      return ThinkingSplit(
        body.substring(0, end),
        body.substring(end + close.length).replaceFirst(_leadingBlankLines, ''),
        done: true,
      );
    }
  }
  // "<thi" might still become "<think>"
  if (!complete &&
      rest.isNotEmpty &&
      _tags.any((tag) => tag.$1.startsWith(rest))) {
    return const ThinkingSplit('', '', done: false);
  }
  return ThinkingSplit(null, text, done: true);
}

String _withoutPartial(String body, String close) {
  for (var length = close.length - 1; length > 0; length--) {
    if (body.endsWith(close.substring(0, length))) {
      return body.substring(0, body.length - length);
    }
  }
  return body;
}
