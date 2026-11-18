import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/csharp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/diff.dart';
import 'package:re_highlight/languages/dockerfile.dart';
import 'package:re_highlight/languages/dos.dart';
import 'package:re_highlight/languages/elixir.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/graphql.dart';
import 'package:re_highlight/languages/groovy.dart';
import 'package:re_highlight/languages/haskell.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/latex.dart';
import 'package:re_highlight/languages/less.dart';
import 'package:re_highlight/languages/lua.dart';
import 'package:re_highlight/languages/makefile.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/objectivec.dart';
import 'package:re_highlight/languages/perl.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/languages/plaintext.dart';
import 'package:re_highlight/languages/powershell.dart';
import 'package:re_highlight/languages/protobuf.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/r.dart';
import 'package:re_highlight/languages/ruby.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/scala.dart';
import 'package:re_highlight/languages/scss.dart';
import 'package:re_highlight/languages/shell.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';

import 'fade.dart';
import 'icons.dart';
import 'style.dart';

// Building all 194 grammars takes ~120 ms, so grammars are built one at a
// time, when a code block first needs them. Rare languages load the full set.
final Map<String, Mode Function()> _common = {
  'bash': () => langBash,
  'c': () => langC,
  'cpp': () => langCpp,
  'csharp': () => langCsharp,
  'css': () => langCss,
  'dart': () => langDart,
  'diff': () => langDiff,
  'dockerfile': () => langDockerfile,
  'dos': () => langDos,
  'elixir': () => langElixir,
  'go': () => langGo,
  'graphql': () => langGraphql,
  'groovy': () => langGroovy,
  'haskell': () => langHaskell,
  'ini': () => langIni,
  'java': () => langJava,
  'javascript': () => langJavascript,
  'json': () => langJson,
  'kotlin': () => langKotlin,
  'latex': () => langLatex,
  'less': () => langLess,
  'lua': () => langLua,
  'makefile': () => langMakefile,
  'markdown': () => langMarkdown,
  'objectivec': () => langObjectivec,
  'perl': () => langPerl,
  'php': () => langPhp,
  'plaintext': () => langPlaintext,
  'powershell': () => langPowershell,
  'protobuf': () => langProtobuf,
  'python': () => langPython,
  'r': () => langR,
  'ruby': () => langRuby,
  'rust': () => langRust,
  'scala': () => langScala,
  'scss': () => langScss,
  'shell': () => langShell,
  'sql': () => langSql,
  'swift': () => langSwift,
  'typescript': () => langTypescript,
  'xml': () => langXml,
  'yaml': () => langYaml,
};

const Map<String, String> _aliases = {
  'py': 'python',
  'gyp': 'python',
  'ipython': 'python',
  'js': 'javascript',
  'jsx': 'javascript',
  'mjs': 'javascript',
  'cjs': 'javascript',
  'ts': 'typescript',
  'tsx': 'typescript',
  'mts': 'typescript',
  'cts': 'typescript',
  'jsp': 'java',
  'kt': 'kotlin',
  'kts': 'kotlin',
  'mm': 'objectivec',
  'objc': 'objectivec',
  'obj-c': 'objectivec',
  'golang': 'go',
  'rs': 'rust',
  'h': 'c',
  'cc': 'cpp',
  'c++': 'cpp',
  'h++': 'cpp',
  'hpp': 'cpp',
  'hh': 'cpp',
  'hxx': 'cpp',
  'cxx': 'cpp',
  'cs': 'csharp',
  'c#': 'csharp',
  'rb': 'ruby',
  'gemspec': 'ruby',
  'podspec': 'ruby',
  'pl': 'perl',
  'pm': 'perl',
  'hs': 'haskell',
  'ex': 'elixir',
  'exs': 'elixir',
  'sh': 'bash',
  'zsh': 'bash',
  'console': 'shell',
  'shellsession': 'shell',
  'pwsh': 'powershell',
  'ps': 'powershell',
  'ps1': 'powershell',
  'yml': 'yaml',
  'html': 'xml',
  'xhtml': 'xml',
  'rss': 'xml',
  'atom': 'xml',
  'xsd': 'xml',
  'xsl': 'xml',
  'plist': 'xml',
  'svg': 'xml',
  'md': 'markdown',
  'mkdown': 'markdown',
  'mkd': 'markdown',
  'docker': 'dockerfile',
  'mk': 'makefile',
  'mak': 'makefile',
  'make': 'makefile',
  'patch': 'diff',
  'text': 'plaintext',
  'txt': 'plaintext',
  'toml': 'ini',
  'gql': 'graphql',
  'proto': 'protobuf',
  'tex': 'latex',
  'bat': 'dos',
  'cmd': 'dos',
};

