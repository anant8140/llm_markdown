## Unreleased

* `StreamingMarkdown.revealLimit`: for replies that are also read aloud,
  the screen shows text only up to a position you move forward from the
  text-to-speech progress, so nothing appears before the voice reaches it.
  Null (the default) changes nothing; smoothing still applies up to the
  limit, lowering it hides text again, and a tap or `skipAnimation()` shows
  everything when the limit hides text; when the voice has caught up, a
  skip only ends the reveal and later text still waits for the voice.

## 0.7.0

* A tool call's line says what the call is about while the model writes it:
  "Using web search  Paris weather". `MarkdownToolCall.argumentsSoFar` and
  `summary` read the arguments as they arrive (with `partial_json`);
  `showToolCallArguments: false` leaves the text out.
* Mermaid: flowcharts, state and class diagrams are drawn in the diagram's
  own colors: `classDef`, `class`, `:::`, `style` and (flowcharts)
  `linkStyle`, with fill, stroke, stroke-width, color and stroke-dasharray.
  Colors are `#rgb`, `#rrggbb`, `#rrggbbaa` or a common CSS name; text on a
  filled node turns black or white when the diagram gives no `color`.
* Mermaid: five more kinds are drawn natively: `gitGraph` (branches as
  lanes, merges, tags, commit types), `journey`, `quadrantChart`,
  `sankey-beta` and `xychart-beta` (bars and lines).
  `MermaidDiagram.supports` is now true for them, so a `codeBlockBuilder`
  that hands unsupported kinds elsewhere no longer gets them.
* `tableBuilder` wraps tables and gets their cells as text
  (`MarkdownTableData`), with `toCsv()` and `toTsv()` for a copy button.
* More HTML tags around plain text: `<b> <strong> <i> <em> <s> <del>
  <strike> <code>`.
* Inline math written as `\( ... \)`, `\[ ... \]` or `$$ ... $$` may run
  over line ends inside a paragraph.
