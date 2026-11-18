## Unreleased

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

## 0.2.0

* LaTeX math (`$...$`, `\(...\)`, `$$...$$`, `\[...\]`) with a `mathBuilder`
  to draw it. Formulas still streaming show their source.
* Thinking section for `<think>...</think>` replies and
  `StreamingMarkdownController.appendThinking`.
* Newest characters fade in (`Smoothing.adaptive(fadeLength: ...)`).

## 0.1.0

* Initial release.