// grammars that highlight embedded code with another grammar
const Map<String, List<String>> _embeds = {
  'xml': ['css', 'javascript'],
  'markdown': ['xml'],
  'dart': ['markdown'],
};

final Highlight _sharedHighlighter = Highlight();
bool _loadedAll = false;

void _register(String name) {
  if (_sharedHighlighter.getLanguage(name) != null) return;
  final mode = _common[name];
  if (mode == null) return;
  _sharedHighlighter.registerLanguage(name, mode());
  _embeds[name]?.forEach(_register);
}

String? _ensureLanguage(String language) {
  final name = language.toLowerCase();
  final canonical = _aliases[name] ?? name;
  _register(canonical);
  if (_sharedHighlighter.getLanguage(canonical) != null) return canonical;
  if (!_loadedAll) {
    _loadedAll = true;
    _sharedHighlighter.registerLanguages(builtinAllLanguages);
  }
  return _sharedHighlighter.getLanguage(name) != null ? name : null;
}

TextSpan? highlightCode(
  String code,
  String? language,
  TextStyle base,
  Map<String, TextStyle> theme,
) {
  if (language == null || language.isEmpty) return null;
  final name = _ensureLanguage(language);
  if (name == null) return null;
  try {
    final result = _sharedHighlighter.highlight(code: code, language: name);
    final renderer = TextSpanRenderer(base, theme);
    result.render(renderer);
    return renderer.span;
  } on Object {
    // some grammars throw on odd input, fall back to plain text
    return null;
  }
}

typedef _Job = (String, String?, TextStyle, Map<String, TextStyle>);

TextSpan? _highlightJob(_Job job) =>
    highlightCode(job.$1, job.$2, job.$3, job.$4);

// Runs on a background isolate (on the web, later in the same one) so the
// first use of a grammar never stalls a frame.
Future<TextSpan?> highlightCodeInBackground(
  String code,
  String? language,
  TextStyle base,
  Map<String, TextStyle> theme,
) {
  if (language == null || language.isEmpty) return SynchronousFuture(null);
  return compute(_highlightJob, (code, language, base, theme));
}

class CodeBlockView extends StatefulWidget {
  const CodeBlockView({
    super.key,
    required this.code,
    required this.language,
    required this.style,
    required this.highlight,
    this.trailing,
    this.fadeLength = 0,
  });

  final int fadeLength;

  final String code;

  final String? language;

  final StreamingMarkdownStyle style;

  final bool highlight;

  final InlineSpan? trailing;

  @override
  State<CodeBlockView> createState() => _CodeBlockViewState();
}

class _CodeBlockViewState extends State<CodeBlockView> {
  TextSpan? _highlighted;
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void initState() {
    super.initState();
    _highlight();
  }

  @override
  void didUpdateWidget(CodeBlockView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code ||
        oldWidget.language != widget.language ||
        oldWidget.highlight != widget.highlight ||
        oldWidget.style != widget.style) {
      _highlight();
    }
  }

  int _job = 0;

  void _highlight() {
    final job = ++_job;
    _highlighted = null;
    if (!widget.highlight) return;
    highlightCodeInBackground(
      widget.code,
      widget.language,
      widget.style.codeBlockTextStyle,
      widget.style.codeTheme,
    ).then((span) {
      if (!mounted || job != _job || span == null) return;
      setState(() => _highlighted = span);
    });
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final header = style.codeBlockHeaderStyle;
    final copyLabel =
        Localizations.of<WidgetsLocalizations>(
          context,
          WidgetsLocalizations,
        )?.copyButtonLabel ??
        'Copy';
    final code = TextSpan(
      style: style.codeBlockTextStyle,
      children: [
        ...(_highlighted == null
            ? fadeTail(
                [TextSpan(text: widget.code)],
                style.codeBlockTextStyle,
                widget.fadeLength,
              )
            : [_highlighted!]),
        if (widget.trailing != null) widget.trailing!,
      ],
    );
    return DecoratedBox(
      decoration: style.codeBlockDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 14, end: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.language ?? 'code',
                    style: header,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Semantics(
                  button: true,
                  label: copyLabel,
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _copy,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MarkdownIcon(
                              _copied
                                  ? MarkdownIconKind.check
                                  : MarkdownIconKind.copy,
                              color: header.color ?? const Color(0xFF808080),
                            ),
                            const SizedBox(width: 4),
                            Text(copyLabel, style: header),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // code reads left to right, also in right-to-left apps
          Directionality(
            textDirection: TextDirection.ltr,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Text.rich(code, softWrap: false),
            ),
          ),
        ],
      ),
    );
  }
}
