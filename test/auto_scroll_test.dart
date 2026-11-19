import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';

// iOS and macOS scroll like this: content that gets shorter under the
// viewport springs back instead of snapping.
Widget _chat(ScrollController scroll, Widget reply) => WidgetsApp(
  color: const Color(0xFF2196F3),
  builder: (context, _) => DefaultTextStyle(
    style: const TextStyle(fontSize: 14, color: Color(0xFF202124)),
    child: SingleChildScrollView(
      controller: scroll,
      physics: const BouncingScrollPhysics(),
      child: reply,
    ),
  ),
);

String _filler(int n) => List.filled(n, 'Filler paragraph.\n\n').join();

void main() {
  testWidgets('the demo reply is followed to its end', (tester) async {
    // This reply lost the end on an iPhone: it grows in one frame and
    // shrinks in the next more than once (a half-typed "![" is hidden, a
    // formula's source becomes the drawn formula), and Flutter then springs
    // the list back, which looked like the user scrolling.
    tester.view
      ..physicalSize = const Size(402, 874)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scroll = ScrollController();
    final controller = StreamingMarkdownController();
    addTearDown(scroll.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF2196F3),
        builder: (context, _) => DefaultTextStyle(
          style: const TextStyle(fontSize: 14, color: Color(0xFF202124)),
          child: ListView(
            controller: scroll,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              StreamingMarkdown(
                controller: controller,
                autoScrollController: scroll,
                allowedImageSchemes: const {'https', 'data'},
                mathBuilder: (context, tex, display) =>
                    SizedBox(width: 60, height: display ? 40 : 12),
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
    final random = Random(1);
    var sent = 0;
    while (sent < _demoReply.length) {
      final end = min(_demoReply.length, sent + 2 + random.nextInt(14));
      controller.append(_demoReply.substring(sent, end));
      sent = end;
      for (var frame = 0; frame < 3; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }
    controller.complete();
    for (var frame = 0; frame < 120; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(scroll.position.maxScrollExtent, greaterThan(500));
    expect(
      scroll.offset,
      moreOrLessEquals(scroll.position.maxScrollExtent, epsilon: 1),
    );
  });

  testWidgets('keeps following when a picture loads late', (tester) async {
    final scroll = ScrollController();
    final controller = StreamingMarkdownController(text: _filler(60));
    final loaded = ValueNotifier(false);
    addTearDown(scroll.dispose);
    addTearDown(controller.dispose);
    addTearDown(loaded.dispose);
    await tester.pumpWidget(
      _chat(
        scroll,
        StreamingMarkdown(
          controller: controller,
          smoothing: const Smoothing.none(),
          autoScrollController: scroll,
          imageBuilder: (context, uri, alt) => ValueListenableBuilder<bool>(
            valueListenable: loaded,
            builder: (context, done, _) =>
                SizedBox(width: 100, height: done ? 300 : 0),
          ),
        ),
      ),
    );
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();

    controller.append('![Chart](https://example.com/chart.png)\n\nAfter.');
    await tester.pump();
    await tester.pump();
    expect(scroll.offset, scroll.position.maxScrollExtent);

    // no new text, but the reply is 300 taller now
    loaded.value = true;
    await tester.pump();
    await tester.pump();
    expect(scroll.offset, scroll.position.maxScrollExtent);

    // and scrolling up still stops the following
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 300));
    // not pumpAndSettle: the cursor blinks for as long as the reply streams
    for (var frame = 0; frame < 40; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final away = scroll.offset;
    controller.append(' More.\n\nAnd more.\n\n');
    await tester.pump();
    await tester.pump();
    expect(scroll.offset, away);
  });
}

const String _demoReply = r'''
<think>
They want to show streaming replies. The main problems are re-parsing the
whole text on every chunk and half-typed syntax. I'll show the package and
a short example.
</think>

## Streaming Markdown in Flutter

Use **llm_markdown**. It parses only the *new* text, so long replies stay
smooth, and it ==tidies unfinished syntax== such as `**bold` while it
streams [1][2].

> [!TIP]
> Keep one controller per message, so a reply survives scrolling.

### Steps

1. Add the package: `flutter pub add llm_markdown`
2. Create a `StreamingMarkdownController`
3. Append each chunk from your model

```dart
final controller = StreamingMarkdownController();

await for (final chunk in model.generate(prompt)) {
  controller.append(chunk);
}
controller.complete();
```

### How a chunk travels

```mermaid
flowchart TD
  A[New chunk] --> B{Block finished?}
  B -->|yes| C(Parse once, keep)
  B -->|no| D([Heal and parse again])
  C --> E((Show))
  D --> E
```

### A bit of math

Reveal speed grows with the backlog: $v = \max(v_0, \frac{n}{t})$.

$$
\int_0^1 x^2 \, dx = \frac{1}{3}
$$

### Why it feels fast

| Approach | Work per chunk | Flicker |
| :--- | :---: | :---: |
| Re-render everything | whole reply | yes |
| **llm_markdown** | last block only | no |

- [x] Code blocks with a copy button
- [x] Diagrams, tables and task lists
- [ ] Your next feature

![A drawn SVG picture](data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyMjAiIGhlaWdodD0iNTYiIHZpZXdCb3g9IjAgMCAyMjAgNTYiPjxyZWN0IHdpZHRoPSIyMjAiIGhlaWdodD0iNTYiIHJ4PSIxMiIgZmlsbD0iIzNGNTFCNSIvPjxjaXJjbGUgY3g9IjMwIiBjeT0iMjgiIHI9IjEyIiBmaWxsPSIjRkZDMTA3Ii8+PHJlY3QgeD0iNTQiIHk9IjE4IiB3aWR0aD0iMTQwIiBoZWlnaHQ9IjgiIHJ4PSI0IiBmaWxsPSIjZmZmIi8+PHJlY3QgeD0iNTQiIHk9IjMyIiB3aWR0aD0iOTYiIGhlaWdodD0iOCIgcng9IjQiIGZpbGw9IiNDNUNBRTkiLz48L3N2Zz4=)

Read more in the [Flutter docs](https://docs.flutter.dev). ગુજરાતી અને emoji 🚀 પણ ચાલે છે.
''';
