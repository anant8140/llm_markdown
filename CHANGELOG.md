## 0.3.0

* Screen readers skip text that is still arriving and announce the reply
  when it is done (`announceWhenDone`).
* Paragraphs, lists, quotes and tables take their direction from their first
  letter (`detectTextDirection`); code always reads left to right.
* Code highlighting runs in the background and only builds the grammars it
  needs, so the first code block no longer stalls a frame.
* A benchmark in `example/lib/benchmark.dart`.
* Unsafe links (`javascript:`, `file:`, ...) show as text and `data:` images
  aren't loaded (`allowedLinkSchemes`, `allowedImageSchemes`).
* `markdownToPlainText`, `controller.plainText` and a `CopyReplyButton`.
* `tapToSkip`, a `placeholder` such as `MarkdownShimmer` before the first
  token, `errorBuilder` with `controller.completeWithError`, and
  `onComplete` / `onTextChanged`.
* "Reduce motion" turns off the reveal, fade and blinking.
* `controller.pause()`, `resume()`, `skipAnimation()` and `replay()`.
* Reveal presets: `Smoothing.gentle()`, `.fast()`, `.typewriter()` and
  `.wordByWord()` (`RevealUnit.word`).
* Cursor styles (`StreamingCursorStyle`: block, bar, underline, dots),
  `fadeBottomEdge` and `updateInterval`.
* `controller.addOpenAIStream(bytes)` and `addAnthropicStream(bytes)` read
  the raw SSE response body, reasoning included; `serverSentEvents()` for
  other APIs.
* GitHub alerts (`> [!NOTE]` ...), `<details>` sections, citation chips for
  `[1]` (`onCitationTap`), `==highlight==`, `||spoiler||`, `:emoji:`, and a
  few HTML tags (`<sub> <sup> <kbd> <mark> <u> <br>`).
* Footnote references scroll to their note.
* Without a `mathBuilder`, math shows as readable Unicode (`x²`, `α`).
* `MarkdownSyntax` turns extensions on or off, e.g. `dollarMath: false` or
  `autolinks: false`, and adds autolink schemes.
* `codeBlocks: CodeBlockOptions(...)`: line numbers, wrapped lines,
  collapsing long blocks behind "Show all N lines", highlighting while a
  block streams, a custom copy button and extra header buttons such as
  "Run".
* `CodeThemes` with 13 ready-made highlighting themes, and
  `StreamingMarkdownStyle.fromColors(monospace: ...)` for your own code
  font.
* Headings get GitHub style ids, so `[Setup](#setup)` links scroll to
  them; `headings: MarkdownHeadings()` collects them for a table of
  contents and scrolls to one with `scrollTo(id)`.
* `searchQuery` marks matches for find-in-chat.
* Tapping an image opens it full screen with pinch-to-zoom (`zoomImages`),
  or calls `onImageTap`.
* `maxLines` with `fadeOverflow` for previews.
* `sliver: true` makes the widget a sliver that builds blocks lazily, for
  very long replies in a `CustomScrollView`.
* `JumpToLatest` shows a "new messages" button while the user has scrolled
  away from the end.
* Your own syntaxes: `MarkdownSyntax(blockSyntaxes: ..., inlineSyntaxes:
  ...)` from `package:markdown`, and `elementBuilders` to draw any element
  your way, built-in ones included.
* `StreamingMarkdownTheme` gives every widget below it a style;
  `StreamingMarkdownStyle.lerp` for animated theme changes or a Material
  `ThemeExtension`.
* Style presets: `StreamingMarkdownStyle.compact`, `.spacious` and
  `.terminal`.
* `StreamingMarkdownStyle.blockPadding` pads blocks by tag.
* A link definition ending in a backslash (`[a]: /b\`) no longer crashes
  the `markdown` package; any other parser error shows the text as it is.
* Every CommonMark and GitHub spec example is checked to stream exactly like
  a one-shot parse; golden images guard the look.
* Mermaid flowcharts, sequence diagrams and pie charts are drawn, natively,
  once their code block is finished (`diagrams`, `MermaidDiagram`).
* SVG images are drawn (with `flutter_svg`), and `data:` images when that
  scheme is allowed. A broken or missing SVG shows its alt text.
* Code is set in JetBrains Mono, which now comes with the package
  (`StreamingMarkdownStyle.codeFont`).
* `MarkdownSelectionArea` makes replies selectable with a menu of your own
  actions, without a design library.
* The parser moved to the pure Dart package `llm_markdown_parser`, for
  servers and CLIs. `package:llm_markdown/parser.dart` re-exports it.
* Fixes:
  * `[1][2]` next to each other are both citation chips.
  * `a==b && c==d` and `a||b||c` are no longer a highlight or a spoiler,
    and `US$5 ... 5$` is no longer math.
  * A half-typed `</sub>`, `> [!NOTE]`, `[^1]` or `[text][ref]` no longer
    shows stray characters while streaming.
  * An empty `<think></think>` no longer shows an empty thinking section.
  * Math without a `mathBuilder` reads better: nested fractions, `\left(`,
    `\{`, `\%`, `\mathbb{R}`, `\vec{v}`, `\sqrt[3]{x}`; `\frac{1}{2}` is
    now `1/2`.
  * Plain text keeps `[1]` for citations and footnotes, and the title of a
    `<details>` section.
  * A model stream survives a line that isn't JSON (a keep-alive, or an
    event cut off by a dropped connection) and a broken UTF-8 byte.
  * A custom-scheme autolink no longer swallows the full stop after it.

## 0.2.0

* LaTeX math (`$...$`, `\(...\)`, `$$...$$`, `\[...\]`) with a `mathBuilder`
  to draw it. Formulas still streaming show their source.
* Thinking section for `<think>...</think>` replies and
  `StreamingMarkdownController.appendThinking`.
* Newest characters fade in (`Smoothing.adaptive(fadeLength: ...)`).

## 0.1.0

* Initial release.
