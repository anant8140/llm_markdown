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

  // what is streamed: the sample reply, or Markdown the visitor typed
  String _text = _answer;
  String _question = 'How do I show streaming Markdown in Flutter?';

  // milliseconds between chunks, about
  int _delay = 40;

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

  /// Plays [_text] back in uneven chunks, the way a model streams tokens.
  Future<void> _ask() async {
    final run = ++_run;
    _reply.reset();
    final text = _text;
    final random = Random();
    if (text == _answer) {
      // the sample reply looks something up first and cites two pages
      _reply
        ..addSource(
          const MarkdownSource(
            url: 'https://pub.dev/packages/llm_markdown',
            title: 'llm_markdown on pub.dev',
          ),
        )
        ..addSource(
          const MarkdownSource(
            url: 'https://github.com/anant8140/llm_markdown',
            title: 'llm_markdown on GitHub',
          ),
        )
        ..startToolCall('search', 'web_search');
      await Future<void>.delayed(Duration(milliseconds: _delay * 20));
      if (!mounted || run != _run) return;
      _reply.finishToolCall('search');
    }
    var i = 0;
    while (i < text.length) {
      if (_delay > 0) {
        await Future<void>.delayed(
          Duration(milliseconds: _delay ~/ 2 + random.nextInt(_delay + 1)),
        );
      }
      if (!mounted || run != _run) return;
      final end = min(text.length, i + 2 + random.nextInt(14));
      _reply.append(text.substring(i, end));
      i = end;
    }
    _reply.complete();
  }

  // Lets the visitor paste their own Markdown and watch it stream.
  Future<void> _tryYourOwn() async {
    final text = await showDialog<String>(
      context: context,
      builder: (context) =>
          _PasteDialog(initial: _text == _answer ? _sample : _text),
    );
    if (text == null || !mounted) return;
    setState(() {
      _text = text;
      _question = text == _answer
          ? 'How do I show streaming Markdown in Flutter?'
          : 'Your Markdown';
    });
    unawaited(_ask());
  }

  void _say(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('llm_markdown'),
        actions: [
          IconButton(
            tooltip: 'Stream your own Markdown',
            icon: const Icon(Icons.edit_note),
            onPressed: _tryYourOwn,
          ),
          PopupMenuButton<int>(
            tooltip: 'Streaming speed',
            icon: const Icon(Icons.speed),
            initialValue: _delay,
            onSelected: (delay) {
              setState(() => _delay = delay);
              unawaited(_ask());
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 120, child: Text('Slow')),
              PopupMenuItem(value: 40, child: Text('Normal')),
              PopupMenuItem(value: 10, child: Text('Fast')),
              PopupMenuItem(value: 0, child: Text('All at once')),
            ],
          ),
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
      // Makes the whole chat selectable, with an extra button in the menu.
      body: MarkdownSelectionArea(
        actions: [
          MarkdownSelectionAction(
            label: 'Ask about this',
            onSelected: (text) => _say('Ask about "$text"'),
          ),
        ],
        child: Stack(
          children: [
            ListView(
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
                    child: Text(_question),
                  ),
                ),
                const SizedBox(height: 16),
                StreamingMarkdown(
                  controller: _reply,
                  smoothing: _smooth
                      ? const Smoothing.adaptive()
                      : const Smoothing.none(),
                  autoScrollController: _scroll,
                  codeBlocks: const CodeBlockOptions(
                    lineNumbers: true,
                    highlightWhileStreaming: true,
                  ),
                  // the little picture in the reply is an inline SVG
                  allowedImageSchemes: const {'https', 'data'},
                  mathBuilder: (context, tex, display) => Math.tex(
                    tex,
                    mathStyle: display ? MathStyle.display : MathStyle.text,
                    onErrorFallback: (error) => Text(tex),
                  ),
                  onLinkTap: (url) => _say('Open $url'),
                  onCitationTap: (number) {
                    final sources = _reply.sources;
                    final source = number >= 1 && number <= sources.length
                        ? sources[number - 1]
                        : null;
                    _say(source?.title ?? source?.url ?? 'Source $number');
                  },
                ),
                const SizedBox(height: 80),
              ],
            ),
            // shows once the user scrolls up while the reply still grows
            Positioned(
              left: 0,
              right: 0,
              bottom: 88,
              child: Center(
                child: JumpToLatest(
                  controller: _scroll,
                  content: _reply,
                  builder: (context, jump) => FilledButton.tonalIcon(
                    onPressed: jump,
                    icon: const Icon(Icons.arrow_downward),
                    label: const Text('Latest'),
                  ),
                ),
              ),
            ),
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

// The box where a visitor pastes Markdown; it owns its text controller,
// which must outlive the dialog's closing animation.
class _PasteDialog extends StatefulWidget {
  const _PasteDialog({required this.initial});

  final String initial;

  @override
  State<_PasteDialog> createState() => _PasteDialogState();
}

class _PasteDialogState extends State<_PasteDialog> {
  late final TextEditingController _field = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Stream your own Markdown'),
    content: SizedBox(
      width: 560,
      child: TextField(
        controller: _field,
        maxLines: 14,
        minLines: 8,
        autofocus: true,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          hintText: 'Paste a reply from any chatbot here',
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, _answer),
        child: const Text('Sample reply'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _field.text),
        child: const Text('Stream it'),
      ),
    ],
  );
}

// put in the box the first time, to show what can be streamed
const String _sample = r'''
# Paste anything here

A **bold** claim, some `code`, a [link](https://flutter.dev) and a table:

| Model | Speed |
| ----- | ----- |
| Small | Fast  |
| Large | Slow  |

```mermaid
classDiagram
  Reply <|-- ChatReply
  Chat "1" *-- "many" Reply
```
''';

const String _answer = r'''
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

The life of a reply, as a state diagram:

```mermaid
stateDiagram-v2
  [*] --> Streaming
  Streaming --> Done : complete()
  Streaming --> Failed : error
  Failed --> Streaming : retry
  Done --> [*]
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
