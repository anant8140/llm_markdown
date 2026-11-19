/// Markdown for text that arrives in pieces, such as AI chat replies,
/// without any UI: incremental parsing, healing of unfinished syntax, plain
/// text, `<think>` splitting and server-sent events.
///
/// Pure Dart, so it runs on a server, in a CLI and in isolates. The
/// `llm_markdown` package builds its Flutter widget on top of this.
///
/// ```dart
/// final parser = IncrementalMarkdownParser();
/// var text = '';
/// await for (final chunk in chunks) {
///   text += chunk;
///   parser.update(text, complete: false);
///   // parser.frozenBlocks are done; parser.openNodes is the open block
/// }
/// parser.update(text, complete: true);
/// ```
library;

export 'src/block_splitter.dart' show findBlockBoundaries, isBlank;
export 'src/healer.dart' show healIncompleteMarkdown;
export 'src/incremental_parser.dart'
    show FrozenBlock, IncrementalMarkdownParser;
export 'src/math.dart'
    show
        InlineMathSyntax,
        MathBlockSyntax,
        blockMathTag,
        inlineMathTag,
        mathOpenerFor,
        newMarkdownDocument,
        texToUnicode;
export 'src/plain_text.dart' show markdownToPlainText;
export 'src/sse.dart' show ModelStreamError, ServerSentEvent, serverSentEvents;
export 'src/syntaxes.dart'
    show
        AlertSyntax,
        CitationSyntax,
        DetailsBlockSyntax,
        HighlightSyntax,
        MarkdownSyntax,
        SafeHtmlSyntax,
        SchemeAutolinkSyntax,
        SpoilerSyntax,
        citationTag,
        detailsCloser,
        detailsOpener,
        detailsTag,
        spoilerTag;
export 'src/thinking_split.dart' show ThinkingSplit, splitThinking;
