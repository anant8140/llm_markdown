import 'dart:convert';
import 'dart:math';

import 'package:partial_json/partial_json.dart';
import 'package:test/test.dart';

void main() {
  test('onComplete reports each finished value with its path', () {
    final done = <String>[];
    PartialJsonParser(
        onComplete: (path, value) => done.add('$path=${jsonEncode(value)}'),
      )
      ..add('{"a": [1, "x", {"b": tr')
      ..add('ue}], "c": n')
      ..add('ull}');
    expect(done, [
      '[a, 0]=1',
      '[a, 1]="x"',
      '[a, 2, b]=true',
      '[a, 2]={"b":true}',
      '[a]=[1,"x",{"b":true}]',
      '[c]=null',
      '[]={"a":[1,"x",{"b":true}],"c":null}',
    ]);
  });

  test('a number is finished by the character after it', () {
    final done = <List<Object>>[];
    final parser = PartialJsonParser(onComplete: (path, _) => done.add(path))
      ..add('[12');
    expect(done, isEmpty);
    parser.add(']');
    expect(done, [
      [0],
      <Object>[],
    ]);
  });

  test('changedPaths: what the last piece touched', () {
    final parser = PartialJsonParser()..add('{"a": "x');
    expect(parser.changedPaths, [
      <Object>[],
      ['a'],
    ]);
    parser.add('y", "b": [');
    expect(parser.changedPaths, [
      ['a'],
      ['b'],
    ]);
    parser.add('   ');
    expect(parser.changedPaths, isEmpty);
    parser.add('1, 2');
    expect(parser.changedPaths, [
      ['b', 0],
      ['b', 1],
    ]);
  });

  test('snapshot is a copy that later pieces leave alone', () {
    final parser = PartialJsonParser()..add('{"a": [1');
    final before = parser.snapshot();
    parser.add(', 2], "b": "c"}');
    expect(before, {
      'a': [1],
    });
    expect(parser.snapshot(), {
      'a': [1, 2],
      'b': 'c',
    });
    expect(identical(parser.snapshot(), parser.value), isFalse);
  });

  group('repair', () {
    test('single quotes, bare keys, comments, Python literals', () {
      const text = '''
{
  // the title
  title: 'It\\'s "fine"',
  /* a * block */ count: 3,
  ok: True, gone: None, no: False,
  'tags': ['a', "b",],
}''';
      expect(parsePartialJson(text, repair: true), {
        'title': 'It\'s "fine"',
        'count': 3,
        'ok': true,
        'gone': null,
        'no': false,
        'tags': ['a', 'b'],
      });
      // without repair the same text is wrong
      expect(() => parsePartialJson(text), throwsFormatException);
    });

    test('cut off in a comment or a bare key', () {
      expect(parsePartialJson('{a: 1, /* note', repair: true), {'a': 1});
      expect(parsePartialJson('{a: 1, nam', repair: true), {'a': 1});
      expect(parsePartialJson("{a: 'Tru", repair: true), {'a': 'Tru'});
      expect(parsePartialJson('[Tr', repair: true), [true]);
    });

    test('repairJson gives valid JSON', () {
      expect(
        repairJson(
          "Sure! ```json\n{name: 'Ann', 'n': [1, 2,], x: None, // hi\n",
        ),
        '{"name":"Ann","n":[1,2],"x":null}',
      );
      expect(
        repairJson('[1, "a\\nb", {"q": "\\u0001"}]'),
        r'[1,"a\nb",{"q":"\u0001"}]',
      );
      expect(() => repairJson('no json here'), throwsFormatException);
      expect(() => repairJson('{a: 1 2}'), throwsFormatException);
    });

    test('fuzz: repair keeps reading real JSON the same', () {
      final random = Random(11);
      for (var round = 0; round < 200; round++) {
        final value = {
          'k': [
            for (var i = random.nextInt(4); i >= 0; i--)
              random.nextBool()
                  ? "it's /* not */ // a comment"
                  : random.nextInt(99),
          ],
        };
        final text = jsonEncode(value);
        for (var end = 1; end <= text.length; end++) {
          expect(
            jsonEncode(parsePartialJson(text.substring(0, end), repair: true)),
            jsonEncode(parsePartialJson(text.substring(0, end))),
          );
        }
        expect(repairJson(text), text);
      }
    });
  });

  test('partialStrings and partialNumbers off show only finished values', () {
    PartialJsonParser p() =>
        PartialJsonParser(partialStrings: false, partialNumbers: false);
    expect((p()..add('{"a": "hal')).value, <String, Object?>{});
    expect((p()..add('{"a": "half"')).value, {'a': 'half'});
    expect((p()..add('[1, 23')).value, [1]);
    expect((p()..add('[1, tr')).value, [1]);
    expect((p()..add('[1, 23]')).value, [1, 23]);
  });

  test('bigInts keeps large whole numbers exact', () {
    expect(parsePartialJson('[12345678901234567890123]', bigInts: true), [
      BigInt.parse('12345678901234567890123'),
    ]);
    // exact on every platform: an int on the VM, a BigInt on the web
    final mixed =
        parsePartialJson('[-9007199254740993, 5, 1.5]', bigInts: true)! as List;
    expect('${mixed[0]}', '-9007199254740993');
    expect(mixed.skip(1), [5, 1.5]);
    expect(parsePartialJson('[12345678901234567890123]')!, [isA<double>()]);
  });

  test('errors name the line and column', () {
    expect(
      () => parsePartialJson('{\n  "a": 1\n  "b": 2}'),
      throwsA(
        isA<FormatException>()
            .having((e) => e.message, 'message', contains('line 3, column 3'))
            .having((e) => e.offset, 'offset', 13),
      ),
    );
  });

  test('PartialJsonDecoder with snapshots gives separate copies', () async {
    final values = await Stream.fromIterable([
      '[1',
      ', 2',
      ']',
    ]).transform(const PartialJsonDecoder(snapshots: true)).toList();
    expect(values, [
      [1],
      [1, 2],
      [1, 2],
    ]);
    expect(identical(values[0], values[1]), isFalse);
  });

  test('PartialJsonItemDecoder gives each item once it is finished', () async {
    final seen = <String>[];
    final items =
        Stream.fromIterable([
              '{"recipes": [{"name": "So',
              'up"}, {"name": "Pie", "steps": [1, 2]}',
              ', {"name": "Tea"}], "other": [{"name": "no"}]}',
            ])
            .transform(
              PartialJsonItemDecoder(
                path: const ['recipes'],
                convert: (json) => (json! as Map)['name'] as String,
              ),
            )
            .map((name) => name);
    await for (final name in items) {
      seen.add(name);
    }
    expect(seen, ['Soup', 'Pie', 'Tea']);

    final root = await Stream.fromIterable(['[1, [2], ', '3]'])
        .transform(PartialJsonItemDecoder(path: const [], convert: (j) => j))
        .toList();
    expect(root, [
      1,
      [2],
      3,
    ]);
  });

  test('PartialJsonDocumentsDecoder reads JSON Lines', () async {
    final docs =
        await Stream.fromIterable(['{"a": 1}\n{"b": ', '2}\n', '[3]\n{"c": "x'])
            .transform(const PartialJsonDocumentsDecoder())
            .toList()
            .then(
              (docs) => docs.map(
                (d) => '${d.index}:${jsonEncode(d.value)}:${d.isComplete}',
              ),
              onError: (Object e) => ['error'],
            );
    expect(docs, ['error']);

    final good = await Stream.fromIterable([
      '{"a": 1}\n{"b": ',
      '2}\n[3]',
      '\n',
    ]).transform(const PartialJsonDocumentsDecoder()).toList();
    expect(
      good.map((d) => '${d.index}:${jsonEncode(d.value)}:${d.isComplete}'),
      ['0:{"a":1}:true', '1:{}:false', '1:{"b":2}:true', '2:[3]:true'],
    );
  });

  test('ToolArgumentsParser follows several calls', () {
    final args = ToolArgumentsParser();
    expect(args.add('a', '{"city": "Pa'), {'city': 'Pa'});
    args.add('b', '{"q":');
    args.add('a', 'ris"}');
    expect(args['a'], {'city': 'Paris'});
    expect(args.isComplete('a'), isTrue);
    expect(args.isComplete('b'), isFalse);
    expect(args.ids, ['a', 'b']);
    expect(args.close('a'), {'city': 'Paris'});
    expect(() => args.close('b'), throwsFormatException);
    expect(args.close('none'), <String, Object?>{});
    // arguments are plain JSON: text around them is an error
    expect(() => args.add('c', 'Sure: {"a": 1}'), throwsFormatException);
    args.remove('a');
    expect(args['a'], isNull);
  });
}
