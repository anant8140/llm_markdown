import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown/src/renderer.dart';
import 'package:markdown/markdown.dart' as md;

Widget _host(Widget child) => WidgetsApp(
  color: const Color(0xFF2196F3),
  builder: (context, _) => DefaultTextStyle(
    style: const TextStyle(fontSize: 14, color: Color(0xFF202124)),
    child: SingleChildScrollView(child: child),
  ),
);

class _Mention extends md.InlineSyntax {
  _Mention() : super(r'@(\w+)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('mention', match[1]!));
    return true;
  }
}

// "!!! text" on one line becomes a callout block
class _Callout extends md.BlockSyntax {
  @override
  RegExp get pattern => RegExp(r'^!!! (.*)$');

  @override
  md.Node parse(md.BlockParser parser) {
    final text = pattern.firstMatch(parser.current.content)![1]!;
    parser.advance();
    return md.Element.text('callout', text);
  }
}

Widget _chip(BuildContext context, md.Element element, bool isComplete) =>
    Text('<${element.textContent}${isComplete ? '' : '…'}>');

void main() {
  testWidgets('custom inline syntax with its own widget', (tester) async {
    final controller = StreamingMarkdownController();
    addTearDown(controller.dispose);
    Widget reply() => _host(
      StreamingMarkdown(
        controller: controller,
        smoothing: const Smoothing.none(),
        syntax: MarkdownSyntax(inlineSyntaxes: [_Mention()]),
        elementBuilders: const {'mention': _chip},
      ),
    );
    await tester.pumpWidget(reply());
    controller.append('Ask @maya about it');
    await tester.pump();
    expect(find.text('<maya…>'), findsOneWidget);
    // inside the paragraph, as an inline widget
    expect(
      find.ancestor(of: find.text('<maya…>'), matching: find.byType(RichText)),
      findsWidgets,
    );

    controller
      ..append('.\n\nNext.')
      ..complete();
    await tester.pump();
    expect(find.text('<maya>'), findsOneWidget);
  });

  testWidgets('a new syntax object of the same kind keeps the cache', (
    tester,
  ) async {
    MarkdownBlockView.debugBuildCounts.clear();
    for (var i = 0; i < 3; i++) {
      await tester.pumpWidget(
        _host(
          StreamingMarkdown.text(
            'One @a.\n\nTwo.\n',
            syntax: MarkdownSyntax(inlineSyntaxes: [_Mention()]),
          ),
        ),
      );
    }
    expect(MarkdownBlockView.debugBuildCounts.values, everyElement(1));
    expect(
      MarkdownSyntax(inlineSyntaxes: [_Mention()]),
      isNot(const MarkdownSyntax()),
    );
  });

  testWidgets('custom block syntax builds a block', (tester) async {
    await tester.pumpWidget(
      _host(
        StreamingMarkdown.text(
          'Before.\n\n!!! Back up first\n\nAfter.\n',
          syntax: MarkdownSyntax(blockSyntaxes: [_Callout()]),
          elementBuilders: {
            'callout': (context, element, _) =>
                Text('CALLOUT ${element.textContent}'),
          },
        ),
      ),
    );
    expect(find.text('CALLOUT Back up first'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('CALLOUT Back up first'),
        matching: find.byType(RichText),
      ),
      findsNothing,
    );
  });

  testWidgets('builders replace built-in elements, or pass with null', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        StreamingMarkdown.text(
          '> quoted\n\n# Title\n',
          elementBuilders: {
            'blockquote': (context, element, _) => const Text('MY QUOTE'),
            'h1': (context, element, _) => null,
          },
        ),
      ),
    );
    expect(find.text('MY QUOTE'), findsOneWidget);
    expect(find.textContaining('quoted'), findsNothing);
    expect(find.text('Title'), findsOneWidget);
  });

  testWidgets('a diagram block waits for its closing fence', (tester) async {
    final controller = StreamingMarkdownController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        StreamingMarkdown(
          controller: controller,
          smoothing: const Smoothing.none(),
          // the README's Mermaid recipe
          codeBlockBuilder: (context, code, language, isComplete) {
            if (language != 'mermaid') return null;
            return Text(isComplete ? 'DIAGRAM ${code.trim()}' : 'drawing…');
          },
        ),
      ),
    );
    controller.append('```mermaid\ngraph TD; A-->B');
    await tester.pump();
    expect(find.text('drawing…'), findsOneWidget);
    controller.append('\n```\n');
    await tester.pump();
    expect(find.text('DIAGRAM graph TD; A-->B'), findsOneWidget);
  });

  testWidgets('blockPadding pads blocks by tag', (tester) async {
    final style = StreamingMarkdownStyle.fromColors(
      textStyle: const TextStyle(fontSize: 14, color: Color(0xFF202124)),
      accentColor: const Color(0xFF1A73E8),
    ).copyWith(blockPadding: {'h2': const EdgeInsets.only(top: 20)});
    await tester.pumpWidget(
      _host(StreamingMarkdown.text('Text.\n\n## Part\n', style: style)),
    );
    final padding = tester.widget<Padding>(
      find
          .ancestor(of: find.text('Part'), matching: find.byType(Padding))
          .first,
    );
    expect(padding.padding, const EdgeInsets.only(top: 20));
  });

  group('theme', () {
    final red = StreamingMarkdownStyle.fromColors(
      textStyle: const TextStyle(fontSize: 14, color: Color(0xFFAA0000)),
      accentColor: const Color(0xFF1A73E8),
    );

    testWidgets('StreamingMarkdownTheme styles the widgets below', (
      tester,
    ) async {
      // Text.rich puts the paragraph's span under the default text style
      Color? color() =>
          (tester.widget<RichText>(find.byType(RichText)).text as TextSpan)
              .children!
              .first
              .style
              ?.color;
      await tester.pumpWidget(
        _host(
          StreamingMarkdownTheme(
            style: red,
            child: const StreamingMarkdown.text('Hello.'),
          ),
        ),
      );
      expect(color(), const Color(0xFFAA0000));

      final blue = red.copyWith(
        textStyle: red.textStyle.copyWith(color: const Color(0xFF0000AA)),
      );
      await tester.pumpWidget(
        _host(
          StreamingMarkdownTheme(
            style: red,
            child: StreamingMarkdown.text('Hello.', style: blue),
          ),
        ),
      );
      expect(color(), const Color(0xFF0000AA));
    });

    test('lerp blends and switches halfway', () {
      final b = StreamingMarkdownStyle.fromColors(
        textStyle: const TextStyle(fontSize: 14, color: Color(0xFFE6E6E6)),
        accentColor: const Color(0xFF8AB4F8),
      ).copyWith(blockSpacing: 20);
      expect(StreamingMarkdownStyle.lerp(red, b, 0), red);
      expect(StreamingMarkdownStyle.lerp(red, b, 1), b);
      final middle = StreamingMarkdownStyle.lerp(red, b, 0.5);
      expect(middle.blockSpacing, 16);
      expect(identical(middle.codeTheme, b.codeTheme), isTrue);
      expect(
        identical(
          StreamingMarkdownStyle.lerp(red, b, 0.4).codeTheme,
          red.codeTheme,
        ),
        isTrue,
      );
    });

    test('presets', () {
      const text = TextStyle(fontSize: 14, color: Color(0xFF202124));
      const accent = Color(0xFF1A73E8);
      final normal = StreamingMarkdownStyle.fromColors(
        textStyle: text,
        accentColor: accent,
      );
      final compact = StreamingMarkdownStyle.compact(
        textStyle: text,
        accentColor: accent,
      );
      final spacious = StreamingMarkdownStyle.spacious(
        textStyle: text,
        accentColor: accent,
      );
      final terminal = StreamingMarkdownStyle.terminal(
        textStyle: text,
        accentColor: accent,
      );
      expect(compact.blockSpacing, lessThan(normal.blockSpacing));
      expect(spacious.blockSpacing, greaterThan(normal.blockSpacing));
      expect(compact.textStyle.height, lessThan(spacious.textStyle.height!));
      expect(
        terminal.textStyle.fontFamily,
        'packages/llm_markdown/JetBrainsMono',
      );
      expect(terminal.headingStyles.map((h) => h.fontSize).toSet(), {
        terminal.textStyle.fontSize,
      });
    });
  });
}
