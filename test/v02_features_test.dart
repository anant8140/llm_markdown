import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown/src/math.dart';
import 'package:llm_markdown/src/thinking.dart';
import 'package:markdown/markdown.dart' as md;

Widget _host(Widget child) => WidgetsApp(
  color: const Color(0xFF2196F3),
  builder: (context, _) => DefaultTextStyle(
    style: const TextStyle(fontSize: 14, color: Color(0xFF202124)),
    child: SingleChildScrollView(child: child),
  ),
);

String _shown(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((text) => text.text.toPlainText())
    .join('\n');

/// Every leaf span with its effective color.
List<(String, Color?)> _leaves(InlineSpan root) {
  final out = <(String, Color?)>[];
  void walk(InlineSpan span, Color? color) {
    if (span is! TextSpan) return;
    final effective = span.style?.color ?? color;
    if (span.text != null) out.add((span.text!, effective));
    span.children?.forEach((child) => walk(child, effective));
  }

  walk(root, null);
  return out;
}

void main() {
  group('math', () {
    List<String> mathIn(String source) {
      final found = <String>[];
      void walk(List<md.Node> nodes) {
        for (final node in nodes) {
          if (node is md.Element) {
            if (node.tag == inlineMathTag || node.tag == blockMathTag) {
              found.add('${node.tag}:${node.textContent}');
            }
            walk(node.children ?? const []);
          }
        }
      }

      walk(newMarkdownDocument().parse(source));
      return found;
    }

    test('finds inline and block formulas', () {
      expect(mathIn(r'Area $\pi r^2$ and \(x\).'), [r'math:\pi r^2', 'math:x']);
      expect(mathIn('\$\$\na+b\n\$\$\n'), ['math-block:a+b']);
      expect(mathIn('\\[\nE=mc^2\n\\]\n'), ['math-block:E=mc^2']);
    });

    test('leaves prices and spaced dollars alone', () {
      expect(mathIn(r'It costs $5 and $10.'), isEmpty);
      expect(mathIn(r'Pay $ 5 now and $ 6 later'), isEmpty);
      expect(mathIn(r'Escaped \$x$ stays text'), isEmpty);
    });

    testWidgets('the builder gets closed formulas, open ones show source', (
      tester,
    ) async {
      final built = <(String, bool)>[];
      final controller = StreamingMarkdownController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          StreamingMarkdown(
            controller: controller,
            smoothing: const Smoothing.none(),
            mathBuilder: (context, tex, display) {
              built.add((tex, display));
              return Text('[$tex]');
            },
          ),
        ),
      );
      controller.append('Inline \$x^2\$ here.\n\n\$\$\n\\frac{1}{');
      await tester.pump();
      expect(built, contains(('x^2', false)));
      expect(built.where((b) => b.$2), isEmpty);
      expect(_shown(tester), contains(r'\frac{1}{'));

      controller.append('2}\n\$\$\n');
      await tester.pump();
      expect(built, contains((r'\frac{1}{2}', true)));
    });

    testWidgets('without a builder the source is shown', (tester) async {
      await tester.pumpWidget(
        _host(const StreamingMarkdown.text('Area \$\\pi r^2\$.')),
      );
      expect(_shown(tester), contains(r'$\pi r^2$'));
    });
  });

  group('thinking', () {
    test('splits <think> tags off the answer', () {
      var split = splitThinking('<think>plan', complete: false);
      expect((split.thinking, split.answer, split.done), ('plan', '', false));

      split = splitThinking('<think>plan</thi', complete: false);
      expect(split.thinking, 'plan');

      split = splitThinking('<think>plan</think>\n\nAnswer', complete: false);
      expect(
        (split.thinking, split.answer, split.done),
        ('plan', 'Answer', true),
      );

      split = splitThinking('<thi', complete: false);
      expect((split.thinking, split.answer), ('', ''));

      split = splitThinking('<thi', complete: true);
      expect((split.thinking, split.answer), (null, '<thi'));

      split = splitThinking('Just an answer', complete: false);
      expect((split.thinking, split.answer), (null, 'Just an answer'));
    });

    testWidgets('shows a closed section while thinking, then the answer', (
      tester,
    ) async {
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
      controller.append('<think>Check the docs first');
      await tester.pump();
      expect(_shown(tester), contains('Thinking'));
      expect(_shown(tester), isNot(contains('Check the docs')));

      controller
        ..append('</think>\n\nHere is the **answer**.')
        ..complete();
      await tester.pump();
      expect(_shown(tester), contains('Thought for'));
      expect(_shown(tester), contains('Here is the answer.'));
      expect(_shown(tester), isNot(contains('think>')));

      await tester.tap(find.textContaining('Thought for'));
      await tester.pumpAndSettle();
      expect(_shown(tester), contains('Check the docs first'));
    });

    testWidgets('appendThinking feeds the section too', (tester) async {
      final controller = StreamingMarkdownController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          StreamingMarkdown(
            controller: controller,
            smoothing: const Smoothing.none(),
            thinkingInitiallyExpanded: true,
            thinkingLabel: (done, duration) => done ? 'Done' : 'Working',
          ),
        ),
      );
      controller.appendThinking('Reading the question');
      await tester.pump();
      expect(_shown(tester), contains('Working'));
      expect(_shown(tester), contains('Reading the question'));

      controller.append('Answer');
      await tester.pump();
      expect(_shown(tester), contains('Done'));
    });

    testWidgets('showThinking: false leaves the thinking out', (tester) async {
      await tester.pumpWidget(
        _host(
          const StreamingMarkdown.text(
            '<think>secret plan</think>Answer',
            showThinking: false,
          ),
        ),
      );
      expect(_shown(tester), contains('Answer'));
      expect(_shown(tester), isNot(contains('Thought')));
      expect(_shown(tester), isNot(contains('secret')));
    });

    testWidgets('a reply from history says Thoughts, not a made-up time', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const StreamingMarkdown.text('<think>plan</think>Answer')),
      );
      expect(_shown(tester), contains('Thoughts'));
      expect(_shown(tester), isNot(contains('Thought for')));
    });
  });

  group('fade-in', () {
    Future<List<(String, Color?)>> streamed(
      WidgetTester tester,
      Smoothing smoothing,
    ) async {
      final controller = StreamingMarkdownController(text: 'x');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(StreamingMarkdown(controller: controller, smoothing: smoothing)),
      );
      controller.append(' The newest words fade in');
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      return _leaves(tester.widget<RichText>(find.byType(RichText)).text);
    }

    testWidgets('the newest characters are fainter', (tester) async {
      final leaves = await streamed(tester, const Smoothing.adaptive());
      final last = leaves.lastWhere((leaf) => leaf.$1.trim().isNotEmpty);
      expect(last.$1, 'n');
      expect(last.$2!.a, lessThan(0.5));
      expect(leaves.first.$2!.a, 1);
    });

    testWidgets('no fade with Smoothing.none or once complete', (tester) async {
      var leaves = await streamed(tester, const Smoothing.none());
      expect(
        leaves.every((leaf) => leaf.$2 == null || leaf.$2!.a == 1),
        isTrue,
      );

      await tester.pumpWidget(
        _host(const StreamingMarkdown.text('All done here.')),
      );
      leaves = _leaves(tester.widget<RichText>(find.byType(RichText)).text);
      expect(
        leaves.every((leaf) => leaf.$2 == null || leaf.$2!.a == 1),
        isTrue,
      );
    });
  });
}
