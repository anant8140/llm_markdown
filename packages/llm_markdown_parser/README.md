# llm_markdown_parser

Markdown for text that arrives in pieces, such as a streamed LLM reply.
Pure Dart: it runs on a server, in a CLI, in an isolate or in Flutter.

This is the text half of [llm_markdown](https://pub.dev/packages/llm_markdown),
which adds the Flutter widget.

- **Incremental parsing.** Finished blocks are parsed once and kept. Only
  the last, open block is parsed again when text arrives.
- **Healing.** `**bold`, an open code fence or a half-typed
  `[link](https://...` is closed before parsing, so it never shows as raw
  symbols.
- **Plain text** of a reply, for copy, search, notifications or
  text-to-speech.
- **`<think>` splitting** for models that put their reasoning first.
- **Server-sent events** from a byte stream.

## Usage

```dart
import 'package:llm_markdown_parser/llm_markdown_parser.dart';
import 'package:markdown/markdown.dart' as md;

final parser = IncrementalMarkdownParser();
var text = '';
await for (final chunk in chunks) {
  text += chunk;
  parser.update(text, complete: false);
  // parser.frozenBlocks never change again; parser.openNodes is the
  // block still being written
}
parser.update(text, complete: true);

final html = md.renderToHtml([
  for (final block in parser.frozenBlocks) ...block.nodes,
]);
```

Smaller pieces work on their own:

```dart
healIncompleteMarkdown('Some **bo');            // 'Some **bo**'
markdownToPlainText('# Hi\n\n**Bold** text');   // 'Hi\n\nBold text'
splitThinking('<think>plan</think>Answer', complete: true);
await for (final event in serverSentEvents(response.stream)) { ... }
```

The nodes are [`markdown`](https://pub.dev/packages/markdown) nodes:
GitHub-flavored Markdown plus math (`$...$`, `\[...\]`), alerts,
`<details>`, citations (`[1]`), `==highlight==`, `||spoiler||` and emoji.
`MarkdownSyntax` turns each of them on or off and takes your own syntaxes.

## How it stays correct

The text is cut only where nothing that comes later can change the block
before it. The tests stream sample replies, a few thousand generated
documents and every example of the CommonMark and GitHub specs, and check
that the finished blocks equal a normal parse of the full text.

## License

MIT
