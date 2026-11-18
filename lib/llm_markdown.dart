/// Markdown for text that arrives in pieces, such as AI chat replies.
///
/// [StreamingMarkdown] shows the text as it grows: finished blocks are built
/// once and kept, unfinished syntax is tidied with [healIncompleteMarkdown],
/// and [Smoothing] reveals bursts at a steady pace.
library;

export 'src/controller.dart' show StreamingMarkdownController;
export 'src/healer.dart' show healIncompleteMarkdown;
export 'src/renderer.dart' show MarkdownCodeBlockBuilder, MarkdownImageBuilder;
export 'src/smoothing.dart' show Smoothing;
export 'src/streaming_markdown.dart' show StreamingMarkdown;
export 'src/style.dart' show StreamingMarkdownStyle;
