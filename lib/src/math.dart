import 'package:markdown/markdown.dart' as md;

import 'syntaxes.dart';

const String inlineMathTag = 'math';
const String blockMathTag = 'math-block';

// $$...$$ or \[...\] on lines of their own.
final RegExp mathBlockOpener = RegExp(r'^ {0,3}(\$\$|\\\[)[ \t]*$');
final RegExp _bracketOpener = RegExp(r'^ {0,3}(\\\[)[ \t]*$');

RegExp mathOpenerFor({required bool dollar}) =>
    dollar ? mathBlockOpener : _bracketOpener;

RegExp mathBlockCloserFor(String opener) => opener == r'$$'
    ? RegExp(r'^ {0,3}\$\$[ \t]*$')
    : RegExp(r'^ {0,3}\\\][ \t]*$');

// \(x\), $$x$$ and \[x\] inside a line, and $x$. A single $ only counts when
// it hugs the formula ($x$, not $ x $) and the closing one isn't followed by
// a digit, so "$5 and $10" stays text.
class InlineMathSyntax extends md.InlineSyntax {
  InlineMathSyntax({bool dollar = true})
    : super(
        dollar
            ? r'\\\((.+?)\\\)'
                  r'|\$\$(.+?)\$\$'
                  r'|\\\[(.+?)\\\]'
                  r'|\$(?=[^\s$])((?:\\.|[^$\\\n])+?)(?<=[^\s\\])\$(?!\d)'
            // (?!)() never matches; it keeps the group numbers the same
            : r'\\\((.+?)\\\)|(?!)()|\\\[(.+?)\\\]',
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
  MathBlockSyntax({this.dollar = true});

  final bool dollar;

  @override
  RegExp get pattern => mathOpenerFor(dollar: dollar);

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

md.Document newMarkdownDocument([
  MarkdownSyntax syntax = const MarkdownSyntax(),
]) {
  final gfm = md.ExtensionSet.gitHubFlavored;
  return md.Document(
    extensionSet: md.ExtensionSet(gfm.blockSyntaxes, [
      for (final s in gfm.inlineSyntaxes)
        if (syntax.autolinks || s is! md.AutolinkExtensionSyntax) s,
    ]),
    blockSyntaxes: [
      ...syntax.blockSyntaxes,
      MathBlockSyntax(dollar: syntax.dollarMath),
      if (syntax.details) DetailsBlockSyntax(),
      if (syntax.alerts) const AlertSyntax(),
    ],
    inlineSyntaxes: [
      ...syntax.inlineSyntaxes,
      InlineMathSyntax(dollar: syntax.dollarMath),
      if (syntax.inlineHtml) SafeHtmlSyntax(),
      if (syntax.highlightAndSpoilers) ...[HighlightSyntax(), SpoilerSyntax()],
      if (syntax.citations) CitationSyntax(),
      if (syntax.emoji) md.EmojiSyntax(),
      if (syntax.autolinkSchemes.isNotEmpty)
        SchemeAutolinkSyntax(syntax.autolinkSchemes),
    ],
    encodeHtml: false,
  );
}

const Map<String, String> _symbols = {
  'alpha': 'α',
  'beta': 'β',
  'gamma': 'γ',
  'delta': 'δ',
  'epsilon': 'ε',
  'theta': 'θ',
  'lambda': 'λ',
  'mu': 'μ',
  'pi': 'π',
  'sigma': 'σ',
  'tau': 'τ',
  'phi': 'φ',
  'omega': 'ω',
  'Delta': 'Δ',
  'Sigma': 'Σ',
  'Omega': 'Ω',
  'Pi': 'Π',
  'infty': '∞',
  'times': '×',
  'cdot': '·',
  'div': '÷',
  'pm': '±',
  'le': '≤',
  'leq': '≤',
  'ge': '≥',
  'geq': '≥',
  'ne': '≠',
  'neq': '≠',
  'approx': '≈',
  'to': '→',
  'rightarrow': '→',
  'leftarrow': '←',
  'Rightarrow': '⇒',
  'in': '∈',
  'sum': '∑',
  'prod': '∏',
  'int': '∫',
  'partial': '∂',
  'nabla': '∇',
  'forall': '∀',
  'exists': '∃',
  'sqrt': '√',
  'ldots': '…',
  'cdots': '⋯',
  'quad': ' ',
  ',': ' ',
};
const String _sup = '⁰¹²³⁴⁵⁶⁷⁸⁹';
const String _sub = '₀₁₂₃₄₅₆₇₈₉';
const Map<String, String> _supOther = {
  '+': '⁺',
  '-': '⁻',
  '=': '⁼',
  '(': '⁽',
  ')': '⁾',
  'a': 'ᵃ',
  'b': 'ᵇ',
  'c': 'ᶜ',
  'd': 'ᵈ',
  'e': 'ᵉ',
  'i': 'ⁱ',
  'k': 'ᵏ',
  'm': 'ᵐ',
  'n': 'ⁿ',
  'o': 'ᵒ',
  'p': 'ᵖ',
  't': 'ᵗ',
  'x': 'ˣ',
  'y': 'ʸ',
};
const Map<String, String> _subOther = {
  '+': '₊',
  '-': '₋',
  '=': '₌',
  '(': '₍',
  ')': '₎',
  'a': 'ₐ',
  'e': 'ₑ',
  'i': 'ᵢ',
  'j': 'ⱼ',
  'k': 'ₖ',
  'm': 'ₘ',
  'n': 'ₙ',
  'o': 'ₒ',
  'p': 'ₚ',
  's': 'ₛ',
  't': 'ₜ',
  'x': 'ₓ',
};

// null when a character has no superscript/subscript form
String? _script(String body, String digits, Map<String, String> other) {
  final out = StringBuffer();
  for (final char in body.split('')) {
    final digit = int.tryParse(char);
    final mapped = digit != null ? digits[digit] : other[char];
    if (mapped == null) return null;
    out.write(mapped);
  }
  return out.toString();
}

// A readable plain-text version of simple TeX, for when no math renderer
// is plugged in: \alpha -> α, x^2 -> x², \frac{a}{b} -> (a)/(b).
String texToUnicode(String tex) {
  var text = tex.replaceAllMapped(
    RegExp(r'\\frac\{([^{}]*)\}\{([^{}]*)\}'),
    (m) => '(${m[1]})/(${m[2]})',
  );
  text = text.replaceAllMapped(
    RegExp(r'\\sqrt\{([^{}]*)\}'),
    (m) => '√(${m[1]})',
  );
  text = text.replaceAllMapped(
    RegExp(r'\\(?:text|mathrm|mathbf|operatorname)\{([^{}]*)\}'),
    (m) => m[1]!,
  );
  text = text.replaceAllMapped(
    RegExp(r'\\([A-Za-z]+|,)'),
    (m) => _symbols[m[1]] ?? m[1]!,
  );
  String scripts(
    String input,
    String mark,
    String digits,
    Map<String, String> other,
  ) => input.replaceAllMapped(
    RegExp('\\$mark(?:\\{([^{}]*)\\}|([0-9a-z+\\-=()]))'),
    (m) {
      final body = m[1] ?? m[2]!;
      return _script(body, digits, other) ?? '$mark($body)';
    },
  );
  text = scripts(text, '^', _sup, _supOther);
  text = scripts(text, '_', _sub, _subOther);
  return text
      .replaceAll(RegExp(r'[{}]'), '')
      .replaceAll(RegExp(r' {2,}'), ' ')
      .trim();
}
