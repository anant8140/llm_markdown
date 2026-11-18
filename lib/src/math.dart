import 'package:markdown/markdown.dart' as md;

const String inlineMathTag = 'math';
const String blockMathTag = 'math-block';

// $$...$$ or \[...\] on lines of their own.
final RegExp mathBlockOpener = RegExp(r'^ {0,3}(\$\$|\\\[)[ \t]*$');

RegExp mathBlockCloserFor(String opener) => opener == r'$$'
    ? RegExp(r'^ {0,3}\$\$[ \t]*$')
    : RegExp(r'^ {0,3}\\\][ \t]*$');

// \(x\), $$x$$ and \[x\] inside a line, and $x$. A single $ only counts when
// it hugs the formula ($x$, not $ x $) and the closing one isn't followed by
// a digit, so "$5 and $10" stays text.
class InlineMathSyntax extends md.InlineSyntax {
  InlineMathSyntax()
    : super(
        r'\\\((.+?)\\\)'
        r'|\$\$(.+?)\$\$'
        r'|\\\[(.+?)\\\]'
        r'|\$(?=[^\s$])((?:\\.|[^$\\\n])+?)(?<=[^\s\\])\$(?!\d)',
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final display = match[2] != null || match[3] != null;
    final tex = (match[1] ?? match[2] ?? match[3] ?? match[4])!.trim();
    parser.addNode(
      md.Element.text(inlineMathTag, tex)..attributes['display'] = '$display',
    );
    return true;
  }
}

class MathBlockSyntax extends md.BlockSyntax {
  @override
  RegExp get pattern => mathBlockOpener;

  @override
  bool canEndBlock(md.BlockParser parser) => true;

  @override
  md.Node parse(md.BlockParser parser) {
    final closer = mathBlockCloserFor(
      pattern.firstMatch(parser.current.content)![1]!,
    );
    parser.advance();
    final lines = <String>[];
    var closed = false;
    while (!parser.isDone) {
      final line = parser.current.content;
      parser.advance();
      if (closer.hasMatch(line)) {
        closed = true;
        break;
      }
      lines.add(line);
    }
    // An unclosed block is still arriving; it is shown as source until the
    // closing line comes in.
    return md.Element.text(blockMathTag, lines.join('\n').trim())
      ..attributes['closed'] = '$closed';
  }
}

md.Document newMarkdownDocument() => md.Document(
  extensionSet: md.ExtensionSet.gitHubFlavored,
  blockSyntaxes: [MathBlockSyntax()],
  inlineSyntaxes: [InlineMathSyntax()],
  encodeHtml: false,
);
