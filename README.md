# llm_markdown

[![pub](https://img.shields.io/pub/v/llm_markdown.svg)](https://pub.dev/packages/llm_markdown)
[![points](https://img.shields.io/pub/points/llm_markdown)](https://pub.dev/packages/llm_markdown/score)
[![likes](https://img.shields.io/pub/likes/llm_markdown)](https://pub.dev/packages/llm_markdown/score)
[![CI](https://github.com/anant8140/llm_markdown/actions/workflows/ci.yml/badge.svg)](https://github.com/anant8140/llm_markdown/actions/workflows/ci.yml)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Markdown widget for chat apps that stream replies from an LLM.

<img src="https://raw.githubusercontent.com/anant8140/llm_markdown/main/doc/demo.gif" width="320" alt="A reply streaming in: a thinking section, math, a code block and a checklist">

If you render a streaming reply with a regular Markdown widget, the whole
text is parsed again on every chunk. That gets slow on long answers, you see
raw `**` and backticks until the closing ones arrive, and code blocks flicker
when they get highlighted.

This package fixes that:

- Only the last unfinished block is parsed again. Finished blocks are built
  once and cached.
- Unfinished syntax is closed before rendering, so `**bold`, an open code
  fence or a half-typed `[link](https://...` already looks right. Tables show
  up once the header row is done.
- Text is revealed at a steady speed instead of in bursts, and it speeds up
  if it falls behind.
- Code blocks have a copy button and get syntax highlighting once closed.
- LaTeX math: `$...$`, `\(...\)`, `$$...$$` and `\[...\]`. Prices like
  "$5 and $10" are left alone.
- Reasoning from `<think>...</think>` (DeepSeek, Qwen, ...) or from a separate
  reasoning stream goes into a collapsible "Thought for 12s" section.
- The newest characters fade in as they appear.
- Screen readers don't read half sentences; the reply is announced once
  it's done. Arabic, Hebrew and other right-to-left text gets the right
  direction per paragraph, even in a left-to-right app.
- Optional auto-scroll that stops when the user scrolls up to read, and a
  "jump to latest" button.
- GitHub extras: alerts (`> [!NOTE]`), footnotes, task lists, tables,
  `<details>`, plus citation chips (`[1]`), `==highlight==`, `||spoiler||`,
  `:emoji:` and a few safe HTML tags.
- Code blocks with line numbers, wrapping, collapsing, 13 themes and your
  own header buttons.
- Find-in-chat highlighting, a table of contents, image zoom, previews with
  `maxLines`, and a sliver mode for very long replies.
- Your own syntaxes and widgets for any element.
- Depends only on `flutter/widgets.dart`, so it works with `material_ui`, the
  old `flutter/material.dart`, Cupertino or no design library at all.

It doesn't talk to any model API. You give it text, it renders it.

## Install

```sh
flutter pub add llm_markdown
```

## Usage

With a controller:

```dart
final controller = StreamingMarkdownController();

// build()
StreamingMarkdown(controller: controller)

// when the reply comes in
await for (final chunk in model.generate(prompt)) {
  controller.append(chunk);
}
controller.complete();
```

`controller.addStream(stream)` does the loop for you. `controller.text` has
the full markdown, e.g. for a "copy reply" button.

Straight from a stream:

```dart
StreamingMarkdown.stream(replyStream)
```

A stream can only be listened to once, so inside a `ListView` (items get
disposed when they scroll away) keep a controller per message instead.

Or from text you already keep in your state:

```dart
StreamingMarkdown.text(message.text, isComplete: message.done)
```

If the new text starts with the old one, only the added part is processed.

### Math

Formulas are found and kept intact while they stream; drawing them is up to
you, so you can pick the math package. With
[`flutter_math_fork`](https://pub.dev/packages/flutter_math_fork):

```dart
StreamingMarkdown(
  controller: controller,
  mathBuilder: (context, tex, display) => Math.tex(
    tex,
    mathStyle: display ? MathStyle.display : MathStyle.text,
  ),
)
```

A formula that is still arriving shows its source until it's closed. Without
a `mathBuilder` the source is shown.

### Thinking

If the reply starts with `<think>...</think>`, that part goes into a section
above the answer. It shows "Thinking..." while it streams and "Thought for
Ns" after. For APIs that send reasoning separately:

```dart
controller.appendThinking(reasoningChunk);
controller.append(answerChunk);
```

`showThinking: false` drops it, `thinkingInitiallyExpanded: true` opens it,
and `thinkingLabel` changes the title (e.g. to translate it).

### Chat list

```dart
SelectionArea(
  child: ListView(
    controller: scrollController,
    children: [
      for (final message in messages)
        StreamingMarkdown(
          controller: message.controller,
          autoScrollController: scrollController,
        ),
    ],
  ),
)
```

`SelectionArea` comes from your design library and makes the text
selectable. With `ListView(reverse: true)` you don't need
`autoScrollController`.

## Options

| Option | Default | |
| --- | --- | --- |
| `smoothing` | `Smoothing.adaptive()` | also `.none()`, `.gentle()`, `.fast()`, `.typewriter()`, `.wordByWord()`; `fadeLength: 0` turns the fade off |
| `style` | from context | see [Styling](#styling) |
| `onLinkTap` | – | called with the link URL |
| `allowedLinkSchemes` / `allowedImageSchemes` | http, https, mailto, tel / http, https | other links show as text |
| `onCitationTap` | – | called with `1` for a `[1]` chip |
| `imageBuilder` | `Image.network` | |
| `onImageTap` / `zoomImages` | – / `true` | a tap opens the image full screen with pinch-to-zoom |
| `codeBlockBuilder` | built-in | return `null` to fall back to the default |
| `codeBlocks` | `CodeBlockOptions()` | see [Code blocks](#code-blocks) |
| `highlightCode` | `true` | |
| `mathBuilder` | – | draws LaTeX, see above; without it math shows as Unicode (`x²`, `α`) |
| `showThinking` / `thinkingInitiallyExpanded` / `thinkingLabel` | `true` / `false` / English | |
| `showCursor` / `cursorStyle` | `true` / block | also bar, underline, dots |
| `placeholder` | – | shown until the first text arrives, e.g. `MarkdownShimmer()` |
| `errorBuilder` | – | shown after `controller.completeWithError(error)` |
| `onComplete` / `onTextChanged` | – | |
| `tapToSkip` | `false` | a tap shows the rest of the reply at once |
| `updateInterval` | every frame | rebuild less often on slow phones |
| `fadeBottomEdge` | `false` | fade the last line while text arrives |
| `newlinesAsBreaks` | `false` | treat a single newline as a line break |
| `autoScrollController` | – | follow the reply while at the bottom |
| `headings` | – | a `MarkdownHeadings` for a table of contents |
| `searchQuery` / `searchHighlightColor` | – | marks matches, ignoring case |
| `maxLines` / `fadeOverflow` | – / `true` | previews |
| `sliver` | `false` | builds blocks lazily inside a `CustomScrollView` |
| `syntax` | everything on | `MarkdownSyntax(dollarMath: false, ...)`, your own syntaxes |
| `elementBuilders` | – | your widget for any element, by tag |
| `announceWhenDone` | `true` | screen readers read the reply when it ends |
| `detectTextDirection` | `true` | per-paragraph direction from the first letter |

The controller can `pause()`, `resume()`, `skipAnimation()` and `replay()`,
and reads model streams directly:

```dart
// the raw bytes of a streaming response, reasoning included
await controller.addOpenAIStream(response.stream);
await controller.addAnthropicStream(response.stream);
```

### Code blocks

```dart
StreamingMarkdown(
  controller: controller,
  codeBlocks: CodeBlockOptions(
    lineNumbers: true,
    collapseAfterLines: 30,
    highlightWhileStreaming: true,
    actionsBuilder: (context, code, language) => [
      if (language == 'python') TextButton(onPressed: () => run(code), child: Text('Run')),
    ],
  ),
  style: StreamingMarkdownStyle.of(context).copyWith(codeTheme: CodeThemes.githubDark),
)
```

`wrapLines` wraps long lines instead of scrolling sideways, and
`copyButtonBuilder` replaces the copy button. For your own code font, pass
`monospace:` to `StreamingMarkdownStyle.fromColors`, e.g.
`GoogleFonts.jetBrainsMono()`.

### Long replies and chats

```dart
final headings = MarkdownHeadings();

StreamingMarkdown(controller: controller, headings: headings, searchQuery: query);

// a table of contents
for (final heading in headings.headings)
  GestureDetector(onTap: () => headings.scrollTo(heading.id), child: Text(heading.text));

// over the chat list, in a Stack
JumpToLatest(
  controller: scrollController,
  content: controller,
  builder: (context, jump) => FilledButton(onPressed: jump, child: Text('New messages')),
)
```

Headings get GitHub's ids, so `[Setup](#setup)` links scroll too. For a
reply with thousands of lines, `sliver: true` puts the blocks straight into a
`CustomScrollView` and builds only those on screen.

### Your own syntax

Any `package:markdown` syntax can be added, and any element drawn your way:

```dart
StreamingMarkdown(
  controller: controller,
  syntax: MarkdownSyntax(inlineSyntaxes: [MentionSyntax()]),
  elementBuilders: {
    'mention': (context, element, isComplete) => Chip(label: Text('@${element.textContent}')),
    'blockquote': (context, element, isComplete) => null, // null keeps the default
  },
)
```

A custom block syntax must not contain blank lines, because a block is
finished at the first blank line while the reply streams.

### Diagrams, SVG and the selection menu

These are left to packages that do them well:

```dart
// Mermaid: draw the block once its closing fence is there
codeBlockBuilder: (context, code, language, isComplete) {
  if (language != 'mermaid') return null;
  return isComplete ? MermaidView(code) : const Text('Drawing…');
},

// SVG images, with flutter_svg
imageBuilder: (context, uri, alt) => uri.path.endsWith('.svg')
    ? SvgPicture.network(uri.toString(), semanticsLabel: alt)
    : Image.network(uri.toString(), semanticLabel: alt),
```

Copy, "Ask about this" and other selection menu items come from the
`SelectionArea` around the chat: pass it a `contextMenuBuilder`.

### Styling

The default style takes the text style from `DefaultTextStyle` and the accent
(links, checkboxes, cursor) from `DefaultSelectionStyle`. Material and
Cupertino apps set both from their theme. To set it yourself:

```dart
StreamingMarkdownTheme(
  style: StreamingMarkdownStyle.compact(
    textStyle: theme.textTheme.bodyMedium!,
    accentColor: theme.colorScheme.primary,
  ).copyWith(blockPadding: {'h2': EdgeInsets.only(top: 8)}),
  child: chat,
)
```

`StreamingMarkdownTheme` styles every `StreamingMarkdown` below it; a
widget's own `style` wins. Besides `fromColors` there are the `compact`,
`spacious` and `terminal` presets. In a Material app the style can live in a
`ThemeExtension` whose `lerp` calls `StreamingMarkdownStyle.lerp`.

### Without widgets

`package:llm_markdown/parser.dart` has the incremental parser,
`healIncompleteMarkdown`, `markdownToPlainText` and `splitThinking`, and
imports no Flutter, so it runs in a background isolate or in plain tests.

## Performance

A 12,800-character reply streamed in 12-character chunks every 16 ms, on a
Mac Studio in profile mode:

| | build avg | build p90 | worst frame |
| --- | --- | --- | --- |
| llm_markdown | 0.65 ms | 1.56 ms | 16.0 ms |
| `MarkdownBody` with the whole text per chunk | 6.01 ms | 12.53 ms | 16.1 ms |

Phones are slower, so expect both columns to be several times higher there.
To run it yourself: `flutter run --profile -t lib/benchmark.dart` in
`example/`.

## How it works

The text is split into blocks only at points where nothing that comes later
can change the block before it (a blank line before a new paragraph, the end
of a heading, a closing code fence, ...). Those blocks are parsed once with
[`markdown`](https://pub.dev/packages/markdown). The last block is healed and
parsed again whenever new text arrives, at most once per frame.

The tests stream sample replies one character at a time, line by line and in
random chunks, plus a few thousand generated documents and every example of
the CommonMark and GitHub specs, and check that every finished block matches
a normal parse of the full text. Golden images guard the look.

## Limitations

- Once a footnote definition appears, the reply is parsed as a whole again
  (correct, just not incremental).
- Raw HTML is shown as text, apart from `<sub> <sup> <kbd> <mark> <u>
  <ins> <small> <br>` and `<details>`.
- Inline math has to fit on one line.
- Mermaid, SVG and LaTeX layout come from other packages (see above).
- `markdown` 7.3.1 crashes on a link definition ending in a backslash
  (`[a]: /b\`); this package works around it, and shows the text as it is
  if the parser ever throws.

Tested on Flutter 3.35 and 3.50.

## License

MIT
