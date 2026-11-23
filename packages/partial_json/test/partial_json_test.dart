import 'dart:convert';
import 'dart:math';

import 'package:partial_json/partial_json.dart';
import 'package:test/test.dart';

Object? p(String text, {bool lenient = true}) =>
    parsePartialJson(text, lenient: lenient);

void main() {
  group('cut-off documents', () {
    test('strings show the text so far; keys once their value starts', () {
      expect(p('{"title": "Stre'), {'title': 'Stre'});
      expect(p('{"title": "Streaming", "ta'), {'title': 'Streaming'});
      expect(p('{"title": "Streaming", "tags":'), {'title': 'Streaming'});
      expect(p('{"tags": ["a", "b'), {
        'tags': ['a', 'b'],
      });
      expect(p('{"a": {"b": [1, {"c": "d'), {
        'a': {
          'b': [
            1,
            {'c': 'd'},
          ],
        },
      });
    });

    test('numbers show the digits so far; a lone "-" waits', () {
      expect(p('[12'), [12]);
      expect(p('[1, -'), [1]);
      expect(p('[-1.'), [-1]);
      expect(p('[2.5e'), [2.5]);
      expect(p('[2.5e-3, 4'), [0.0025, 4]);
      expect(p('[12345678901234567890'), [12345678901234567890.0]);
    });

    test('t, f and n already show true, false and null', () {
      expect(p('{"a": t'), {'a': true});
      expect(p('{"a": fal'), {'a': false});
      expect(p('[n'), [null]);
    });

    test('escapes, also cut off in the middle', () {
      expect(p(r'["a\"b\\c\/\n\t'), ['a"b\\c/\n\t']);
      expect(p(r'["x\'), ['x']);
      expect(p(r'["x\u00'), ['x']);
      expect(p(r'["xé'), ['xé']);
      expect(p(r'["\ud83d'), ['']);
      expect(p(r'["😀'), ['😀']);
      expect(p('["héllo 👋'), ['héllo 👋']);
    });

    test('nothing yet', () {
      expect(p(''), isNull);
      expect(p('Sure, here it is: '), isNull);
      expect(PartialJsonParser().hasValue, isFalse);
      expect((PartialJsonParser()..add('[')).hasValue, isTrue);
    });
  });

  group('lenient', () {
    test('skips text and code fences around the document', () {
      expect(p('```json\n{"a": 1}\n```'), {'a': 1});
      expect(p('Here you go: [1, 2] Hope that helps! {"no": 1}'), [1, 2]);
    });

    test('allows trailing commas', () {
      expect(p('[1, 2,]'), [1, 2]);
      expect(p('{"a": 1,}'), {'a': 1});
    });

    test('strict mode refuses both, and takes a root scalar', () {
      expect(() => p('x [1]', lenient: false), throwsFormatException);
      expect(() => p('[1,]', lenient: false), throwsFormatException);
      expect(() => p('[1] x', lenient: false), throwsFormatException);
      expect(p('"ab', lenient: false), 'ab');
      final parser = PartialJsonParser(lenient: false)..add('42');
      expect(parser.isComplete, isFalse);
      expect(parser.close(), 42);
      expect(parser.isComplete, isTrue);
    });
  });

  test('wrong JSON throws a FormatException with the offset', () {
    for (final bad in [
      '{"a" 1}',
      '{1: 2}',
      '[1 2]',
      '[tru3]',
      '["a\\x"]',
      '[01]',
      '[1.]',
      '[-]',
      '{"a": 1 "b"}',
      '["\u0001"]',
    ]) {
      expect(
        () => PartialJsonParser(lenient: false)
          ..add(bad)
          ..close(),
        throwsFormatException,
        reason: bad,
      );
    }
    try {
      p('[1, 2 3]');
      fail('no error');
    } on FormatException catch (error) {
      expect(error.offset, 6);
    }
  });

  test('isComplete, close and pendingPath', () {
    final parser = PartialJsonParser();
    expect(parser.pendingPath, isEmpty);
    parser.add('{"items": [{"title": "A');
    expect(parser.pendingPath, ['items', 0, 'title']);
    parser.add('"');
    expect(parser.pendingPath, ['items', 0]);
    parser.add('}, ');
    expect(parser.pendingPath, ['items']);
    parser.add('{"n": 4');
    expect(parser.pendingPath, ['items', 1, 'n']);
    expect(parser.isComplete, isFalse);
    expect(() => parser.close(), throwsFormatException);
    parser.add('2}]}');
    expect(parser.isComplete, isTrue);
    expect(parser.pendingPath, isEmpty);
    expect(parser.close(), {
      'items': [
        {'title': 'A'},
        {'n': 42},
      ],
    });
  });

  test('the value is updated in place', () {
    final parser = PartialJsonParser()..add('{"a": [1');
    final map = parser.value! as Map;
    parser.add(', 2]}');
    expect(identical(parser.value, map), isTrue);
    expect(map, {
      'a': [1, 2],
    });
  });

  test('PartialJsonDecoder gives the value after each piece', () async {
    final values = await Stream.fromIterable([
      'Sure: ',
      '{"a": "x',
      'y", "b": [tr',
      'ue]}',
    ]).transform(const PartialJsonDecoder()).map(jsonEncode).toList();
    expect(values, [
      '{"a":"x"}',
      '{"a":"xy","b":[true]}',
      '{"a":"xy","b":[true]}',
    ]);
    await expectLater(
      Stream.fromIterable(['{"a": ']).transform(const PartialJsonDecoder()),
      emitsInOrder([<String, Object?>{}, emitsError(isFormatException)]),
    );
  });

  group('fuzz', () {
    final random = Random(7);

    Object? randomValue(int depth) {
      final kind = random.nextInt(depth > 3 ? 6 : 8);
      switch (kind) {
        case 0:
          return null;
        case 1:
          return random.nextBool();
        case 2:
          return random.nextInt(2000000) - 1000000;
        case 3:
          return (random.nextDouble() - 0.5) * pow(10, random.nextInt(12) - 4);
        case 4 || 5:
          const pieces = [
            'a',
            'é',
            '👋',
            '"',
            r'\',
            '\n',
            ' ',
            'z',
            '\u0007',
            '/',
          ];
          return [
            for (var i = random.nextInt(8); i > 0; i--)
              pieces[random.nextInt(pieces.length)],
          ].join();
        case 6:
          return [
            for (var i = random.nextInt(5); i > 0; i--) randomValue(depth + 1),
          ];
        default:
          return {
            for (var i = random.nextInt(5); i > 0; i--)
              'k${random.nextInt(9)}$i': randomValue(depth + 1),
          };
      }
    }

    // [partial] can grow into [full]
    void compatible(Object? partial, Object? full, String at) {
      switch (partial) {
        case Map():
          expect(full, isA<Map>(), reason: at);
          full as Map;
          final keys = partial.keys.toList();
          expect(full.keys.take(keys.length).toList(), keys, reason: at);
          for (final key in keys) {
            compatible(partial[key], full[key], at);
          }
        case List():
          expect(full, isA<List>(), reason: at);
          full as List;
          expect(partial.length, lessThanOrEqualTo(full.length), reason: at);
          for (var i = 0; i < partial.length; i++) {
            compatible(partial[i], full[i], at);
          }
        case String():
          expect(full, isA<String>(), reason: at);
          expect((full as String).startsWith(partial), isTrue, reason: at);
        case num():
          expect(full, isA<num>(), reason: at);
        default:
          expect(partial, full, reason: at);
      }
    }

    test('every prefix parses and can grow into the whole', () {
      for (var round = 0; round < 300; round++) {
        final value = random.nextBool()
            ? [randomValue(0)]
            : {'root': randomValue(0)};
        final text = random.nextBool()
            ? jsonEncode(value)
            : const JsonEncoder.withIndent('  ').convert(value);
        final parser = PartialJsonParser();
        var chunkStart = 0;
        for (var end = 1; end <= text.length; end++) {
          final prefix = text.substring(0, end);
          final whole = parsePartialJson(prefix);
          compatible(whole, value, prefix);
          // reading in random pieces gives the same as reading it at once
          if (random.nextInt(4) == 0 || end == text.length) {
            parser.add(text.substring(chunkStart, end));
            chunkStart = end;
            expect(jsonEncode(parser.value), jsonEncode(whole), reason: prefix);
          }
        }
        expect(parser.isComplete, isTrue);
        expect(jsonEncode(parser.close()), jsonEncode(jsonDecode(text)));
      }
    });
  });
}
