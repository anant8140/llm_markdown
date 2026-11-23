import 'package:flutter_test/flutter_test.dart';
import 'package:llm_structured_ui/llm_structured_ui.dart';

import 'helpers.dart';

void main() {
  group('StructuredValue', () {
    test('reads maps and lists', () {
      const v = StructuredValue({
        'title': 'Soup',
        'servings': 4,
        'rating': 4.5,
        'vegan': true,
        'note': null,
        'steps': [
          {'text': 'Chop'},
          {'text': 'Boil'},
        ],
      });
      expect(v['title'].asString, 'Soup');
      expect(v['servings'].asNum, 4);
      expect(v['servings'].asInt, 4);
      expect(v['servings'].asDouble, 4.0);
      expect(v['rating'].asDouble, 4.5);
      expect(v['rating'].asInt, isNull);
      expect(v['vegan'].asBool, isTrue);
      expect(v['steps'][1]['text'].asString, 'Boil');
      expect(v['steps'].asList.map((s) => s['text'].asString), [
        'Chop',
        'Boil',
      ]);
      expect(v.asMap.keys, [
        'title',
        'servings',
        'rating',
        'vegan',
        'note',
        'steps',
      ]);
      expect(v.asMap['title']!.asString, 'Soup');
      expect(v.length, 6);
      expect(v['steps'].length, 2);
      expect(v['title'].length, 0);
      expect(v.isMap, isTrue);
      expect(v['steps'].isList, isTrue);
      expect(v['title'].isScalar, isTrue);
      expect(v['steps'].isScalar, isFalse);
      expect(v['steps'][1]['text'].path, ['steps', 1, 'text']);
      expect(const StructuredValue(2.0).asInt, 2);
    });

    test('a missing key or index does not exist and reads as null', () {
      const v = StructuredValue({
        'a': [1],
      });
      for (final missing in [
        v['nope'],
        v['a'][1],
        v['a'][-1],
        v['a']['key'],
        v[0],
        v['nope']['deeper'][3],
        v[1.5],
      ]) {
        expect(missing.exists, isFalse, reason: '$missing');
        expect(missing.raw, isNull);
        expect(missing.asString, isNull);
        expect(missing.asNum, isNull);
        expect(missing.asBool, isNull);
        expect(missing.asList, isEmpty);
        expect(missing.asMap, isEmpty);
        expect(missing.length, 0);
        expect(missing.isDone, isFalse);
        expect(missing.isPending, isFalse);
        expect(missing.isAwaited, isFalse);
        expect(missing.isNull, isFalse);
        expect(missing.isScalar, isFalse);
      }
      expect(v['nope']['deeper'][3].path, ['nope', 'deeper', 3]);
    });

    test('a value of another type reads as null, not an error', () {
      const v = StructuredValue({'s': 'text', 'n': 1, 'b': true, 'l': []});
      expect(v['s'].asNum, isNull);
      expect(v['s'].asBool, isNull);
      expect(v['s'].asList, isEmpty);
      expect(v['s'].asMap, isEmpty);
      expect(v['n'].asString, isNull);
      expect(v['n'].asBool, isNull);
      expect(v['b'].asString, isNull);
      expect(v['b'].asNum, isNull);
      expect(v['b'].asInt, isNull);
      expect(v['l'].asMap, isEmpty);
      expect(v['l'].asString, isNull);
      expect(v.asList, isEmpty);
    });

    test('a JSON null exists', () {
      const v = StructuredValue({'note': null});
      expect(v['note'].exists, isTrue);
      expect(v['note'].isNull, isTrue);
      expect(v['note'].isDone, isTrue);
      expect(v['other'].isNull, isFalse);
    });

    test('whole JSON is done everywhere', () {
      const v = StructuredValue({
        'a': [1, 2],
      });
      expect(v.isDone, isTrue);
      expect(v.isPending, isFalse);
      expect(v['a'].isDone, isTrue);
      expect(v['a'][1].isDone, isTrue);
      expect(v['a'][1].isPending, isFalse);
      expect(v['b'].isAwaited, isFalse);
    });

    test('missing() is not awaited', () {
      const v = StructuredValue.missing();
      expect(v.exists, isFalse);
      expect(v.isPending, isFalse);
      expect(v.isAwaited, isFalse);
      expect(v['a'].isAwaited, isFalse);
    });

    test('pending and done flags follow the chunks', () {
      final c = StructuredStreamController();

      // nothing yet: the document is awaited, and so is all of it
      expect(c.data.exists, isFalse);
      expect(c.data.isPending, isTrue);
      expect(c.data.isDone, isFalse);
      expect(c.data.isAwaited, isTrue);
      expect(c.data['title'].isAwaited, isTrue);
      expect(c.data['title'].isPending, isFalse);

      c.add('{"title": "Pan');
      var d = c.data;
      expect(d.isPending, isTrue);
      expect(d.isAwaited, isFalse);
      expect(d['title'].asString, 'Pan');
      expect(d['title'].isPending, isTrue);
      expect(d['title'].isDone, isFalse);
      expect(d['steps'].exists, isFalse);
      expect(d['steps'].isAwaited, isTrue);
      expect(d['steps'].isPending, isFalse);
      expect(d['steps'][0]['text'].isAwaited, isTrue);

      c.add('cakes", "steps": [{"text": "Mix"}, {"text": "Fr');
      d = c.data;
      expect(d['title'].isPending, isFalse);
      expect(d['title'].isDone, isTrue);
      expect(d['steps'].isPending, isTrue);
      expect(d['steps'][0].isDone, isTrue);
      expect(d['steps'][0]['text'].isDone, isTrue);
      expect(d['steps'][0]['time'].isAwaited, isFalse);
      expect(d['steps'][1].isPending, isTrue);
      expect(d['steps'][1]['text'].isPending, isTrue);
      expect(d['steps'][1]['time'].isAwaited, isTrue);
      expect(d['steps'][2].isAwaited, isTrue);
      expect(d['servings'].isAwaited, isTrue);

      c.add('y"}], "servings": 1');
      d = c.data;
      expect(d['steps'].isDone, isTrue);
      expect(d['steps'][1].isDone, isTrue);
      expect(d['steps'][2].isAwaited, isFalse);
      expect(d['servings'].asNum, 1);
      expect(d['servings'].isPending, isTrue);

      c.add('2}');
      d = c.data;
      expect(d['servings'].asNum, 12);
      expect(d['servings'].isDone, isTrue);
      expect(d.isDone, isTrue);
      expect(d.isPending, isFalse);
      expect(d['more'].isAwaited, isFalse);
    });

    test('a path that only looks like the pending one is done', () {
      // pendingPath is ['b', 0]; ['a', 0] shares the index, not the key
      final d = partial('{"a": ["x"], "b": ["y');
      expect(d['b'][0].isPending, isTrue);
      expect(d['a'][0].isPending, isFalse);
      expect(d['a'][0].isDone, isTrue);
      expect(d['a'].isDone, isTrue);
    });

    test('after an error nothing is pending, and cut-off values are '
        'not done', () {
      final c = StructuredStreamController()
        ..add('{"title": "Soup", "note": "sal')
        ..close();
      expect(c.error, isNotNull);
      final d = c.data;
      expect(d.isPending, isFalse);
      expect(d.isDone, isFalse);
      expect(d['title'].isDone, isTrue);
      expect(d['note'].asString, 'sal');
      expect(d['note'].isPending, isFalse);
      expect(d['note'].isDone, isFalse);
      expect(d['later'].isAwaited, isFalse);
    });

    test('toString names the path and state', () {
      final d = partial('{"a": {"b": "c');
      expect(d['a']['b'].toString(), 'StructuredValue(a.b: c, pending)');
      expect(d['a']['x'].toString(), contains('missing, awaited'));
      expect(const StructuredValue(1).toString(), contains('done'));
    });
  });
}
