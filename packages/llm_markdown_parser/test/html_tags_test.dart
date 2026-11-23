import 'package:llm_markdown_parser/llm_markdown_parser.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:test/test.dart';

String _html(String text, [MarkdownSyntax syntax = const MarkdownSyntax()]) =>
    md.renderToHtml(newMarkdownDocument(syntax).parse(text));

// The tags of the elements [text] parses to. HTML that is not read as an
// element stays text, which the widget shows as written.
List<String> _tags(
  String text, [
  MarkdownSyntax syntax = const MarkdownSyntax(),
]) {
  final tags = <String>[];
  void walk(md.Node node) {
    if (node is md.Element) {
      tags.add(node.tag);
      node.children?.forEach(walk);
    }
  }

  newMarkdownDocument(syntax).parse(text).forEach(walk);
  return tags;
}

void main() {
  test('b, i, s and strike become the Markdown elements they mean', () {
    expect(
      _html('<b>bold</b> <strong>strong</strong> <i>it</i> <em>em</em>'),
      '<p><strong>bold</strong> <strong>strong</strong> <em>it</em> <em>em</em></p>',
    );
    expect(
      _html(
        '<s>one</s> <del>two</del> <strike>three</strike> <code>x = 1</code>',
      ),
      '<p><del>one</del> <del>two</del> <del>three</del> <code>x = 1</code></p>',
    );
    expect(_html('<B>caps</B>'), '<p><strong>caps</strong></p>');
  });

  test('other tags, attributes and nesting are not read as elements', () {
    expect(_tags('<script>alert(1)</script>'), isNot(contains('script')));
    expect(_tags('<b onclick="x()">no</b>'), ['p']);
    expect(_tags('<a href="x">no</a>'), ['p']);
    // only plain text inside: the outer tag is left as text
    expect(_tags('<b>a <i>b</i></b>'), ['p', 'em']);
    // mismatched tags are not paired
    expect(_tags('<b>x</i>'), ['p']);
    expect(_tags('<b>x</b>'), ['p', 'strong']);
  });

  test('with inlineHtml off none of them is read', () {
    expect(
      _tags(
        '<b>bold</b> <kbd>k</kbd>',
        const MarkdownSyntax(inlineHtml: false),
      ),
      ['p'],
    );
  });

  test('a tag still being written is closed or hidden', () {
    expect(healIncompleteMarkdown('<b>bol'), '<b>bol</b>');
    expect(healIncompleteMarkdown('a <strike>x</str'), 'a <strike>x</strike>');
    expect(healIncompleteMarkdown('a <code>y'), 'a <code>y</code>');
    expect(healIncompleteMarkdown('text <stro'), 'text ');
    // only the "</" of the closing tag has arrived
    expect(healIncompleteMarkdown('H<sub>2</'), 'H<sub>2</sub>');
    expect(healIncompleteMarkdown('<em>done</em> more'), '<em>done</em> more');
  });

  test('every prefix of a line with the tags parses', () {
    const line = 'A <b>bold</b>, <i>it</i>, <s>gone</s> and <code>c</code>.';
    for (var end = 0; end <= line.length; end++) {
      final healed = healIncompleteMarkdown(line.substring(0, end));
      expect(() => _html(healed), returnsNormally, reason: healed);
      // a tag that was opened is closed: none is left half-written
      expect(healed, isNot(matches(RegExp(r'<[a-z/]*$'))), reason: healed);
    }
  });
}
