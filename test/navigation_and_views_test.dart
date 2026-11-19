import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown/src/headings.dart';
import 'package:llm_markdown/src/line_clip.dart';
import 'package:llm_markdown/src/renderer.dart';
import 'package:llm_markdown/src/svg_image.dart';
import 'package:markdown/markdown.dart' as md;

Widget _host(Widget child, {ScrollController? scroll}) => WidgetsApp(
  color: const Color(0xFF2196F3),
  builder: (context, _) => DefaultTextStyle(
    style: const TextStyle(fontSize: 14, color: Color(0xFF202124)),
    child: SingleChildScrollView(controller: scroll, child: child),
  ),
);

// with a Navigator, for routes
Widget _app(Widget child) => WidgetsApp(
  color: const Color(0xFF2196F3),
  pageRouteBuilder: <T>(settings, builder) =>
      PageRouteBuilder<T>(pageBuilder: (context, _, _) => builder(context)),
  home: DefaultTextStyle(
    style: const TextStyle(fontSize: 14, color: Color(0xFF202124)),
    child: SingleChildScrollView(child: child),
  ),
);

// pumpAndSettle never ends while the cursor blinks
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

String _filler(int n) => List.filled(n, 'Filler paragraph.\n\n').join();

List<TextSpan> _marked(WidgetTester tester) => [
  for (final rich in tester.widgetList<RichText>(find.byType(RichText)))
    ..._leaves(rich.text).where((s) => s.style?.backgroundColor != null),
];

List<TextSpan> _leaves(InlineSpan span) => [
  if (span is TextSpan) ...[
    if (span.text != null) span,
    for (final child in span.children ?? const <InlineSpan>[])
      ..._leaves(child),
  ],
];

