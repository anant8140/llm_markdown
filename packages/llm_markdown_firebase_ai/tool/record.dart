// Records the pictures in doc/: a Gemini reply from firebase_ai, replayed
// from recorded responses, with real fonts in a widget test. Makes
// doc/frames/*.png; tool/gif.py turns them into doc/firebase_ai.gif.
//
//   flutter test tool/record.dart && python3 tool/gif.py
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_ai/firebase_ai.dart';
// ignore: implementation_imports
import 'package:firebase_ai/src/api.dart' show GroundingMetadata;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown_firebase_ai/llm_markdown_firebase_ai.dart';

GenerateContentResponse _reply(
  List<Part> parts, {
  List<GroundingChunk>? sources,
}) => GenerateContentResponse([
  Candidate(
    Content('model', parts),
    null,
    null,
    null,
    null,
    groundingMetadata: sources == null
        ? null
        : GroundingMetadata(
            groundingChunks: sources,
            groundingSupports: const [],
            webSearchQueries: const [],
          ),
  ),
], null);

GroundingChunk _page(String uri, String title) => GroundingChunk(
  web: WebGroundingChunk(uri: uri, title: title),
);

const _answer =
    '**Mount Everest** is **8,849 m** (29,032 ft) tall, as measured by '
    'China and Nepal together in 2020.\n\n'
    '| Survey | Height |\n| --- | --- |\n| 1955, India | 8,848 m |\n'
    '| 2020, China and Nepal | 8,849 m |\n\n'
    'The summit is on the border of Nepal and Tibet, in the Mahalangur '
    'range of the Himalayas.';

Stream<GenerateContentResponse> _recorded() async* {
  await Future<void>.delayed(const Duration(milliseconds: 500));
  for (final thought in [
    'The user asks for the height of Mount Everest. ',
    'I will search for the latest official survey.',
  ]) {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    yield _reply([TextPart(thought, isThought: true)]);
  }
  yield _reply([
    const FunctionCall('google_search', {'query': 'Mount Everest height'}),
  ]);
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  for (var i = 0; i < _answer.length; i += 7) {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    yield _reply(
      [
        TextPart(
          _answer.substring(i, i + 7 > _answer.length ? _answer.length : i + 7),
        ),
      ],
      sources: i == 0
          ? [
              _page('https://en.wikipedia.org/wiki/Mount_Everest', 'Wikipedia'),
              _page(
                'https://www.britannica.com/place/Mount-Everest',
                'Britannica',
              ),
            ]
          : null,
    );
  }
}

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
  final mono = FontLoader('packages/llm_markdown/JetBrainsMono')
    ..addFont(
      File(
        '../../fonts/JetBrainsMono-Regular.ttf',
      ).readAsBytes().then(ByteData.sublistView),
    );
  await mono.load();
  // phones and browsers fall back to a system font for symbols such as the
  // check mark of a finished tool call; a test has none
  final symbols = FontLoader('Symbols')
    ..addFont(
      File(
        '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
      ).readAsBytes().then(ByteData.sublistView),
    );
  await symbols.load();
}

void main() {
  testWidgets('record', (tester) async {
    await tester.runAsync(_loadFonts);
    tester.view
      ..physicalSize = const Size(390 * 2, 470 * 2)
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

    final controller = StreamingMarkdownController();
    addTearDown(controller.dispose);
    const ink = Color(0xFF1C1B1F);
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF1A73E8),
        debugShowCheckedModeBanner: false,
        builder: (context, _) => RepaintBoundary(
          key: key,
          child: DefaultTextStyle(
            style: const TextStyle(
              fontFamily: 'Roboto',
              fontFamilyFallback: ['Symbols'],
              fontSize: 15,
              height: 1.4,
              color: ink,
            ),
            child: DefaultSelectionStyle(
              cursorColor: const Color(0xFF1A73E8),
              child: ColoredBox(
                color: const Color(0xFFFFFFFF),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'How tall is Mount Everest?',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      StreamingMarkdown(controller: controller),
                      const SizedBox(height: 12),
                      // the app shows controller.sources its own way
                      ListenableBuilder(
                        listenable: controller,
                        builder: (context, _) => Wrap(
                          spacing: 8,
                          children: [
                            for (final (i, source)
                                in controller.sources.indexed)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F3F4),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${i + 1}  ${source.title}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    unawaited(controller.addFirebaseAIStream(_recorded()));
    await hold(30);
    await shot('searching');
    while (!controller.isComplete) {
      await hold(1);
    }
    await hold(8);
    await shot('firebase_ai');
    await hold(25);
  });
}
