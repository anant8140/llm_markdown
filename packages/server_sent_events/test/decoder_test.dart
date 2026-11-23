import 'dart:convert';

import 'package:server_sent_events/server_sent_events.dart';
import 'package:test/test.dart';

Future<List<SseEvent>> decode(
  List<String> chunks, {
  String? lastEventId,
  List<Object?>? calls,
}) => Stream<List<int>>.fromIterable(chunks.map(utf8.encode))
    .transform(
      SseDecoder(
        lastEventId: lastEventId,
        onRetry: (r) => calls?.add(r),
        onLastEventId: (id) => calls?.add('id=$id'),
      ),
    )
    .toList();

void main() {
  test('data lines are joined; event, id and defaults', () async {
    expect(
      await decode(['data: a\ndata:b\n\nevent: add\ndata:  c\nid: 7\n\n']),
      [const SseEvent('a\nb'), const SseEvent(' c', event: 'add', id: '7')],
    );
  });

  test(r'\r\n, \r and \n line ends, split between chunks', () async {
    expect(
      await decode(['data: one\r', '\n\r', '\ndata: two\r\rdata: 3\n', '\n']),
      [const SseEvent('one'), const SseEvent('two'), const SseEvent('3')],
    );
  });

  test('a UTF-8 character split between chunks', () async {
    final bytes = utf8.encode('data: héllo 👋\n\n');
    final events = await Stream<List<int>>.fromIterable([
      for (final b in bytes) [b],
    ]).transform(const SseDecoder()).toList();
    expect(events.single.data, 'héllo 👋');
  });

  test('BOM, comments, unknown fields, a field without a colon', () async {
    expect(await decode(['﻿: ping\nfoo: bar\ndata\n\ndata: x\n\n']), [
      const SseEvent(''),
      const SseEvent('x'),
    ]);
  });

  test(
    'the id lasts across events; with NUL it is ignored; empty clears',
    () async {
      expect(
        await decode([
          'id: 1\ndata: a\n\ndata: b\n\nid: x\u0000y\ndata: c\n\nid\ndata: d\n\n',
        ]),
        [
          const SseEvent('a', id: '1'),
          const SseEvent('b', id: '1'),
          const SseEvent('c', id: '1'),
          const SseEvent('d'),
        ],
      );
    },
  );

  test('retry: only digits count, also without data', () async {
    final calls = <Object?>[];
    final events = await decode([
      'retry: 1500\n\nretry: 2x\ndata: a\n\nretry: 20\ndata: b\n\n',
    ], calls: calls);
    expect(events, [
      const SseEvent('a'),
      const SseEvent('b', retry: Duration(milliseconds: 20)),
    ]);
    expect(calls, [
      const Duration(milliseconds: 1500),
      const Duration(milliseconds: 20),
    ]);
  });

  test('id-only blocks report the new id, once per change', () async {
    final calls = <Object?>[];
    final events = await decode(
      ['id: 5\n\nid: 5\n\nid: 6\ndata: z\n\n'],
      lastEventId: '4',
      calls: calls,
    );
    expect(events, [const SseEvent('z', id: '6')]);
    expect(calls, ['id=5', 'id=6']);
  });

  test('an unfinished event at the end is dropped; empty event type', () async {
    expect(await decode(['event:\ndata: a\n\ndata: half']), [
      const SseEvent('a'),
    ]);
  });

  test('json, isDone and toString', () {
    expect(const SseEvent('{"a":[1]}').json, {
      'a': [1],
    });
    expect(const SseEvent(' [DONE] ').isDone, isTrue);
    expect(const SseEvent('x').isDone, isFalse);
    expect(
      '${const SseEvent('x', event: 'e', id: '1', retry: Duration(seconds: 1))}',
      'SseEvent(e: x, id: 1, retry: 1000 ms)',
    );
  });
}
