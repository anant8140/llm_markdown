@Tags(['golden'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';

// Text is drawn with the test font (boxes), so the pictures are the same on
// every machine except for edge smoothing; allow a little of that.
class _Tolerant extends LocalFileComparator {
  _Tolerant(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= 0.005) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}

const _reply = '''
# Getting started

Install it, then **wrap** your reply in `StreamingMarkdown`.

1. Add the package
2. Stream the reply
   - with a controller
   - or a `Stream<String>`

> [!TIP]
> Keep one controller per message.

| Option | Default |
| --- | --- |
| smoothing | adaptive |
| cursor | block |

```dart
final controller = StreamingMarkdownController();
controller.append('Hello');
```

- [x] tests
- [ ] docs
''';

Widget _scene({
  required String text,
  bool dark = false,
  TextDirection direction = TextDirection.ltr,
  bool complete = true,
}) {
  final background = dark ? const Color(0xFF1E1F22) : const Color(0xFFFFFFFF);
  final color = dark ? const Color(0xFFE6E6E6) : const Color(0xFF202124);
  return WidgetsApp(
    color: const Color(0xFF2196F3),
    debugShowCheckedModeBanner: false,
    builder: (context, _) => Directionality(
      textDirection: direction,
      child: ColoredBox(
        color: background,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DefaultTextStyle(
            style: TextStyle(fontSize: 14, color: color),
            child: StreamingMarkdown.text(
              text,
              isComplete: complete,
              smoothing: const Smoothing.none(),
              detectTextDirection: false,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    final local = goldenFileComparator as LocalFileComparator;
    goldenFileComparator = _Tolerant(local.basedir.resolve('golden_test.dart'));
  });

  Future<void> shoot(WidgetTester tester, Widget scene, String name) async {
    tester.view
      ..physicalSize = const Size(420, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(scene);
    await tester.pump();
    await expectLater(
      find.byType(WidgetsApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('a full reply, light', (tester) async {
    await shoot(tester, _scene(text: _reply), 'reply_light');
  });

  testWidgets('a full reply, dark', (tester) async {
    await shoot(tester, _scene(text: _reply, dark: true), 'reply_dark');
  });

  testWidgets('right to left', (tester) async {
    await shoot(
      tester,
      _scene(text: _reply, direction: TextDirection.rtl),
      'reply_rtl',
    );
  });

  testWidgets('half way through a stream', (tester) async {
    await shoot(
      tester,
      _scene(text: _reply.substring(0, 260), complete: false),
      'reply_streaming',
    );
  });
}