void main() {
  group('headings', () {
    test('get GitHub style ids that never repeat', () {
      List<String> ids(String text) => [
        for (final h in assignHeadingIds(
          md.Document().parseLines(text.split('\n')),
          {},
        ))
          h.id,
      ];
      expect(headingSlug('Getting started!'), 'getting-started');
      expect(ids('# A\n\n## A\n\n# A 1\n\n# A\n'), [
        'a',
        'a-1',
        'a-1-1',
        'a-2',
      ]);
      expect(ids('# A 1\n\n# A\n\n# A\n'), ['a-1', 'a', 'a-2']);
      expect(ids('- # In a list\n'), ['in-a-list']);
    });

    testWidgets('are collected while streaming, and scrolled to', (
      tester,
    ) async {
      final controller = StreamingMarkdownController();
      final headings = MarkdownHeadings();
      addTearDown(controller.dispose);
      addTearDown(headings.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        _host(
          StreamingMarkdown(
            controller: controller,
            smoothing: const Smoothing.none(),
            headings: headings,
          ),
          scroll: scroll,
        ),
      );
      controller.append('# Intro\n\n${_filler(40)}## Set');
      await tester.pump();
      await tester.pump();
      expect(headings.headings.map((h) => h.id), ['intro', 'set']);

      controller.append('up\n\nDone.');
      await tester.pump();
      await tester.pump();
      expect(
        headings.headings.last,
        const MarkdownHeading(2, 'Setup', 'setup'),
      );

      expect(await headings.scrollTo('nothing'), isFalse);
      final scrolled = headings.scrollTo('setup');
      await _frames(tester);
      expect(await scrolled, isTrue);
      expect(scroll.offset, greaterThan(0));
    });

    testWidgets('#links scroll to them; a footnote id can match a heading', (
      tester,
    ) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        _host(
          StreamingMarkdown.text(
            '[Go to the end](#the-end)[^1]\n\n${_filler(40)}'
            '# The end\n\n# fn 1\n\n[^1]: A note.\n',
          ),
          scroll: scroll,
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.tapOnText(find.textRange.ofSubstring('Go to the end'));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
    });
  });

  testWidgets('search marks every match, ignoring case', (tester) async {
    Widget reply(String? query) => _host(
      StreamingMarkdown.text(
        'Flutter is fun.\n\nI like **flutter** a lot.\n\n'
        '```\nflutter run\n```\n',
        searchQuery: query,
      ),
    );
    await tester.pumpWidget(reply('FLUTTER'));
    expect(_marked(tester).map((s) => s.text), ['Flutter', 'flutter']);

    await tester.pumpWidget(reply('a lot'));
    expect(_marked(tester).map((s) => s.text), ['a lot']);

    await tester.pumpWidget(reply(null));
    expect(_marked(tester), isEmpty);
  });

  group('images', () {
    const source = '![A cat](https://example.com/cat.png)';
    Widget picture(BuildContext context, Uri uri, String? alt) =>
        const SizedBox(width: 40, height: 30, child: Text('cat picture'));

    testWidgets('report taps', (tester) async {
      Uri? tapped;
      await tester.pumpWidget(
        _app(
          StreamingMarkdown.text(
            source,
            imageBuilder: picture,
            onImageTap: (uri, alt) => tapped = uri,
          ),
        ),
      );
      await tester.tap(find.text('cat picture'));
      expect(tapped.toString(), 'https://example.com/cat.png');
    });

    testWidgets('open full screen to zoom, and close on tap', (tester) async {
      await tester.pumpWidget(
        _app(StreamingMarkdown.text(source, imageBuilder: picture)),
      );
      await tester.tap(find.text('cat picture'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text('cat picture'), findsNWidgets(2));

      await tester.tap(find.byType(InteractiveViewer));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
    });

    testWidgets('SVG pictures are drawn; broken ones show their alt text', (
      tester,
    ) async {
      Uri inline(String svg) =>
          Uri.dataFromString(svg, mimeType: 'image/svg+xml');
      final good = inline(
        '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20">'
        '<rect width="40" height="20" fill="#f00"/></svg>',
      );
      await tester.pumpWidget(
        _app(
          StreamingMarkdown.text(
            '![Red box]($good)',
            allowedImageSchemes: const {'https', 'data'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(SvgPicture)), const Size(40, 20));

      // a file that isn't SVG never reaches the SVG renderer, which in
      // older versions throws an error that can't be caught
      await tester.pumpWidget(
        _app(
          StreamingMarkdown.text(
            '![Broken picture](${inline('this is not svg')})',
            allowedImageSchemes: const {'https', 'data'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(SvgPicture), findsNothing);
      expect(find.text('Broken picture'), findsOneWidget);

      // by address: .svg goes to the SVG path (tests have no network, so
      // the download fails), anything else to Image
      await tester.pumpWidget(
        _app(
          const StreamingMarkdown.text(
            '![Logo](https://example.com/logo.SVG?size=2)\n\n'
            '![Photo](https://example.com/photo.png)',
          ),
        ),
      );
      expect(find.byType(SvgImage), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      expect(find.text('Logo'), findsOneWidget);

      // data: is not allowed by default: the alt text shows
      await tester.pumpWidget(
        _app(StreamingMarkdown.text('![Red box]($good)')),
      );
      expect(find.byType(SvgImage), findsNothing);
    });

    testWidgets('zoomImages: false leaves them alone', (tester) async {
      await tester.pumpWidget(
        _app(
          StreamingMarkdown.text(
            source,
            imageBuilder: picture,
            zoomImages: false,
          ),
        ),
      );
      await tester.tap(find.text('cat picture'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
    });
  });

  testWidgets('maxLines cuts long replies and fades the end', (tester) async {
    RenderHeightClip clip() =>
        tester.renderObject<RenderHeightClip>(find.byType(HeightClip));
    await tester.pumpWidget(
      _host(StreamingMarkdown.text(_filler(20), maxLines: 3)),
    );
    final style = StreamingMarkdownStyle.of(
      tester.element(find.byType(StreamingMarkdown)),
    );
    final line = TextPainter(
      text: TextSpan(text: 'X', style: style.textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    expect(clip().size.height, moreOrLessEquals(line.height * 3));
    expect(clip().overflowing, isTrue);
    expect(tester.layers.whereType<ShaderMaskLayer>(), isNotEmpty);
    line.dispose();

    await tester.pumpWidget(
      _host(const StreamingMarkdown.text('Short.', maxLines: 3)),
    );
    expect(clip().overflowing, isFalse);
    expect(tester.layers.whereType<ShaderMaskLayer>(), isEmpty);
  });

  testWidgets('as a sliver only builds the blocks on screen', (tester) async {
    MarkdownBlockView.debugBuildCounts.clear();
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF2196F3),
        builder: (context, _) => DefaultTextStyle(
          style: const TextStyle(fontSize: 14, color: Color(0xFF202124)),
          child: CustomScrollView(
            slivers: [
              StreamingMarkdown.text(
                List.generate(300, (i) => 'Paragraph $i.\n\n').join(),
                sliver: true,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Paragraph 0.'), findsOneWidget);
    expect(MarkdownBlockView.debugBuildCounts.length, lessThan(100));
    await tester.scrollUntilVisible(
      find.text('Paragraph 299.'),
      2000,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Paragraph 299.'), findsOneWidget);
  });

  testWidgets('jump to latest shows away from the end and jumps back', (
    tester,
  ) async {
    final scroll = ScrollController();
    final controller = StreamingMarkdownController(text: _filler(60));
    addTearDown(scroll.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF2196F3),
        builder: (context, _) => DefaultTextStyle(
          style: const TextStyle(fontSize: 14, color: Color(0xFF202124)),
          child: Stack(
            children: [
              SingleChildScrollView(
                controller: scroll,
                child: StreamingMarkdown(
                  controller: controller,
                  autoScrollController: scroll,
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: JumpToLatest(
                  controller: scroll,
                  content: controller,
                  builder: (context, jump) => GestureDetector(
                    onTap: jump,
                    child: const Text('New messages'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('New messages'), findsOneWidget);

    await tester.tap(find.text('New messages'));
    await _frames(tester);
    expect(scroll.offset, scroll.position.maxScrollExtent);
    expect(find.text('New messages'), findsNothing);

    // following new text keeps it hidden
    controller.append('More text.\n\n');
    await _frames(tester);
    expect(find.text('New messages'), findsNothing);
  });
}
