# llm_markdown

Smooth, flicker-free Markdown for **streaming AI chat replies** in Flutter.

Most apps re-parse and re-draw the whole reply every time a few new
characters arrive. That gets slower as the reply grows, shows raw `**` and
` ``` ` while syntax is unfinished, and makes code blocks flicker.
`llm_markdown` does the work only for the new text:

- **Parses only the new part.** Finished blocks are parsed and built once and
  then kept. Only the last, open block is parsed again.
- **Heals unfinished syntax.** An unclosed code block, `**bold`, `` `code ``
  or `[link](https://exa` shows as it will look, not as raw symbols. A table
  appears once its header row is complete.
- **Smooth reveal.** Uneven bursts from the model are shown at a steady
  pace, which speeds up automatically so the view never lags far behind.
- **Code blocks** with the language name, a copy button and syntax
  highlighting once the block is closed (so it never flickers).
- **Follows the scroll** while the user is at the bottom, and stops when they
  scroll up to read.
- Tables, task lists, quotes, links and images, a streaming cursor, and
  light and dark colors taken from your app.
- **No design-library dependency.** It uses only `package:flutter/widgets.dart`,
  so it works the same with `package:material_ui`, the Material library that
  ships with Flutter, Cupertino, or no design library at all.
- Works with any model or provider: it only needs the text.

## Getting started

```sh
flutter pub add llm_markdown
```

## Usage

### From a stream of chunks

```dart
StreamingMarkdown.stream(
  replyStream, // Stream<String>
  onLinkTap: (url) => launchUrl(Uri.parse(url)),
)
```

### With a controller

```dart
final controller = StreamingMarkdownController();

// In build():
StreamingMarkdown(controller: controller);

// As the reply arrives:
await for (final chunk in model.generate(prompt)) {
  controller.append(chunk);
}
controller.complete();
```

`controller.text` is the whole Markdown received so far, for example to copy
the full reply.

### From text you already keep in state

```dart
StreamingMarkdown.text(
  message.text,
  isComplete: message.isDone,
)
```

When you rebuild with a longer text that starts with the previous one, only
the new part is processed.

### In a chat list

```dart
ListView(
  controller: scrollController,
  children: [
    for (final message in messages)
      StreamingMarkdown(
        controller: message.controller,
        autoScrollController: scrollController,
      ),
  ],
)
```

With `ListView(reverse: true)` you do not need `autoScrollController`.

## Options

| Option | Default | What it does |
| --- | --- | --- |
| `smoothing` | `Smoothing.adaptive()` | `Smoothing.none()` shows text at once. `charactersPerSecond` and `maxLag` tune the pace. |
| `style` | from context | A `StreamingMarkdownStyle`; see [Styling](#styling). |
| `onLinkTap` | none | Called with the address of a tapped link. |
| `imageBuilder` | `Image.network` | Builds images. |
| `codeBlockBuilder` | built-in | Builds code blocks, for example diagrams; return `null` for the default. |
| `highlightCode` | `true` | Syntax highlighting for closed code blocks. |
| `showCursor` | `true` | A blinking cursor while text arrives. |
| `newlinesAsBreaks` | `false` | Show a single newline as a line break, as many chat apps do. |
| `autoScrollController` | none | Keeps the list at the end while the user is at the bottom. |

## Selecting text

Wrap the chat in your design library's `SelectionArea`, so selection
handles and the copy menu match your app. One area around the whole list
also lets the user select across several messages:

```dart
SelectionArea(
  child: ListView(children: [/* StreamingMarkdown widgets */]),
)
```

## Styling

By default the text follows the surrounding `DefaultTextStyle`, and links,
checked boxes and the cursor use the app's cursor color. Material and
Cupertino apps set both from their theme. To choose the colors yourself:

```dart
final theme = Theme.of(context);

StreamingMarkdown(
  controller: controller,
  style: StreamingMarkdownStyle.fromColors(
    textStyle: theme.textTheme.bodyMedium!,
    accentColor: theme.colorScheme.primary,
  ).copyWith(blockSpacing: 16),
)
```

`healIncompleteMarkdown(text)` is also available on its own if you render
Markdown with another package.

## How it works

1. The text is cut into blocks only where the part before the cut can no
   longer change: a blank line before an independent block, the end of a
   heading line or of a closed code fence.
2. Those blocks are parsed once with the official
   [`markdown`](https://pub.dev/packages/markdown) package (GitHub flavored)
   and their widgets are cached.
3. The open block is healed and parsed again on each frame that has new
   text, and at most once per frame.

The test suite feeds each sample reply in every way it could arrive: one
character at a time, line by line and in random chunks. It checks that no
finished block ever differs from parsing the whole text at once.

## Compatibility

Developed and tested on Flutter 3.50 (the latest stable release). It
also tested on Flutter 3.35, the oldest version it supports.

## Limitations

- Footnotes are placed at the end of their block rather than at the end of
  the reply.
- Raw HTML is shown as text.
- Math (LaTeX) and collapsible "thinking" sections are planned.

## License

MIT
