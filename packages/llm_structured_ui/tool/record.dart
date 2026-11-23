// Makes the pictures in doc/: a recipe object half written and finished,
// at a phone's width, with real fonts, in a widget test.
//
//   flutter test tool/record.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_structured_ui/llm_structured_ui.dart';

const _json =
    '{"title": "Tomato soup", "servings": 4, "minutes": 25, '
    '"summary": "A **quick** soup from pantry staples, ready in under half an hour.", '
    '"steps": [{"text": "Chop the onion and garlic."}, '
    '{"text": "Add the tomatoes and stock, simmer 15 minutes."}, '
    '{"text": "Blend until smooth and season."}]}';

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
}

void main() {
  testWidgets('record', (tester) async {
    await tester.runAsync(_loadFonts);
    tester.view
      ..physicalSize = const Size(390 * 2, 330 * 2)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    final controller = StructuredStreamController();
    addTearDown(controller.dispose);

    Future<void> shot(String name) async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });
      File('doc/$name.png').writeAsBytesSync(bytes!);
    }

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
            child: ColoredBox(
              color: const Color(0xFFFFFFFF),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: StructuredBuilder(
                  controller: controller,
                  builder: (context, recipe) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StructuredText(
                        recipe['title'],
                        textStyle: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      StructuredFields(
                        recipe,
                        order: const ['servings', 'minutes'],
                        labels: const {
                          'servings': 'Serves',
                          'minutes': 'Time (min)',
                        },
                        hide: const {'title', 'summary', 'steps'},
                      ),
                      const SizedBox(height: 12),
                      StructuredText(recipe['summary'], markdown: true),
                      const SizedBox(height: 12),
                      StructuredList(
                        recipe['steps'],
                        itemBuilder: (context, step, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${index + 1}.  '),
                              Expanded(child: StructuredText(step['text'])),
                            ],
                          ),
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
    // cut off inside the second step
    final cut = _json.indexOf('simmer');
    controller.add(_json.substring(0, cut));
    await tester.pump(const Duration(milliseconds: 100));
    await shot('streaming');
    controller
      ..add(_json.substring(cut))
      ..close();
    await tester.pump(const Duration(seconds: 1));
    await shot('done');
  });
}
