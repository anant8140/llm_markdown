import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_structured_ui/llm_structured_ui.dart';

import 'helpers.dart';

void main() {
  group('StructuredStyle', () {
    Future<StructuredStyle> styleIn(
      WidgetTester tester, {
      Brightness brightness = Brightness.light,
      TextStyle? textStyle,
    }) async {
      late StructuredStyle style;
      await pumpPlain(
        tester,
        Builder(
          builder: (context) {
            style = StructuredStyle.of(context);
            return const SizedBox();
          },
        ),
        brightness: brightness,
        textStyle: textStyle,
      );
      return style;
    }

    testWidgets('follows the DefaultTextStyle', (tester) async {
      const text = TextStyle(fontSize: 20, color: Color(0xFF336699));
      final style = await styleIn(tester, textStyle: text);
      expect(style.textStyle, text);
      expect(style.cursorColor, const Color(0xFF336699));
      expect(style.titleStyle.fontSize, 24);
      expect(style.titleStyle.fontWeight, FontWeight.w600);
      expect(style.labelStyle.color!.a, closeTo(0.62, 0.01));
      expect(style.subtitleStyle.color!.a, closeTo(0.62, 0.01));
      expect(style.placeholderColor.a, closeTo(0.14, 0.01));
      expect(style.chipColor.a, closeTo(0.08, 0.01));
      expect(style.cardBorderColor.a, closeTo(0.16, 0.01));
      expect(style.cardColor.a, closeTo(0.03, 0.01));
      // tints of the text color
      expect(style.placeholderColor.b, closeTo(0x99 / 255, 0.01));
    });

    testWidgets('without a text color, picks one for the brightness', (
      tester,
    ) async {
      final light = await styleIn(tester);
      expect(light.textStyle.color, const Color(0xFF1F1F1F));
      final dark = await styleIn(tester, brightness: Brightness.dark);
      expect(dark.textStyle.color, const Color(0xFFECECEC));
      expect(dark.cursorColor, const Color(0xFFECECEC));
    });

    testWidgets('StructuredTheme styles the widgets below it', (tester) async {
      final themed = StructuredStyle.fromTextStyle(
        const TextStyle(fontSize: 22, color: Color(0xFFAA0000)),
      ).copyWith(cursorColor: const Color(0xFF00AA00));
      final c = StructuredStreamController()..add('{"t": "Hi');
      addTearDown(c.dispose);
      await pumpPlain(
        tester,
        StructuredTheme(
          style: themed,
          child: StructuredBuilder(
            controller: c,
            builder: (context, data) => StructuredText(data['t']),
          ),
        ),
      );
      final rich = tester.widget<RichText>(find.byType(RichText));
      expect(rich.text.style?.color, const Color(0xFFAA0000));
      expect(rich.text.style?.fontSize, 22);
      final box = tester.widget<Container>(
        find.descendant(of: cursor, matching: find.byType(Container)),
      );
      expect(box.color, const Color(0xFF00AA00));
      expect(tester.getSize(cursor).height, 22);
    });

    test('copyWith, == and hashCode', () {
      final a = StructuredStyle.fromTextStyle(
        const TextStyle(fontSize: 14, color: Color(0xFF000000)),
      );
      final b = StructuredStyle.fromTextStyle(
        const TextStyle(fontSize: 14, color: Color(0xFF000000)),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.copyWith(), a);
      final changed = a.copyWith(spacing: 20, indent: 3, cardRadius: 1);
      expect(changed, isNot(a));
      expect(changed.spacing, 20);
      expect(changed.indent, 3);
      expect(changed.cardRadius, 1);
      expect(changed.textStyle, a.textStyle);
      expect(a.copyWith(pendingOpacity: 0.1), isNot(a));
      expect(
        a.copyWith(cardPadding: EdgeInsets.zero).cardPadding,
        EdgeInsets.zero,
      );
    });

    testWidgets('the theme notifies only when the style changes', (
      tester,
    ) async {
      final style = StructuredStyle.fromTextStyle(
        const TextStyle(fontSize: 14, color: Color(0xFF000000)),
      );
      const child = SizedBox();
      final theme = StructuredTheme(style: style, child: child);
      expect(
        theme.updateShouldNotify(
          StructuredTheme(style: style.copyWith(), child: child),
        ),
        isFalse,
      );
      expect(
        theme.updateShouldNotify(
          StructuredTheme(style: style.copyWith(spacing: 1), child: child),
        ),
        isTrue,
      );
    });
  });
}