* A closing HTML tag of which only `</` has arrived no longer shows as text.
* New companion packages:
  [llm_markdown_client](https://pub.dev/packages/llm_markdown_client)
  (`addLlmEvents`, for `llm_client`: OpenAI, Anthropic, Gemini, Ollama) and
  [llm_structured_ui](https://pub.dev/packages/llm_structured_ui).

## 0.6.1

* `addStream` stops at once when the reply is completed (a stop button) or
  reset, and cancels the stream, which closes the request behind it; it
  used to wait for the next chunk and to keep reading after `complete`.
* `addStream` and the model adapters on a reply that is already complete
  (stopped while its request was being sent) now cancel the response and
  return; they used to throw on the first chunk and never end.
* `completeAfter`: a reply that grows again after a pause continues where
  it was, instead of being rebuilt from the start.
* New companion package
  [llm_markdown_chat](https://pub.dev/packages/llm_markdown_chat): a ready
  chat screen with message list, input, send and stop, copy and try again.

## 0.6.0

* `StreamingMarkdown.text` takes `completeAfter`: for a text that grows but
  never says when it is done, such as the `responseBuilder` of
  `flutter_ai_toolkit`'s `LlmChatView`, the reply counts as complete once it
  has not grown for that long. Text there at the first build counts as
  complete, so replies from the history show no cursor.
* New companion package
  [llm_markdown_firebase_ai](https://pub.dev/packages/llm_markdown_firebase_ai):
  `addFirebaseAIStream` reads Firebase AI Logic (`firebase_ai`) replies,
  with thinking, function calls and Google Search sources.

## 0.5.0

* `addGeminiStream` reads a Gemini `streamGenerateContent?alt=sse` response;
  thought parts go to the thinking section.
* `addOllamaStream` reads Ollama's `/api/chat` and `/api/generate` streams
  (one JSON object per line), thinking included.
* `addGeminiStream` also reads `streamGenerateContent` without `alt=sse`,
  where the body is one JSON array that arrives piece by piece.
* Tool calls: the controller has `toolCalls` (`startToolCall`,
  `addToolCallArguments`, `finishToolCall`), and every adapter fills it from
  its API's function calls and server tools such as web search. The reply
  shows a "Using web search…" line per call at the top; see
  `showToolCalls`, `toolCallBuilder` and `MarkdownLabels.toolCall`.
* Sources: the controller has `sources` (`addSource`, `MarkdownSource`).
  Anthropic citations, OpenAI `url_citation` annotations and Gemini search
  grounding are collected there, and Anthropic citations put `[n]` chips
  after the text they support.
* Mermaid state diagrams (`stateDiagram` / `stateDiagram-v2`) are drawn: the
  start dot, the end ring, `<<choice>>` diamonds, `state "..." as X`, state
  descriptions and the states inside a composite state.
* Mermaid class diagrams (`classDiagram`) are drawn: classes with their
  fields and methods, `<<interface>>`-style annotations, generics, and the
  inheritance, realization, composition, aggregation, association and
  dependency lines with their own ends.
* Flowchart `subgraph`s are drawn as titled boxes around their nodes, and
  edges to a subgraph end on its box.
* State diagrams draw composite states as boxes around their states, and
  notes (`note right of X`, also over several lines).
* Class diagrams draw notes (`note for X`), and cardinalities near each end
  of the line instead of in the middle.
* New Mermaid kinds are drawn: ER diagrams (`erDiagram`, with attributes and
  crow's-foot ends), gantt charts (`YYYY-MM-DD` dates, day and week
  durations, `after`, done / active / crit / milestone), mindmaps and
  timelines. What they can't read stays a code block.
* A reply ended by the app with `complete()` while an `add...Stream` is
  still reading (a stop button) now stays as it is: the rest of the stream
  is ignored. Before, the next chunk threw a `StateError` out of the
  adapter.
* `reset()` or `complete()` while an `add...Stream` is reading cancels the
  response body right away, which closes its connection, instead of
  waiting for the server's next chunk.
* A streaming code block in a language with no highlighting grammar, such
  as a ` ```mermaid ` block, with `highlightWhileStreaming` on, retried
  the same text without end. On the web that froze the page; elsewhere it
  kept starting background work. It is now tried once per new line.
* Code no longer shows ligatures: the bundled JetBrains Mono drew `<|`, `->`
  or `!=` as one symbol, so code didn't show the characters that were
  written. `StreamingMarkdownStyle.codeFont` turns them off.
* `addOpenAIStream` shows a refusal (`delta.refusal`) as the answer instead
  of an empty reply.
* Two edge labels that would land on one spot, as on a pair of edges going
  both ways between two nodes, no longer cover each other.
* The example app runs on the web, and is published as a live demo:
  https://anant8140.github.io/llm_markdown/. Visitors can paste their own
  Markdown, pick the streaming speed and switch the theme.

## 0.4.1

* The menu of `MarkdownSelectionArea` uses the app's font. On Android, in a
  Material app, it was drawn in a monospace font.

## 0.4.0

* Following the end of a reply (`autoScrollController`) no longer stops
  half way on iOS and macOS. It was lost whenever the reply got a little
  shorter for one frame, for example when a half-typed image was hidden or
  a formula's source became the drawn formula.
* The end is also followed when a picture loads late and makes the reply
  taller without any new text.
* Labels on Mermaid flowchart edges sit in a gap of the line, not on top of
  it.
* A tap anywhere on a drawn SVG opens it, also on a see-through part.
* Nothing about the look is fixed any more:
  * New parts of `StreamingMarkdownStyle`: `highlightColor`, `spoilerColor`,
    `citationDecoration`, `citationTextStyle`, `kbdDecoration`,
    `thinkingStyle`, `imageBarrierColor`, `bullets`, `tableCellPadding` and
    `diagramStyle` (`MarkdownDiagramStyle`: node, line, note and pie colors).
  * `thinkingBuilder` and `cursorBuilder` replace the thinking section and
    the cursor with your own widgets; `elementBuilders['li']` draws list
    items.
  * `MarkdownSelectionArea` takes `menuColor`, `menuTextStyle`,
    `menuBorderRadius`, `handleColor`, or a whole `menuBuilder`.
  * `labels: MarkdownLabels(...)` replaces every built-in word ("Copy",
    "Show code", alert titles, ...), on a widget or for the whole app with
    `StreamingMarkdownTheme(labels: ...)`.
* The example app shows the 0.3.0 features, and the demo GIF is new.

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
