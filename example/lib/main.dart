import 'dart:async';
import 'dart:math';

import 'package:flutter_math_fork/flutter_math.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:material_ui/material_ui.dart';

void main() => runApp(const DemoApp());

/// A chat screen that streams a fake AI reply into [StreamingMarkdown].
class DemoApp extends StatefulWidget {
  /// Creates the demo app.
  const DemoApp({super.key});

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  ThemeMode _mode = ThemeMode.light;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'llm_markdown demo',
    debugShowCheckedModeBanner: false,
    themeMode: _mode,
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      brightness: Brightness.dark,
    ),
    home: ChatScreen(
      dark: _mode == ThemeMode.dark,
      onToggleTheme: () => setState(() {
        _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
      }),
    ),
  );
}

/// The chat screen of the demo.
class ChatScreen extends StatefulWidget {
  /// Creates the chat screen.
  const ChatScreen({
    super.key,
    required this.dark,
    required this.onToggleTheme,
  });

  /// Whether the dark theme is on.
  final bool dark;

  /// Switches between the light and dark theme.
  final VoidCallback onToggleTheme;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final StreamingMarkdownController _reply = StreamingMarkdownController();
  final ScrollController _scroll = ScrollController();
  bool _smooth = true;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    _ask();
  }

  @override
  void dispose() {
    _reply.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Plays [_answer] back in uneven chunks, the way a model streams tokens.
  Future<void> _ask() async {
    final run = ++_run;
    _reply.reset();
    final random = Random();
    var i = 0;
    while (i < _answer.length) {
      await Future<void>.delayed(
        Duration(milliseconds: 20 + random.nextInt(60)),
      );
      if (!mounted || run != _run) return;
      final end = min(_answer.length, i + 2 + random.nextInt(14));
      _reply.append(_answer.substring(i, end));
      i = end;
    }
    _reply.complete();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('llm_markdown'),
        actions: [
          IconButton(
            tooltip: _smooth ? 'Turn smoothing off' : 'Turn smoothing on',
            icon: Icon(_smooth ? Icons.waves : Icons.bolt),
            onPressed: () => setState(() => _smooth = !_smooth),
          ),
          IconButton(
            tooltip: 'Switch theme',
            icon: Icon(widget.dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: widget.onToggleTheme,
          ),
        ],
      ),
      // Lets the user select and copy text across the whole chat.
      body: SelectionArea(
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.all(16),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'How do I show streaming Markdown in Flutter?',
                ),
              ),
            ),
            const SizedBox(height: 16),
            StreamingMarkdown(
              controller: _reply,
              smoothing: _smooth
                  ? const Smoothing.adaptive()
                  : const Smoothing.none(),
              autoScrollController: _scroll,
              mathBuilder: (context, tex, display) => Math.tex(
                tex,
                mathStyle: display ? MathStyle.display : MathStyle.text,
                onErrorFallback: (error) => Text(tex),
              ),
              onLinkTap: (url) =>
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Open $url'))),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _ask,
        icon: const Icon(Icons.replay),
        label: const Text('Ask again'),
      ),
    );
  }
}

const String _answer = r'''
<think>
They want to show streaming replies. The main problems are re-parsing the
whole text on every chunk and half-typed syntax. I'll show the package and
a short example.
</think>

## Streaming Markdown in Flutter

Use **llm_markdown**. It parses only the *new* text, so long replies stay
smooth, and it tidies unfinished syntax such as `**bold` while it streams.

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

> Finished blocks are built **once** and never parsed again.

- [x] Code blocks with a copy button
- [x] Tables, quotes and task lists
- [ ] Your next feature

Read more in the [Flutter docs](https://docs.flutter.dev). ગુજરાતી અને emoji 🚀 પણ ચાલે છે.
''';
