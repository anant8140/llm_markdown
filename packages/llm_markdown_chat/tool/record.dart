// Records the pictures in doc/: frames of a chat at a phone's size, taken
// with real fonts in a widget test. Makes doc/frames/*.png; tool/gif.py
// turns them into doc/chat.gif.
//
//   flutter test tool/record.dart && python3 tool/gif.py
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown_chat/llm_markdown_chat.dart';

const _answer =
    '## Streams in Dart\n\n'
    'A `Stream` gives you values **over time**, like the chunks of a '
    'reply from a model.\n\n'
    '- `listen` gets each value as it comes\n'
    '- `await for` reads them in a loop\n'
    '- cancelling closes the request\n\n'
    '```dart\nawait for (final chunk in reply) {\n  print(chunk);\n}\n```\n\n'
    '| Kind | Values |\n| --- | --- |\n| Future | one |\n| Stream | many |\n';

Future<void> _loadFonts() async {
  final root =
      Platform.environment['FLUTTER_ROOT'] ??
      '${Platform.environment['HOME']}/fvm/versions/3.50.0';
  final dir = '$root/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final name in ['Regular', 'Medium', 'Bold', 'Italic']) {
    roboto.addFont(
      File('$dir/Roboto-$name.ttf').readAsBytes().then(ByteData.sublistView),
    );
  }
  await roboto.load();
  // the code font of llm_markdown, two folders up
  final mono = FontLoader('packages/llm_markdown/JetBrainsMono')
    ..addFont(
      File(
        '../../fonts/JetBrainsMono-Regular.ttf',
      ).readAsBytes().then(ByteData.sublistView),
    );
  await mono.load();
}

void main() {
  testWidgets('record', (tester) async {
    await tester.runAsync(_loadFonts);
    tester.view
      ..physicalSize = const Size(390 * 2, 720 * 2)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final frames = Directory('doc/frames');
    if (frames.existsSync()) frames.deleteSync(recursive: true);
    frames.createSync(recursive: true);
    var count = 0;
    final key = GlobalKey();

    Future<void> shot([String? name]) async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });
      File(
        '${frames.path}/${(count++).toString().padLeft(4, '0')}.png',
      ).writeAsBytesSync(bytes!);
      if (name != null) File('doc/$name.png').writeAsBytesSync(bytes);
    }

    Future<void> hold(int frames) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await shot();
      }
    }

    final chat = LlmChatController(
      onReply: (prompt, reply, history) => reply.addStream(() async* {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        for (var i = 0; i < _answer.length; i += 6) {
          await Future<void>.delayed(const Duration(milliseconds: 60));
          yield _answer.substring(
            i,
            i + 6 > _answer.length ? _answer.length : i + 6,
          );
        }
      }()),
    );
    addTearDown(chat.dispose);

    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF6750A4),
        debugShowCheckedModeBanner: false,
        builder: (context, _) => RepaintBoundary(
          key: key,
          child: DefaultTextStyle(
            style: const TextStyle(
              fontFamily: 'Roboto',
              fontSize: 15,
              height: 1.4,
              color: Color(0xFF1C1B1F),
            ),
            child: DefaultSelectionStyle(
              cursorColor: const Color(0xFF6750A4),
              child: ColoredBox(
                color: const Color(0xFFFFFFFF),
                child: LlmChatView(
                  controller: chat,
                  emptyBuilder: (context) => const Text(
                    'How can I help?',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                  ),
                  suggestions: const [
                    'Explain streams in Dart',
                    'Write a haiku',
                    'Plan a trip',
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await shot('empty');
    await hold(12);

    // type the prompt, letter by letter
    const prompt = 'Explain streams in Dart';
    for (var i = 1; i <= prompt.length; i++) {
      await tester.enterText(find.byType(EditableText), prompt.substring(0, i));
      await tester.pump(const Duration(milliseconds: 50));
      if (i.isEven) await shot();
    }
    await hold(4);
    await tester.tap(find.bySemanticsLabel('Send'));
    await hold(40);
    await shot('streaming');
    while (chat.isReplying) {
      await hold(1);
    }
    await hold(6);
    await shot('chat');
    await hold(25);
    expect(count, greaterThan(50));
  });
}
