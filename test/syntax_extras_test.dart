import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown_parser/llm_markdown_parser.dart';
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

List<String> _tags(
  String source, [
  MarkdownSyntax syntax = const MarkdownSyntax(),
]) {
  final tags = <String>[];
  void walk(List<md.Node> nodes) {
    for (final node in nodes) {
      if (node is md.Element) {
        tags.add(node.tag);
        walk(node.children ?? const []);
      }
    }
  }

  walk(newMarkdownDocument(syntax).parse(source));
  return tags;
}

void main() {
  test('TeX becomes readable Unicode', () {
    const cases = {
      r'x^2 + y^2': 'x² + y²',
      r'a_1 + a_{10}': 'a₁ + a₁₀',
      r'\frac{1}{2}': '1/2',
      r'\sqrt{x}': '√(x)',
      r'\alpha \le \beta': 'α ≤ β',
      r'\sum_{i=1}^{n} i': '∑ᵢ₌₁ⁿ i',
      r'e^{i\pi}': 'e^(iπ)',
      r'\text{speed} = 3 \times 10^8': 'speed = 3 × 10⁸',
    };
    for (final entry in cases.entries) {
      expect(texToUnicode(entry.key), entry.value, reason: entry.key);
    }
  });

  testWidgets('footnotes show at the end and the ref scrolls there', (
    tester,
  ) async {
    String? tapped;
    await tester.pumpWidget(
      _host(
        StreamingMarkdown.text(
          'A claim[^1] in the text.\n\n${'Filler paragraph.\n\n' * 30}'
          '[^1]: The source of the claim.\n',
          onLinkTap: (url) => tapped = url,
        ),
      ),
    );
    expect(_shown(tester), contains('The source of the claim.'));
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.pixels, 0);

    await tester.tapOnText(find.textRange.ofSubstring('1').first);
    await tester.pumpAndSettle();
    expect(tapped, isNull);
    expect(scrollable.position.pixels, greaterThan(0));
  });

  group('alerts', () {
    test('keep all their "> " lines', () {
      expect(
        md.renderToHtml(
          newMarkdownDocument().parse('> [!NOTE]\n> One.\n> Two.\n'),
        ),
        isNot(contains('<blockquote>')),
      );
    });

    test('parse like block quotes', () {
      expect(_tags('> [!TIP]\n> Use it.\n'), contains('div'));
      expect(
        _tags('> [!TIP]\n> Use it.\n', const MarkdownSyntax(alerts: false)),
        isNot(contains('div')),
      );
    });

    testWidgets('draw a colored box with a title', (tester) async {
      await tester.pumpWidget(
        _host(const StreamingMarkdown.text('> [!WARNING]\n> Back up first.\n')),
      );
      expect(_shown(tester), contains('Warning'));
      expect(_shown(tester), contains('Back up first.'));
      final box = tester.widget<DecoratedBox>(
        find
            .ancestor(
              of: find.textContaining('Back up'),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final border =
          (box.decoration as BoxDecoration).border! as BorderDirectional;
      expect(border.start.color, const Color(0xFF9A6700));
    });
  });

  testWidgets('<details> opens on tap', (tester) async {
    await tester.pumpWidget(
      _host(
        const StreamingMarkdown.text(
          '<details>\n<summary>Show the steps</summary>\n\n'
          '1. **first**\n2. second\n</details>\n',
        ),
      ),
    );
    expect(_shown(tester), contains('Show the steps'));
    expect(_shown(tester), isNot(contains('first')));
    await tester.tap(find.textContaining('Show the steps'));
    await tester.pumpAndSettle();
    expect(_shown(tester), contains('first'));
  });

  testWidgets('emoji, highlight, spoiler and safe HTML', (tester) async {
    await tester.pumpWidget(
      _host(
        const StreamingMarkdown.text(
          'Done :rocket: and ==important== and ||the ending||.\n\n'
          'H<sub>2</sub>O, x<sup>2</sup>, <kbd>Ctrl</kbd>, <u>under</u>'
          '<br>new line <script>bad()</script>\n',
        ),
      ),
    );
    final shown = _shown(tester);
    expect(shown, contains('🚀'));
    expect(shown, isNot(contains('==')));
    expect(shown, isNot(contains('||')));
    expect(shown, isNot(contains('<sub>')));
    expect(shown, contains('Ctrl'));
    expect(shown, contains('<script>'));

    final spoiler = tester.widget<Text>(find.text('the ending'));
    expect(spoiler.style?.color?.a, 0);
    await tester.tap(find.text('the ending'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.text('the ending')).style?.color?.a,
      isNot(0),
    );
  });

  test('healing half-typed HTML and highlight', () {
    expect(healIncompleteMarkdown('water is H<su'), 'water is H');
    expect(
      healIncompleteMarkdown('water is H<sub>2'),
      'water is H<sub>2</sub>',
    );
    expect(healIncompleteMarkdown('an ==important'), 'an ==important==');
  });

  group('citations', () {
    test('only [n] after text, not links or indexing', () {
      expect(_tags('Fact [1].'), contains('cite'));
      expect(_tags('Code a[1] here.'), isNot(contains('cite')));
      expect(_tags('See [1](https://x.y).'), isNot(contains('cite')));
      expect(_tags('See [1].\n\n[1]: https://x.y\n'), isNot(contains('cite')));
      expect(
        _tags('Fact [1].', const MarkdownSyntax(citations: false)),
        isNot(contains('cite')),
      );
    });

    testWidgets('chips report taps', (tester) async {
      int? tapped;
      await tester.pumpWidget(
        _host(
          StreamingMarkdown.text(
            'Paris is the capital [2].',
            onCitationTap: (n) => tapped = n,
          ),
        ),
      );
      await tester.tap(find.text('2'));
      expect(tapped, 2);
    });
  });

  group('syntax options', () {
    test(r'dollarMath: false keeps $ as text', () {
      const off = MarkdownSyntax(dollarMath: false);
      expect(_tags(r'costs $5 or $x$', off), isNot(contains('math')));
      expect(_tags(r'but \(x\) is math', off), contains('math'));
      expect(_tags('\$\$\nx\n\$\$\n', off), isNot(contains('math-block')));
    });

    test(r'dollarMath: false streams like a one-shot parse', () {
      const off = MarkdownSyntax(dollarMath: false);
      const text = 'Before\n\$\$\nnot math\n\$\$\n\nAfter\n';
      final parser = IncrementalMarkdownParser(syntax: off);
      for (var i = 1; i <= text.length; i++) {
        parser.update(text.substring(0, i), complete: false);
      }
      parser.update(text, complete: true);
      String html(List<md.Node> nodes) => md.renderToHtml(nodes);
      expect(
        html([for (final b in parser.frozenBlocks) ...b.nodes]),
        html(newMarkdownDocument(off).parse(text)),
      );
    });

    test('autolinks can be turned off or extended', () {
      expect(_tags('Go to https://dart.dev now'), contains('a'));
      expect(
        _tags(
          'Go to https://dart.dev now',
          const MarkdownSyntax(autolinks: false),
        ),
        isNot(contains('a')),
      );
      expect(
        _tags(
          'Open myapp://home now',
          const MarkdownSyntax(autolinkSchemes: {'myapp'}),
        ),
        contains('a'),
      );
    });
  });
}
