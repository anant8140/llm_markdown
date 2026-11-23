/// Markdown for text that arrives in pieces, such as AI chat replies.
///
/// [StreamingMarkdown] shows the text as it grows: finished blocks are built
/// once and kept, unfinished syntax is tidied with [healIncompleteMarkdown],
/// and [Smoothing] reveals bursts at a steady pace.
library;

export 'package:llm_markdown_parser/llm_markdown_parser.dart'
    show
        MarkdownSyntax,
        ModelStreamError,
        ServerSentEvent,
        healIncompleteMarkdown,
        markdownToPlainText,
        serverSentEvents;

export 'src/adapters.dart' show ModelStreams;
export 'src/code_options.dart'
    show
        CodeActionsBuilder,
        CodeBlockOptions,
        CodeCopyButtonBuilder,
        CodeThemes;
export 'src/controller.dart'
    show MarkdownSource, MarkdownToolCall, StreamingMarkdownController;
export 'src/extras.dart'
    show CopyReplyButton, JumpToLatest, JumpToLatestBuilder, MarkdownShimmer;
export 'src/headings.dart' show MarkdownHeading, MarkdownHeadings;
export 'src/safety.dart' show defaultImageSchemes, defaultLinkSchemes;
export 'src/labels.dart' show MarkdownLabels;
export 'src/mermaid/mermaid_view.dart' show MermaidDiagram;
export 'src/renderer.dart'
    show
        MarkdownCodeBlockBuilder,
        MarkdownCursorBuilder,
        MarkdownElementBuilder,
        MarkdownImageBuilder,
        MarkdownImageTapCallback,
        MarkdownMathBuilder,
        StreamingCursorStyle;
export 'src/selection.dart'
    show
        MarkdownSelectionAction,
        MarkdownSelectionArea,
        MarkdownSelectionMenuBuilder,
        MarkdownSelectionMenuItem;
export 'src/smoothing.dart' show RevealUnit, Smoothing;
export 'src/streaming_markdown.dart' show StreamingMarkdown;
export 'src/style.dart'
    show MarkdownDiagramStyle, StreamingMarkdownStyle, StreamingMarkdownTheme;
export 'src/thinking.dart'
    show MarkdownThinking, MarkdownThinkingBuilder, ThinkingLabelBuilder;
export 'src/tool_calls.dart' show MarkdownToolCallBuilder;
