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
            // these three may run over line ends inside a paragraph; a
            // single $ may not, so that two prices on two lines stay text
            ? r'\\\(([\s\S]+?)\\\)'
                  r'|\$\$([\s\S]+?)\$\$'
                  r'|\\\[([\s\S]+?)\\\]'
                  // not right after a letter or digit: US$5 is a price
                  r'|(?<![\w$])\$(?=[^\s$])((?:\\.|[^$\\\n])+?)(?<=[^\s\\])\$(?!\d)'
            // (?!)() never matches; it keeps the group numbers the same
            : r'\\\(([\s\S]+?)\\\)|(?!)()|\\\[([\s\S]+?)\\\]',
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final display = match[2] != null || match[3] != null;
    final tex = (match[1] ?? match[2] ?? match[3] ?? match[4])!
        .replaceAll(RegExp(r'\s*\n\s*'), ' ')
        .trim();
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

/// A `package:markdown` document with GitHub-flavored Markdown and the
/// extensions turned on in [syntax], as `StreamingMarkdown` parses it.
md.Document newMarkdownDocument([
  MarkdownSyntax syntax = const MarkdownSyntax(),
]) {
  final gfm = md.ExtensionSet.gitHubFlavored;
  return _SafeDocument(
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

// A link definition whose line ends in a backslash, like "[a]: /b\".
final RegExp _definitionEndingInBackslash = RegExp(
  r'^([ \t>]*(?:(?:[-*+]|\d{1,9}[.)])[ \t]+)?\[[^\]]+\]:[ \t]*\S*\\)$',
  multiLine: true,
);

// The markdown package must never take the app down with it.
class _SafeDocument extends md.Document {
  _SafeDocument({
    super.extensionSet,
    super.blockSyntaxes,
    super.inlineSyntaxes,
    super.encodeHtml,
  });

  @override
  List<md.Node> parse(String text) {
    // markdown 7.3 reads past the end of such a line; a space after the
    // destination changes nothing and avoids it
    final safe = text.replaceAllMapped(
      _definitionEndingInBackslash,
      (match) => '${match[1]} ',
    );
    try {
      return super.parse(safe);
    } catch (_) {
      // any other parser bug: show the text as it is
      return [
        md.Element('p', [md.Text(text)]),
      ];
    }
  }
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

/// A readable plain-text version of simple TeX, for when no math renderer
/// is plugged in: `\alpha` becomes α, `x^2` x² and `\frac{a}{b}` a/b.
String texToUnicode(String tex) => _TexReader(tex)
    .read(null)
    .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
    .replaceAll(RegExp(r' *\n *'), '\n')
    .trim();

// \mathbb{R}
const Map<String, String> _doubleStruck = {
  'C': 'ℂ',
  'N': 'ℕ',
  'Q': 'ℚ',
  'R': 'ℝ',
  'Z': 'ℤ',
};

// \vec{v}: a combining mark after the letter
const Map<String, String> _accents = {
  'vec': '⃗',
  'hat': '̂',
  'widehat': '̂',
  'bar': '̄',
  'overline': '̅',
  'tilde': '̃',
  'widetilde': '̃',
  'dot': '̇',
  'ddot': '̈',
};

// commands whose argument is shown as it is
const Set<String> _plainWrappers = {
  'text',
  'textbf',
  'textit',
  'textrm',
  'mathrm',
  'mathbf',
  'mathit',
  'mathsf',
  'mathtt',
  'mathcal',
  'boldsymbol',
  'operatorname',
  'mbox',
};

// sizing and layout commands that draw nothing themselves
const Set<String> _silent = {
  'left',
  'right',
  'big',
  'Big',
  'bigg',
  'Bigg',
  'bigl',
  'bigr',
  'displaystyle',
  'textstyle',
  'limits',
  'nolimits',
};

const Map<String, String> _roots = {'2': '√', '3': '∛', '4': '∜'};

final RegExp _letters = RegExp('[A-Za-z]+');
final RegExp _simple = RegExp(r'^[\p{L}\p{N}.]+$', unicode: true);

class _TexReader {
  _TexReader(this.source);

  final String source;
  int at = 0;

  bool get done => at >= source.length;

  // Reads up to [stop] ("}" or "]") or the end.
  String read(String? stop) {
    final out = StringBuffer();
    while (!done) {
      final char = source[at];
      if (char == stop) {
        at++;
        break;
      }
      switch (char) {
        case r'\':
          out.write(command());
        case '{':
          at++;
          out.write(read('}'));
        case '}':
          // a closing brace with nothing open
          at++;
        case '^':
          at++;
          out.write(script('^', _sup, _supOther));
        case '_':
          at++;
          out.write(script('_', _sub, _subOther));
        case '&' || '~':
          at++;
          out.write(' ');
        default:
          at++;
          out.write(char);
      }
    }
    return out.toString();
  }

  // The next thing a command or script applies to: a {group}, a \command
  // or one character. Empty at the end of the text.
  String argument() {
    while (!done && source[at] == ' ') {
      at++;
    }
    if (done) return '';
    final char = source[at];
    if (char == '{') {
      at++;
      return read('}');
    }
    if (char == r'\') return command();
    if (char == '}') return '';
    at++;
    return char;
  }

  String script(String mark, String digits, Map<String, String> other) {
    final body = argument().trim();
    if (body.isEmpty) return mark;
    final small = _script(body, digits, other);
    if (small != null) return small;
    return body.runes.length == 1 ? '$mark$body' : '$mark($body)';
  }

  String command() {
    at++; // the backslash
    if (done) return '';
    final name = _letters.matchAsPrefix(source, at)?[0];
    if (name == null) {
      final char = source[at++];
      return switch (char) {
        ',' || ';' || ':' || ' ' => ' ',
        '!' => '',
        r'\' => '\n',
        // \{ \} \% \$ \& \# \_ are the characters themselves
        _ => char,
      };
    }
    at += name.length;
    switch (name) {
      case 'frac' || 'dfrac' || 'tfrac':
        final above = argument().trim();
        final below = argument().trim();
        return '${_fractionPart(above)}/${_fractionPart(below)}';
      case 'sqrt':
        var root = '√';
        if (!done && source[at] == '[') {
          at++;
          final index = read(']').trim();
          root =
              _roots[index] ?? '${_script(index, _sup, _supOther) ?? index}√';
        }
        return '$root(${argument().trim()})';
      case 'mathbb':
        final body = argument();
        return _doubleStruck[body] ?? body;
      case 'begin' || 'end':
        // \begin{matrix}: the name is not part of the formula
        argument();
        return name == 'end' ? '' : ' ';
    }
    if (_plainWrappers.contains(name)) return argument();
    final accent = _accents[name];
    if (accent != null) return '${argument()}$accent';
    if (_silent.contains(name)) {
      // \left. and \right. are invisible brackets
      if ((name == 'left' || name == 'right') && !done && source[at] == '.') {
        at++;
      }
      return '';
    }
    // \alpha is α; an unknown name such as \sin is shown as "sin"
    return _symbols[name] ?? name;
  }

  // a and 12 stand alone; a+b needs brackets to stay one thing
  String _fractionPart(String part) =>
      part.isEmpty || _simple.hasMatch(part) || _isBracketed(part)
      ? part
      : '($part)';

  bool _isBracketed(String part) {
    if (!part.startsWith('(') || !part.endsWith(')')) return false;
    var depth = 0;
    for (var i = 0; i < part.length; i++) {
      if (part[i] == '(') depth++;
      if (part[i] == ')') depth--;
      if (depth == 0 && i < part.length - 1) return false;
    }
    return true;
  }
}
