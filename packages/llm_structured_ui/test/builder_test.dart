import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_structured_ui/llm_structured_ui.dart';

import 'helpers.dart';

void main() {
  group('StructuredBuilder', () {
    testWidgets('rebuilds from a controller after each chunk', (tester) async {
      final c = StructuredStreamController();
      addTearDown(c.dispose);
      await pumpPlain(
        tester,
        StructuredBuilder(
          controller: c,
          builder: (context, data) =>
              Text('title=${data['title'].asString ?? '?'}'),
        ),
      );
      expect(shown(tester), ['title=?']);
      await feed(tester, c, '{"title": "Pan');
      expect(shown(tester), ['title=Pan']);
      await feed(tester, c, 'cakes"}');
      expect(shown(tester), ['title=Pancakes']);
      c.reset();
      await tester.pump();
      expect(shown(tester), ['title=?']);
    });

    testWidgets('reads a stream directly', (tester) async {
      final source = StreamController<String>();
      addTearDown(source.close);
      await pumpPlain(
        tester,
        StructuredBuilder.stream(
          source.stream,
          builder: (context, data) => Text(
            '${data['n'].asNum ?? '-'} '
            '${data.isDone ? 'done' : 'pending'}',
          ),
        ),
      );
      expect(shown(tester), ['- pending']);
      source.add('{"n": 4');
      await delivered(tester);
      expect(shown(tester), ['4 pending']);
      source.add('2}');
      await delivered(tester);
      expect(shown(tester), ['42 done']);
    });

    testWidgets('stream constructor passes repair on', (tester) async {
      await pumpPlain(
        tester,
        StructuredBuilder.stream(
          Stream.value("{name: 'Ann'}"),
          repair: true,
          builder: (context, data) => Text(data['name'].asString ?? 'none'),
          errorBuilder: (context, error, data) => const Text('error'),
        ),
      );
      await delivered(tester);
      expect(shown(tester), ['Ann']);
    });

    testWidgets('without errorBuilder the last good value stays', (
      tester,
    ) async {
      final c = StructuredStreamController();
      addTearDown(c.dispose);
      await pumpPlain(
        tester,
        StructuredBuilder(
          controller: c,
          builder: (context, data) => Text(data['title'].asString ?? '?'),
        ),
      );
      await feed(tester, c, '{"title": "Soup", ');
      await feed(tester, c, '!!');
      expect(c.error, isNotNull);
      expect(shown(tester), ['Soup']);
    });

    testWidgets('errorBuilder gets the error and the last good value', (
      tester,
    ) async {
      final c = StructuredStreamController();
      addTearDown(c.dispose);
      await pumpPlain(
        tester,
        StructuredBuilder(
          controller: c,
          builder: (context, data) => Text(data['title'].asString ?? '?'),
          errorBuilder: (context, error, data) =>
              Text('${error.runtimeType} after ${data['title'].asString}'),
        ),
      );
      await feed(tester, c, '{"title": "Soup", ');
      expect(shown(tester), ['Soup']);
      await feed(tester, c, '!!');
      expect(shown(tester), ['FormatException after Soup']);
      c.reset();
      await tester.pump();
      expect(shown(tester), ['?']);
    });

    testWidgets('a stream that ends early reaches errorBuilder', (
      tester,
    ) async {
      await pumpPlain(
        tester,
        StructuredBuilder.stream(
          Stream.value('{"a": "b'),
          builder: (context, data) => const Text('ok'),
          errorBuilder: (context, error, data) =>
              Text('cut off at ${data['a'].asString}'),
        ),
      );
      await delivered(tester);
      expect(shown(tester), ['cut off at b']);
    });

    testWidgets('follows a new controller and lets go of the old one', (
      tester,
    ) async {
      final a = StructuredStreamController()..add('{"v": "a"}');
      final b = StructuredStreamController()..add('{"v": "b"}');
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      var builds = 0;
      Widget tree(StructuredStreamController c) => StructuredBuilder(
        controller: c,
        builder: (context, data) {
          builds++;
          return Text(data['v'].asString ?? '');
        },
      );
      await pumpPlain(tester, tree(a));
      expect(shown(tester), ['a']);
      await pumpPlain(tester, tree(b));
      expect(shown(tester), ['b']);

      final before = builds;
      a.reset();
      await tester.pump();
      expect(builds, before, reason: 'the old controller is not listened to');
      b.reset();
      await tester.pump();
      expect(builds, before + 1);
    });

    testWidgets('a new stream starts a new document', (tester) async {
      final first = StreamController<String>();
      final second = StreamController<String>();
      addTearDown(first.close);
      addTearDown(second.close);
      Widget tree(Stream<String> s) => StructuredBuilder.stream(
        s,
        builder: (context, data) => Text(data['v'].asString ?? 'empty'),
      );
      await pumpPlain(tester, tree(first.stream));
      first.add('{"v": "one"');
      await delivered(tester);
      expect(shown(tester), ['one']);

      await pumpPlain(tester, tree(second.stream));
      expect(shown(tester), ['empty']);
      expect(first.hasListener, isFalse);
      second.add('{"v": "two"}');
      await delivered(tester);
      expect(shown(tester), ['two']);

      await tester.pumpWidget(const SizedBox());
      expect(second.hasListener, isFalse);
    });
  });
}
