import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_structured_ui/llm_structured_ui.dart';

/// Pumps [child] without a Material or Cupertino app around it.
Future<void> pumpPlain(
  WidgetTester tester,
  Widget child, {
  bool disableAnimations = false,
  Brightness brightness = Brightness.light,
  TextStyle? textStyle,
}) {
  Widget tree = Align(alignment: Alignment.topLeft, child: child);
  if (textStyle != null) {
    tree = DefaultTextStyle(style: textStyle, child: tree);
  }
  return tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(
          size: const Size(800, 600),
          disableAnimations: disableAnimations,
          platformBrightness: brightness,
        ),
        child: tree,
      ),
    ),
  );
}

/// Adds [chunk] and builds one frame.
Future<void> feed(
  WidgetTester tester,
  StructuredStreamController controller,
  String chunk,
) async {
  controller.add(chunk);
  await tester.pump();
}

/// Every piece of text on screen, in tree order; cursors leave no mark.
List<String> shown(WidgetTester tester) => [
  for (final text in tester.widgetList<RichText>(find.byType(RichText)))
    text.text.toPlainText().replaceAll('￼', ''),
]..removeWhere((text) => text.isEmpty);

final cursor = find.byType(StructuredCursor);
final placeholder = find.byType(StructuredPlaceholder);

/// A value as it is after the parser has read [json] (and nothing else).
StructuredValue partial(String json) =>
    (StructuredStreamController()..add(json)).data;

/// Lets stream events arrive, then builds one frame.
Future<void> delivered(WidgetTester tester) async {
  await tester.idle();
  await tester.pump();
}
