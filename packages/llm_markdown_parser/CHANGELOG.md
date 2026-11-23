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
