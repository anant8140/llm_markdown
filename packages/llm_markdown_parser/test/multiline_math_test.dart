import 'package:llm_markdown_parser/llm_markdown_parser.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:test/test.dart';

/// The TeX of each inline math element in [text].
List<String> math(
  String text, [
  MarkdownSyntax syntax = const MarkdownSyntax(),
]) {
  final found = <String>[];
  void walk(md.Node node) {
    if (node is! md.Element) return;
    if (node.tag == 'math-inline' || node.tag.contains('math')) {
      found.add(node.textContent);
    }
    node.children?.forEach(walk);
  }

  newMarkdownDocument(syntax).parse(text).forEach(walk);
  return found;
}

void main() {
  test(r'\( ... \) may run over a line end inside a paragraph', () {
    expect(math('so \\( a + b\n  = c \\) holds'), ['a + b = c']);
    expect(math('one line \\(x^2\\) still'), ['x^2']);
    expect(math('inline display \\[ a\n= b \\] here'), ['a = b']);
    expect(math('text \$\$ a\n= b \$\$ more'), ['a = b']);
  });

  test('not across a blank line: that is two paragraphs', () {
    expect(math('open \\( a +\n\nb \\) closed'), isEmpty);
  });

  test(r'a single $ still has to close on its line', () {
    expect(math('it costs \$5 and\nthen 6\$ more'), isEmpty);
    expect(math('so \$x\$ is'), ['x']);
    expect(math('a \$x +\ny\$ b'), isEmpty);
  });

  test('without dollar math the backslash forms still span lines', () {
    expect(
      math(
        'so \\( a\n= b \\) and \$x\$',
        const MarkdownSyntax(dollarMath: false),
      ),
      ['a = b'],
    );
  });

  test('every prefix of a multi-line formula parses', () {
    const text = 'Start \\( a + b\n = c \\) end, and \\[ x\n y \\] done.';
    for (var end = 0; end <= text.length; end++) {
      final healed = healIncompleteMarkdown(text.substring(0, end));
      expect(() => math(healed), returnsNormally, reason: healed);
    }
    expect(math(text), ['a + b = c', 'x y']);
  });
}
