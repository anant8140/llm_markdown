import 'dart:convert';

import 'package:llm_markdown_parser/llm_markdown_parser.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:test/test.dart';

String _html(String text, [MarkdownSyntax syntax = const MarkdownSyntax()]) =>
    md.renderToHtml(newMarkdownDocument(syntax).parse(text));

void main() {
  group('healing', () {
    test('a half-typed closing tag still closes the open one', () {
      expect(healIncompleteMarkdown('H<sub>2</su'), 'H<sub>2</sub>');
      expect(healIncompleteMarkdown('H<sub>2<'), 'H<sub>2</sub>');
      expect(healIncompleteMarkdown('H<sub>2</sub>O'), 'H<sub>2</sub>O');
    });

    test('a half-typed alert marker is hidden, not shown as "!NO"', () {
      expect(healIncompleteMarkdown('> [!NO'), '');
      expect(healIncompleteMarkdown('Text.\n\n> [!WARNING]'), 'Text.\n\n');
      expect(healIncompleteMarkdown('> [link'), '> link');
    });

    test('half-typed footnote and reference links leave no marks', () {
      expect(healIncompleteMarkdown('A claim[^1'), 'A claim');
      expect(healIncompleteMarkdown('see [docs][ref'), 'see [docs]');
    });

    test('== between words is a comparison, not a highlight', () {
      expect(healIncompleteMarkdown('if a==b then'), 'if a==b then');
      expect(healIncompleteMarkdown('an ==important'), 'an ==important==');
    });
  });

  group('syntax', () {
    test('== and || inside code-like text stay text', () {
      expect(_html('if (a==b && c==d) x'), isNot(contains('<mark>')));
      expect(_html('a||b||c'), isNot(contains('<spoiler>')));
      expect(
        _html('an ==important== word'),
        contains('<mark>important</mark>'),
      );
      expect(_html('the ||ending|| is'), contains('<spoiler>ending</spoiler>'));
    });

    test('citations next to each other are all citations', () {
      expect(
        _html('A fact [1][2][13].'),
        '<p>A fact <cite>1</cite><cite>2</cite><cite>13</cite>.</p>',
      );
      // a reference link keeps working
      expect(
        _html('See [1][2].\n\n[2]: https://x.y\n'),
        contains('<a href="https://x.y">1</a>'),
      );
      expect(_html('[text][2] and a[1][2]'), isNot(contains('<cite>')));
    });

    test(r'"US$5 ... 5$" is not math', () {
      expect(_html(r'US$5 and 5$ or more'), isNot(contains('<math')));
      expect(_html(r'so $x$ is'), contains('<math'));
    });

    test('a custom-scheme link ends before the sentence does', () {
      const syntax = MarkdownSyntax(autolinkSchemes: {'myapp'});
      expect(
        _html('Open myapp://home/settings. Then', syntax),
        contains('<a href="myapp://home/settings">myapp://home/settings</a>.'),
      );
      expect(
        _html('(myapp://a?b=1), ok', syntax),
        contains('href="myapp://a?b=1"'),
      );
    });
  });

  group('plain text', () {
    test('citations and footnotes keep their brackets', () {
      expect(markdownToPlainText('A fact [1].'), 'A fact [1].');
      expect(
        markdownToPlainText('A claim[^1].\n\n[^1]: The source.\n'),
        'A claim[1].\n\n1. The source.',
      );
    });

    test('a rule leaves one blank line and details keep their title', () {
      expect(markdownToPlainText('a\n\n---\n\nb'), 'a\n\nb');
      expect(
        markdownToPlainText(
          '<details>\n<summary>Steps</summary>\n\nbody\n</details>\n',
        ),
        'Steps\n\nbody',
      );
    });
  });

  group('thinking', () {
    test('an empty think block is no thinking at all', () {
      for (final reply in [
        '<think>\n\n</think>\n\nAnswer',
        '<think></think>Answer',
      ]) {
        final split = splitThinking(reply, complete: true);
        expect(split.thinking, isNull, reason: reply);
        expect(split.answer, 'Answer');
        expect(split.done, isTrue);
      }
      // still open: the model may yet think
      expect(splitThinking('<think>\n', complete: false).thinking, isNotNull);
    });
  });

  group('server-sent events', () {
    test('a broken byte does not end the stream', () async {
      final events = await serverSentEvents(
        Stream.fromIterable([
          [...utf8.encode('data: a'), 0xFF, ...utf8.encode('\n\ndata: b\n\n')],
        ]),
      ).toList();
      expect(events.map((e) => e.data), ['a\uFFFD', 'b']);
    });
  });

  group('TeX as text', () {
    test('common commands read well', () {
      const cases = {
        r'\frac{1}{2}': '1/2',
        r'\frac12': '1/2',
        r'\frac{a+b}{c}': '(a+b)/c',
        r'\frac{\frac{a}{b}}{c}': '(a/b)/c',
        r'\sqrt[3]{x}': '∛(x)',
        r'\sqrt{x+1}': '√(x+1)',
        r'\left( x \right)': '( x )',
        r'\left. y \right|': 'y |',
        r'\{a, b\}': '{a, b}',
        r'50\% of \$5': r'50% of $5',
        r'a\;b\!c\ d': 'a bc d',
        r'e^{-x^2}': 'e^(-x²)',
        r'\mathbb{R}^n': 'ℝⁿ',
        // the letter, then a combining arrow, hat or bar
        r'\vec{v} + \hat{x} + \bar{y}': 'v\u20D7 + x\u0302 + y\u0304',
        r'\mathbf{A}\mathrm{d}x': 'Adx',
        r'\sin x + \log_2 n': 'sin x + log₂ n',
        r'a \\ b': 'a\nb',
        r'x^': 'x^',
        r'\frac{a}': 'a/',
        r'}{': '',
      };
      for (final entry in cases.entries) {
        expect(texToUnicode(entry.key), entry.value, reason: entry.key);
      }
    });

    test('what worked keeps working', () {
      const cases = {
        r'x^2 + y^2': 'x² + y²',
        r'a_1 + a_{10}': 'a₁ + a₁₀',
        r'\sqrt{x}': '√(x)',
        r'\alpha \le \beta': 'α ≤ β',
        r'\sum_{i=1}^{n} i': '∑ᵢ₌₁ⁿ i',
        r'e^{i\pi}': 'e^(iπ)',
        r'\text{speed} = 3 \times 10^8': 'speed = 3 × 10⁸',
        r'\int_0^\infty': '∫₀^∞',
        r'x^\alpha': 'x^α',
        r'\pi r^2': 'π r²',
      };
      for (final entry in cases.entries) {
        expect(texToUnicode(entry.key), entry.value, reason: entry.key);
      }
    });
  });
}
