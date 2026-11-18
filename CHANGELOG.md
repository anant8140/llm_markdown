## 0.1.0

- `StreamingMarkdown` widget for Markdown that arrives in pieces, with a
  controller, stream and text constructor.
- Incremental parsing: finished blocks are parsed and built once.
- `healIncompleteMarkdown` closes unfinished code blocks, emphasis, code
  spans and links, and hides half-typed tables and block markers.
- Adaptive smoothing that never splits a letter or emoji.
- Code blocks with language label, copy button and syntax highlighting.
- Tables, task lists, quotes, links, images and a streaming cursor.
- Auto-scroll that follows the reply while the user is at the bottom.
- Uses only `package:flutter/widgets.dart`: works with `material_ui`, the
  Flutter Material library, Cupertino or no design library.
- Style follows the app's `DefaultTextStyle` and cursor color, or set it with
  `StreamingMarkdownStyle.fromColors`.
