/// The text side of llm_markdown, without widgets: incremental parsing,
/// healing of unfinished Markdown, and plain text.
///
/// Nothing here imports Flutter, so it can run in a background isolate or
/// in tests without a widget binding.
///
/// ```dart
/// final parser = IncrementalMarkdownParser();
/// for (final chunk in chunks) {
///   text += chunk;
///   parser.update(text, complete: false);
///   // parser.frozenBlocks are done; parser.openNodes is the open block
/// }
/// parser.update(text, complete: true);
/// ```
library;

export 'src/healer.dart' show healIncompleteMarkdown;
export 'src/incremental_parser.dart'
    show FrozenBlock, IncrementalMarkdownParser;
export 'src/math.dart' show newMarkdownDocument, texToUnicode;
export 'src/plain_text.dart' show markdownToPlainText;
export 'src/syntaxes.dart' show MarkdownSyntax;
export 'src/thinking_split.dart' show ThinkingSplit, splitThinking;
