import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown/src/code_block.dart';
import 'package:llm_markdown/src/direction.dart';

Widget _host(
  Widget child, {
  TextDirection direction = TextDirection.ltr,
  double textScale = 1,
}) => WidgetsApp(
  color: const Color(0xFF2196F3),
  builder: (context, _) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: Directionality(
      textDirection: direction,
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 14, color: Color(0xFF202124)),
        child: SingleChildScrollView(child: child),
      ),
    ),
  ),
);

/// The direction the paragraph containing [text] is laid out in.
TextDirection _directionOf(WidgetTester tester, Finder finder) {
  final rich = tester.widget<RichText>(finder);
  return rich.textDirection ?? Directionality.of(tester.element(finder));
}

Finder _richTextWith(String text) => find.byWidgetPredicate(
  (w) => w is RichText && w.text.toPlainText().contains(text),
);

void main() {
  group('screen readers', () {
    testWidgets('text still arriving is hidden until the reply is done', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final controller = StreamingMarkdownController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          StreamingMarkdown(
            controller: controller,
            smoothing: const Smoothing.none(),
            showCursor: false,
          ),
        ),
      );
      controller.append('First paragraph is done.\n\nSecond one is half');
      await tester.pump();
      expect(find.bySemanticsLabel(RegExp('First paragraph')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Second one')), findsNothing);

      controller
        ..append(' written.')
        ..complete();
      await tester.pump();
      expect(find.bySemanticsLabel(RegExp('Second one')), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('the finished reply is announced once', (tester) async {
      final controller = StreamingMarkdownController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          StreamingMarkdown(
            controller: controller,
            smoothing: const Smoothing.none(),
          ),
        ),
      );
      controller.append('# Answer\n\nIt is **42**.');
      await tester.pump();
      expect(tester.takeAnnouncements(), isEmpty);

      controller.complete();
      await tester.pump();
      await tester.pump();
      final announced = tester.takeAnnouncements();
      expect(announced, hasLength(1));
      expect(announced.single.message, 'Answer\nIt is 42.');

      await tester.pump();
      expect(tester.takeAnnouncements(), isEmpty);
    });

    testWidgets('no announcement for history or when turned off', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const StreamingMarkdown.text('Old reply')));
      await tester.pump();
      expect(tester.takeAnnouncements(), isEmpty);

      final controller = StreamingMarkdownController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          StreamingMarkdown(
            controller: controller,
            smoothing: const Smoothing.none(),
            announceWhenDone: false,
          ),
        ),
      );
      controller
        ..append('New reply')
        ..complete();
      await tester.pump();
      await tester.pump();
      expect(tester.takeAnnouncements(), isEmpty);
    });

    testWidgets('math is read as its TeX source', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          StreamingMarkdown.text(
            '\$\$\nE = mc^2\n\$\$\n',
            mathBuilder: (context, tex, display) => const SizedBox(),
          ),
        ),
      );
      expect(find.bySemanticsLabel('E = mc^2'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('large text does not overflow on a narrow screen', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(320, 1200)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          const StreamingMarkdown.text(
            '# A long heading that has to wrap\n\n'
            '- [x] a task item with enough words to wrap twice\n\n'
            '```dart\nfinal value = someFunction(withAnArgument, another);\n```\n'
            '| a | b | c |\n| - | - | - |\n| one | two | three |\n',
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('text direction', () {
    test('the first letter decides', () {
      expect(detectTextDirection('مرحبا بالعالم'), TextDirection.rtl);
      expect(detectTextDirection('שלום'), TextDirection.rtl);
      expect(detectTextDirection('123, hello'), TextDirection.ltr);
      expect(detectTextDirection('**مرحبا** and more'), TextDirection.rtl);
      expect(detectTextDirection('નમસ્તે'), TextDirection.ltr);
      expect(detectTextDirection('123 !?'), isNull);
    });

    testWidgets('an Arabic paragraph reads right to left in an LTR app', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const StreamingMarkdown.text('مرحبا، هذا رد.\n\nHello there.')),
      );
      expect(_directionOf(tester, _richTextWith('مرحبا')), TextDirection.rtl);
      expect(_directionOf(tester, _richTextWith('Hello')), TextDirection.ltr);
    });

    testWidgets('list markers sit on the right for a Hebrew list', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const StreamingMarkdown.text('- פריט ראשון\n- פריט שני\n')),
      );
      final marker = tester.getCenter(find.text('•').first);
      final item = tester.getCenter(find.textContaining('ראשון'));
      expect(marker.dx, greaterThan(item.dx));
    });

    testWidgets('a quote line sits on the right for a Hebrew quote', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const StreamingMarkdown.text('> ציטוט קצר\n')),
      );
      final quote = tester.widget<DecoratedBox>(
        find
            .ancestor(
              of: find.textContaining('ציטוט'),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      // In a right-to-left block the start side is the right side.
      final border = (quote.decoration as BoxDecoration).border!;
      final (right, left) = switch (border) {
        BorderDirectional(:final start, :final end) => (start, end),
        Border(:final right, :final left) => (right, left),
        _ => throw StateError('unexpected border $border'),
      };
      expect(right.width, greaterThan(0));
      expect(left.width, 0);
      expect(
        Directionality.of(tester.element(find.textContaining('ציטוט'))),
        TextDirection.rtl,
      );
    });

    testWidgets('code stays left to right in an RTL app', (tester) async {
      await tester.pumpWidget(
        _host(
          const StreamingMarkdown.text('```dart\nprint(1);\n```\n'),
          direction: TextDirection.rtl,
        ),
      );
      final code = find.descendant(
        of: find.byType(CodeBlockView),
        matching: find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('print'),
        ),
      );
      expect(_directionOf(tester, code), TextDirection.ltr);
    });

    testWidgets('detectTextDirection: false keeps the app direction', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const StreamingMarkdown.text(
            'مرحبا، هذا رد.',
            detectTextDirection: false,
          ),
        ),
      );
      expect(_directionOf(tester, _richTextWith('مرحبا')), TextDirection.ltr);
    });
  });
}
