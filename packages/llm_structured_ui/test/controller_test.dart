import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_structured_ui/llm_structured_ui.dart';

void main() {
  group('StructuredStreamController', () {
    test('starts empty', () {
      final c = StructuredStreamController();
      expect(c.value, isNull);
      expect(c.hasValue, isFalse);
      expect(c.isComplete, isFalse);
      expect(c.isClosed, isFalse);
      expect(c.error, isNull);
      expect(c.pendingPath, isEmpty);
    });

    test('value, pendingPath and isComplete follow the chunks', () {
      final c = StructuredStreamController();
      c.add('{"title": "Pan');
      expect(c.value, {'title': 'Pan'});
      expect(c.pendingPath, ['title']);
      expect(c.isComplete, isFalse);

      c.add('cakes", "steps": ["Mix", "Fr');
      expect(c.value, {
        'title': 'Pancakes',
        'steps': ['Mix', 'Fr'],
      });
      expect(c.pendingPath, ['steps', 1]);

      c.add('y"]}');
      expect(c.value, {
        'title': 'Pancakes',
        'steps': ['Mix', 'Fry'],
      });
      expect(c.isComplete, isTrue);
      expect(c.pendingPath, isEmpty);
      expect(c.error, isNull);
    });

    test('tells listeners after every add, close and reset', () {
      final c = StructuredStreamController();
      var calls = 0;
      c.addListener(() => calls++);
      c.add('{"a"');
      expect(calls, 1);
      c.add(': 1}');
      expect(calls, 2);
      c.close();
      expect(calls, 3);
      c.reset();
      expect(calls, 4);
    });

    test('wrong JSON sets error and keeps the last good value', () {
      final c = StructuredStreamController();
      var calls = 0;
      c.addListener(() => calls++);
      c.add('{"title": "Soup", ');
      c.add('oops');
      expect(c.error, isA<FormatException>());
      expect(c.value, {'title': 'Soup'});
      expect(calls, 2);

      // later pieces are ignored and do not throw
      c.add('"more": 1}');
      expect(c.value, {'title': 'Soup'});
      expect(c.isComplete, isFalse);
      expect(c.error, isA<FormatException>());
    });

    test('close on a whole document sets no error', () {
      final c = StructuredStreamController()..add('{"a": 1}');
      c.close();
      expect(c.isClosed, isTrue);
      expect(c.error, isNull);
      expect(c.value, {'a': 1});
    });

    test('close in the middle sets error and keeps the value', () {
      final c = StructuredStreamController()..add('{"a": [1, 2');
      c.close();
      expect(c.isClosed, isTrue);
      expect(c.error, isA<FormatException>());
      expect(c.value, {
        'a': [1, 2],
      });
    });

    test('close after an error keeps the first error', () {
      final c = StructuredStreamController()..add('{"a": x');
      final first = c.error;
      expect(first, isNotNull);
      c.close();
      expect(c.error, same(first));
    });

    test('add after close throws until reset', () {
      final c = StructuredStreamController()
        ..add('{}')
        ..close();
      expect(() => c.add('{}'), throwsStateError);
      c.reset();
      c.add('[1]');
      expect(c.value, [1]);
    });

    test('reset forgets the document and the error', () {
      final c = StructuredStreamController()..add('{"a": x');
      expect(c.error, isNotNull);
      c.reset();
      expect(c.error, isNull);
      expect(c.value, isNull);
      expect(c.hasValue, isFalse);
      expect(c.isClosed, isFalse);
      c.add('{"b": 2}');
      expect(c.value, {'b': 2});
      expect(c.isComplete, isTrue);
    });

    test('repair reads common mistakes, and is off by default', () {
      final strict = StructuredStreamController()..add("{name: 'Ann'}");
      expect(strict.error, isA<FormatException>());

      final repairing = StructuredStreamController(repair: true)
        ..add("{name: 'Ann', ok: True}");
      expect(repairing.error, isNull);
      expect(repairing.value, {'name': 'Ann', 'ok': true});

      // still repairing after a reset
      repairing
        ..reset()
        ..add("{'a': None}");
      expect(repairing.error, isNull);
      expect(repairing.value, {'a': null});
    });

    test('text around the document is skipped', () {
      final c = StructuredStreamController()
        ..add('Here it is:\n```json\n{"a": 1}\n```');
      expect(c.error, isNull);
      expect(c.value, {'a': 1});
      expect(c.isComplete, isTrue);
    });

    test('data reads the current state', () {
      final c = StructuredStreamController();
      expect(c.data.exists, isFalse);
      expect(c.data.isPending, isTrue);
      c.add('{"a": "x');
      expect(c.data['a'].asString, 'x');
      expect(c.data['a'].isPending, isTrue);
      c.add('"}');
      expect(c.data['a'].isDone, isTrue);
      expect(c.data.isDone, isTrue);
    });

    group('addStream', () {
      test('adds each event and closes at the end', () async {
        final c = StructuredStreamController();
        await c.addStream(Stream.fromIterable(['{"a": ', '[1, ', '2]}']));
        expect(c.value, {
          'a': [1, 2],
        });
        expect(c.isComplete, isTrue);
        expect(c.isClosed, isTrue);
        expect(c.error, isNull);
      });

      test('a stream that ends in the middle sets error', () async {
        final c = StructuredStreamController();
        await c.addStream(Stream.fromIterable(['{"a": "b']));
        expect(c.error, isA<FormatException>());
        expect(c.value, {'a': 'b'});
        expect(c.isClosed, isTrue);
      });

      test('reset completes the future and stops reading', () async {
        final c = StructuredStreamController();
        final source = StreamController<String>();
        var done = false;
        final future = c.addStream(source.stream).then((_) => done = true);
        source.add('{"a": 1, ');
        await pumpEventQueue();
        expect(c.value, {'a': 1});
        expect(source.hasListener, isTrue);
        expect(done, isFalse);

        c.reset();
        await future;
        expect(done, isTrue);
        expect(source.hasListener, isFalse);
        expect(c.value, isNull);
        expect(c.error, isNull);
        expect(c.isClosed, isFalse);

        // the old stream is no longer read
        source.add('"b": 2}');
        await pumpEventQueue();
        expect(c.value, isNull);
        await source.close();
        expect(c.isClosed, isFalse);
      });

      test('an error of the stream is kept and ends reading', () async {
        final c = StructuredStreamController();
        final source = StreamController<String>();
        var calls = 0;
        final future = c.addStream(source.stream);
        source.add('{"a": 1');
        await pumpEventQueue();
        c.addListener(() => calls++);
        source.addError(StateError('network'));
        await future;
        expect(c.error, isStateError);
        expect(c.value, {'a': 1});
        expect(source.hasListener, isFalse);
        expect(calls, 1);
        expect(c.data.isPending, isFalse);
      });

      test('wrong JSON in the stream ends reading', () async {
        final c = StructuredStreamController();
        final source = StreamController<String>();
        final future = c.addStream(source.stream);
        source.add('{"a": 1, !');
        await future;
        expect(c.error, isA<FormatException>());
        expect(c.value, {'a': 1});
        expect(source.hasListener, isFalse);
      });

      test('a second addStream replaces the first', () async {
        final c = StructuredStreamController();
        final first = StreamController<String>();
        final firstDone = c.addStream(first.stream);
        final second = c.addStream(Stream.fromIterable(['[1, 2]']));
        await firstDone;
        expect(first.hasListener, isFalse);
        await second;
        expect(c.value, [1, 2]);
      });

      test('dispose stops reading and completes the future', () async {
        final c = StructuredStreamController();
        final source = StreamController<String>();
        final future = c.addStream(source.stream);
        c.dispose();
        await future;
        expect(source.hasListener, isFalse);
      });
    });
  });
}
