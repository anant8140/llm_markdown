## 0.2.1

* A code span opened with two or more backticks and cut mid-stream
  (``` ``co` ```) is closed with the same number of backticks, so the raw
  backticks no longer show.

## 0.2.0

* More HTML tags around plain text: `<b> <strong> <i> <em> <s> <del>
  <strike> <code>`, read as the Markdown elements they mean.
* A closing tag of which only `</` has arrived no longer shows as text.
* Inline math written as `\( ... \)`, `\[ ... \]` or `$$ ... $$` may run
  over line ends inside a paragraph. A single `$` still closes on its line.

## 0.1.0

* The parser of `llm_markdown`, as a pure Dart package:
  `IncrementalMarkdownParser`, `healIncompleteMarkdown`,
  `markdownToPlainText`, `splitThinking`, `serverSentEvents` and
  `MarkdownSyntax`.
