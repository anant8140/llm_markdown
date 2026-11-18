/// Markdown for text that arrives in pieces, such as AI chat replies.
///
/// [StreamingMarkdown] shows the text as it grows: finished blocks are built
/// once and kept, unfinished syntax is tidied with [healIncompleteMarkdown],
/// and [Smoothing] reveals bursts at a steady pace.
library;

export 'src/adapters.dart'
    show ModelStreamError, ModelStreams, ServerSentEvent, serverSentEvents;
export 'src/controller.dart' show StreamingMarkdownController;
export 'src/extras.dart' show CopyReplyButton, MarkdownShimmer;
export 'src/healer.dart' show healIncompleteMarkdown;
export 'src/plain_text.dart' show markdownToPlainText;
export 'src/safety.dart' show defaultImageSchemes, defaultLinkSchemes;
export 'src/renderer.dart'
    show
        MarkdownCodeBlockBuilder,
        MarkdownImageBuilder,
        MarkdownMathBuilder,
        StreamingCursorStyle;
export 'src/smoothing.dart' show RevealUnit, Smoothing;
export 'src/streaming_markdown.dart' show StreamingMarkdown;
export 'src/style.dart' show StreamingMarkdownStyle;
export 'src/thinking.dart' show ThinkingLabelBuilder;
