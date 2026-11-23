import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';

Stream<List<int>> _body(String text, {int chunk = 7}) async* {
  final bytes = utf8.encode(text);
  for (var i = 0; i < bytes.length; i += chunk) {
    yield bytes.sublist(i, i + chunk > bytes.length ? bytes.length : i + chunk);
  }
}

String _sse(Iterable<Map<String, Object?>> events) =>
    events.map((e) => 'data: ${jsonEncode(e)}\n\n').join();

String _calls(StreamingMarkdownController c) => c.toolCalls
    .map((t) => '${t.id}:${t.name}(${t.arguments})${t.isDone ? '.' : ''}')
    .join(' ');

Widget _host(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: MediaQuery(
    data: const MediaQueryData(),
    child: DefaultTextStyle(
      style: const TextStyle(fontSize: 14, color: Color(0xFF000000)),
      child: child,
    ),
  ),
);

void main() {
  group('controller', () {
    test('sources are numbered once each and cleared on reset', () {
      final c = StreamingMarkdownController();
      expect(c.addSource(const MarkdownSource(url: 'https://a')), 1);
      expect(c.addSource(const MarkdownSource(title: 'Doc')), 2);
      expect(
        c.addSource(const MarkdownSource(url: 'https://a', title: 'A again')),
        1,
      );
      expect(c.addSource(const MarkdownSource(title: 'Doc')), 2);
      expect(c.addSource(const MarkdownSource(url: 'https://b')), 3);
      expect(c.sources.map((s) => s.url ?? s.title), [
        'https://a',
        'Doc',
        'https://b',
      ]);
      c.startToolCall('t1', 'search');
      c.reset();
      expect(c.sources, isEmpty);
      expect(c.toolCalls, isEmpty);
    });

    test('tool calls fill in, finish, and finish on complete', () {
      final c = StreamingMarkdownController();
      var notified = 0;
      c.addListener(() => notified++);
      c
        ..startToolCall('a', '')
        ..startToolCall('a', 'get_weather')
        ..startToolCall('a', 'ignored')
        ..addToolCallArguments('a', '{"city":')
        ..addToolCallArguments('a', '"Surat"}')
        ..addToolCallArguments('nope', 'x')
        ..startToolCall('b', 'web_search')
        ..finishToolCall('a');
      expect(_calls(c), 'a:get_weather({"city":"Surat"}). b:web_search()');
      expect(notified, 6);
      c.complete();
      expect(c.toolCalls.every((t) => t.isDone), isTrue);
    });
  });

  group('adapters', () {
    test('OpenAI chat: tool call deltas by index, url citations', () async {
      Map<String, Object?> delta(Map<String, Object?> d) => {
        'choices': [
          {'delta': d},
        ],
      };
      final c = StreamingMarkdownController();
      await c.addOpenAIStream(
        _body(
          '${_sse([
            delta({
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'call_9',
                  'function': {'name': 'get_weather', 'arguments': ''},
                },
              ],
            }),
            delta({
              'tool_calls': [
                {
                  'index': 0,
                  'function': {'arguments': '{"city"'},
                },
              ],
            }),
            delta({
              'tool_calls': [
                {
                  'index': 0,
                  'function': {'arguments': ':"Pune"}'},
                },
              ],
            }),
            delta({
              'content': 'Sunny.',
              'annotations': [
                {
                  'type': 'url_citation',
                  'url_citation': {'url': 'https://w', 'title': 'W'},
                },
                {'type': 'other'},
              ],
            }),
          ])}data: [DONE]\n\n',
        ),
      );
      expect(_calls(c), 'call_9:get_weather({"city":"Pune"}).');
      expect(c.text, 'Sunny.');
      expect(c.sources, [const MarkdownSource(url: 'https://w', title: 'W')]);
    });

    test('OpenAI Responses: function and web search calls', () async {
      final c = StreamingMarkdownController();
      await c.addOpenAIStream(
        _body(
          _sse([
            {
              'type': 'response.output_item.added',
              'item': {'type': 'web_search_call', 'id': 'ws_1'},
            },
            {
              'type': 'response.output_item.done',
              'item': {'type': 'web_search_call', 'id': 'ws_1'},
            },
            {
              'type': 'response.output_item.added',
              'item': {'type': 'function_call', 'id': 'fc_1', 'name': 'add'},
            },
            {
              'type': 'response.function_call_arguments.delta',
              'item_id': 'fc_1',
              'delta': '{"a":1}',
            },
            {
              'type': 'response.output_item.added',
              'item': {'type': 'message', 'id': 'm'},
            },
            {'type': 'response.output_text.delta', 'delta': 'Done'},
            {
              'type': 'response.output_text.annotation.added',
              'annotation': {
                'type': 'url_citation',
                'url': 'https://r',
                'title': 'R',
              },
            },
            {'type': 'response.completed'},
          ]),
        ),
      );
      expect(_calls(c), 'ws_1:web_search(). fc_1:add({"a":1}).');
      expect(c.sources.single.url, 'https://r');
      expect(c.text, 'Done');
    });

    test('Anthropic: tool use, and [n] after cited text', () async {
      final c = StreamingMarkdownController();
      final events = [
        {
          'type': 'content_block_start',
          'index': 0,
          'content_block': {
            'type': 'server_tool_use',
            'id': 'srv_1',
            'name': 'web_search',
          },
        },
        {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {
            'type': 'input_json_delta',
            'partial_json': '{"query":"x"}',
          },
        },
        {'type': 'content_block_stop', 'index': 0},
        {
          'type': 'content_block_start',
          'index': 1,
          'content_block': {'type': 'text', 'text': ''},
        },
        {
          'type': 'content_block_delta',
          'index': 1,
          'delta': {
            'type': 'citations_delta',
            'citation': {
              'type': 'web_search_result_location',
              'url': 'https://a',
              'title': 'A',
              'cited_text': 'sky is blue',
            },
          },
        },
        {
          'type': 'content_block_delta',
          'index': 1,
          'delta': {
            'type': 'citations_delta',
            'citation': {'url': 'https://b', 'title': 'B'},
          },
        },
        {
          'type': 'content_block_delta',
          'index': 1,
          'delta': {
            'type': 'citations_delta',
            'citation': {'url': 'https://a', 'title': 'A'},
          },
        },
        {
          'type': 'content_block_delta',
          'index': 1,
          'delta': {'type': 'text_delta', 'text': 'The sky is blue'},
        },
        {'type': 'content_block_stop', 'index': 1},
        {
          'type': 'content_block_delta',
          'index': 2,
          'delta': {'type': 'text_delta', 'text': '. Also '},
        },
        {
          'type': 'content_block_delta',
          'index': 3,
          'delta': {
            'type': 'citations_delta',
            'citation': {'url': 'https://a', 'title': 'A'},
          },
        },
        {
          'type': 'content_block_delta',
          'index': 3,
          'delta': {'type': 'text_delta', 'text': 'it is wide'},
        },
        {'type': 'content_block_stop', 'index': 3},
        {'type': 'message_stop'},
      ];
      final body = StreamController<List<int>>();
      final done = c.addAnthropicStream(body.stream);
      body.add(utf8.encode(_sse(events.take(3))));
      await pumpEventQueue();
      // finished when its block ends, before the reply does
      expect(_calls(c), 'srv_1:web_search({"query":"x"}).');
      expect(c.isComplete, isFalse);
      body.add(utf8.encode(_sse(events.skip(3))));
      await body.close();
      await done;
      expect(c.text, 'The sky is blue [1][2]. Also it is wide [1]');
      expect(c.sources.first.citedText, 'sky is blue');
      expect(c.sources.length, 2);
    });

    test('Gemini: function calls and grounding pages', () async {
      final c = StreamingMarkdownController();
      await c.addGeminiStream(
        _body(
          _sse([
            {
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {
                        'functionCall': {
                          'name': 'find',
                          'args': {'q': 1},
                        },
                      },
                      {'text': 'Answer'},
                    ],
                  },
                  'groundingMetadata': {
                    'groundingChunks': [
                      {
                        'web': {'uri': 'https://g', 'title': 'g.com'},
                      },
                      {
                        'web': {'uri': 'https://g', 'title': 'g.com'},
                      },
                    ],
                  },
                },
              ],
            },
          ]),
        ),
      );
      expect(_calls(c), 'call_0:find({"q":1}).');
      expect(c.text, 'Answer');
      expect(c.sources, [
        const MarkdownSource(url: 'https://g', title: 'g.com'),
      ]);
    });

    test('Ollama: tool calls with object arguments', () async {
      final c = StreamingMarkdownController();
      await c.addOllamaStream(
        _body(
          [
            {
              'message': {
                'role': 'assistant',
                'content': '',
                'tool_calls': [
                  {
                    'function': {
                      'name': 'get_time',
                      'arguments': {'zone': 'IST'},
                    },
                  },
                ],
              },
              'done': false,
            },
            {
              'message': {'role': 'assistant', 'content': 'Noon'},
              'done': true,
            },
          ].map(jsonEncode).join('\n'),
        ),
      );
      expect(_calls(c), 'call_0:get_time({"zone":"IST"}).');
      expect(c.text, 'Noon');
    });
  });

  group('fixes', () {
    test('an error ends running tool calls too', () async {
      final c = StreamingMarkdownController();
      await expectLater(
        c.addAnthropicStream(
          _body(
            _sse([
              {
                'type': 'content_block_start',
                'index': 0,
                'content_block': {
                  'type': 'server_tool_use',
                  'id': 's',
                  'name': 'web_search',
                },
              },
              {
                'type': 'error',
                'error': {'message': 'Overloaded'},
              },
            ]),
          ),
        ),
        throwsA(isA<ModelStreamError>()),
      );
      expect(c.toolCalls.single.isDone, isTrue);
    });

    Map<String, Object?> cite(int index, String url) => {
      'type': 'content_block_delta',
      'index': index,
      'delta': {
        'type': 'citations_delta',
        'citation': {'url': url, 'title': url},
      },
    };
    Map<String, Object?> say(int index, String text) => {
      'type': 'content_block_delta',
      'index': index,
      'delta': {'type': 'text_delta', 'text': text},
    };
    Map<String, Object?> stop(int index) => {
      'type': 'content_block_stop',
      'index': index,
    };

    test(
      '[n] goes next to the cited words, never into code or a table',
      () async {
        final c = StreamingMarkdownController();
        await c.addAnthropicStream(
          _body(
            _sse([
              cite(0, 'a'),
              say(0, 'Water boils at 100 °C.\n\n'),
              stop(0),
              say(1, '```\nprint(1)\n'),
              cite(2, 'b'),
              say(2, 'x = 2\n'),
              stop(2),
              say(3, '```'),
              cite(4, 'c'),
              say(4, '\n\n| a | b |\n|---|---|\n| 1 | 2 |'),
              stop(4),
              cite(5, 'd'),
              say(5, '\n\nDone'),
              stop(5),
              cite(6, 'e'),
              stop(6),
              {'type': 'message_stop'},
            ]),
          ),
        );
        expect(
          c.text,
          'Water boils at 100 °C. [1]\n\n'
          '```\nprint(1)\nx = 2\n```\n\n'
          '| a | b |\n|---|---|\n| 1 | 2 |\n\n'
          'Done [4]',
        );
        // every source is still listed, marked or not
        expect(c.sources.length, 5);
      },
    );

    test('no [n] after a closing fence', () async {
      final c = StreamingMarkdownController();
      await c.addAnthropicStream(
        _body(
          _sse([
            cite(0, 'a'),
            say(0, '```\ncode\n```'),
            stop(0),
            {'type': 'message_stop'},
          ]),
        ),
      );
      expect(c.text, '```\ncode\n```');
    });

    test('a reply stopped by the app ignores what still comes', () async {
      final body = StreamController<List<int>>();
      final c = StreamingMarkdownController();
      final done = c.addAnthropicStream(body.stream);
      body.add(utf8.encode(_sse([say(0, 'Hello')])));
      await pumpEventQueue();
      c.complete();
      body.add(
        utf8.encode(
          _sse([
            say(0, ' more'),
            {
              'type': 'content_block_start',
              'index': 1,
              'content_block': {'type': 'tool_use', 'id': 't', 'name': 'x'},
            },
          ]),
        ),
      );
      await body.close();
      await done;
      expect(c.text, 'Hello');
      expect(c.toolCalls, isEmpty);
      expect(c.error, isNull);
    });

    test('sources: search results, and untitled ones kept apart', () async {
      final c = StreamingMarkdownController();
      await c.addAnthropicStream(
        _body(
          _sse([
            {
              'type': 'content_block_delta',
              'index': 0,
              'delta': {
                'type': 'citations_delta',
                'citation': {
                  'type': 'search_result_location',
                  'source': 'https://docs/x',
                  'title': 'X',
                },
              },
            },
            say(0, 'Fact'),
            stop(0),
            {'type': 'message_stop'},
          ]),
        ),
      );
      expect(c.sources.single.url, 'https://docs/x');
      expect(c.addSource(const MarkdownSource(citedText: 'one')), 2);
      expect(c.addSource(const MarkdownSource(citedText: 'two')), 3);
    });

    test('Gemini: a blocked prompt and a cut-off array are errors', () async {
      final blocked = StreamingMarkdownController();
      await expectLater(
        blocked.addGeminiStream(
          _body(
            'data: ${jsonEncode({
              'promptFeedback': {'blockReason': 'SAFETY'},
            })}\n\n',
          ),
        ),
        throwsA(isA<ModelStreamError>()),
      );
      expect('${blocked.error}', contains('SAFETY'));

      final cut = StreamingMarkdownController();
      await expectLater(
        cut.addGeminiStream(
          _body(
            '[${jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'Half'},
                    ],
                  },
                },
              ],
            })},{"candidates": [{"content',
          ),
        ),
        throwsA(isA<ModelStreamError>()),
      );
      expect(cut.text, 'Half');
    });

    test('OpenAI: refusals, whole arguments, finish_reason', () async {
      final body = StreamController<List<int>>();
      final c = StreamingMarkdownController();
      final done = c.addOpenAIStream(body.stream);
      body.add(
        utf8.encode(
          _sse([
            {
              'choices': [
                {
                  'delta': {
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'c1',
                        'function': {'name': 'f', 'arguments': '{}'},
                      },
                    ],
                  },
                },
              ],
            },
            {
              'choices': [
                {'delta': <String, Object?>{}, 'finish_reason': 'tool_calls'},
              ],
            },
          ]),
        ),
      );
      await pumpEventQueue();
      expect(c.toolCalls.single.isDone, isTrue);
      expect(c.isComplete, isFalse);
      await body.close();
      await done;

      final refused = StreamController<List<int>>();
      final r = StreamingMarkdownController();
      final rDone = r.addOpenAIStream(refused.stream);
      refused.add(
        utf8.encode(
          _sse([
            {
              'choices': [
                {
                  'delta': {'refusal': "I can't help with that."},
                },
              ],
            },
            {
              'type': 'response.output_item.added',
              'item': {'type': 'function_call', 'id': 'fc', 'name': 'g'},
            },
            {
              'type': 'response.output_item.done',
              'item': {
                'type': 'function_call',
                'id': 'fc',
                'arguments': '{"a":1}',
              },
            },
            {
              'type': 'response.output_item.added',
              'item': {'type': 'web_search_call'},
            },
          ]),
        ),
      );
      await refused.close();
      await rDone;
      expect(r.text, "I can't help with that.");
      expect(_calls(r), 'fc:g({"a":1}).');
    });
  });

  group('closing the connection', () {
    for (final (name, end) in [
      ('reset', (StreamingMarkdownController c) => c.reset()),
      ('a stop button', (StreamingMarkdownController c) => c.complete()),
    ]) {
      test('$name closes an idle stream at once', () async {
        var cancelled = false;
        final body = StreamController<List<int>>(
          onCancel: () => cancelled = true,
        );
        final c = StreamingMarkdownController();
        final done = c.addOpenAIStream(body.stream);
        body.add(
          utf8.encode(
            _sse([
              {
                'choices': [
                  {
                    'delta': {'content': 'Hi'},
                  },
                ],
              },
            ]),
          ),
        );
        await pumpEventQueue();
        expect(c.text, 'Hi');
        // the server is quiet now; ending the reply must not wait for it
        end(c);
        await done.timeout(const Duration(seconds: 1));
        expect(cancelled, isTrue);
        expect(c.error, isNull);
        // nothing more is listened to, and a new reply starts clean
        expect(body.hasListener, isFalse);
      });
    }

    test('a new reply after reset is not touched by the old stream', () async {
      final old = StreamController<List<int>>();
      final c = StreamingMarkdownController();
      final first = c.addAnthropicStream(old.stream);
      c.reset();
      await first;
      final second = c.addOllamaStream(
        _body('${jsonEncode({'response': 'New', 'done': true})}\n'),
      );
      await second;
      expect(c.text, 'New');
      expect(c.isComplete, isTrue);
      expect(old.hasListener, isFalse);
    });

    test('an error from the connection still ends the reply', () async {
      final body = StreamController<List<int>>();
      final c = StreamingMarkdownController();
      final done = c.addGeminiStream(body.stream);
      body.addError(const FormatException('socket closed'));
      await expectLater(done, throwsA(isA<FormatException>()));
      expect(c.error, isA<FormatException>());
      expect(c.isComplete, isTrue);
    });
  });

  group('widget', () {
    testWidgets('tool calls show above the answer, then turn done', (
      tester,
    ) async {
      final c = StreamingMarkdownController()
        ..appendThinking('Let me look.')
        ..startToolCall('1', 'web_search');
      await tester.pumpWidget(
        _host(
          StreamingMarkdown(controller: c, smoothing: const Smoothing.none()),
        ),
      );
      await tester.pump();
      expect(find.text('Using web search…'), findsOneWidget);
      final line = tester.getTopLeft(find.text('Using web search…')).dy;
      c
        ..finishToolCall('1')
        ..append('It is **sunny**.')
        ..complete();
      await tester.pumpAndSettle();
      expect(find.text('Used web search'), findsOneWidget);
      expect(find.text('Using web search…'), findsNothing);
      // the line stays above the answer
      expect(
        tester.getTopLeft(find.textContaining('sunny', findRichText: true)).dy,
        greaterThan(line),
      );

      await tester.pumpWidget(
        _host(
          StreamingMarkdown(
            controller: c,
            smoothing: const Smoothing.none(),
            labels: MarkdownLabels(
              toolCall: (name, done) => done ? 'Fertig: $name' : '…',
            ),
          ),
        ),
      );
      expect(find.text('Fertig: web_search'), findsOneWidget);

      await tester.pumpWidget(
        _host(
          StreamingMarkdown(
            controller: c,
            smoothing: const Smoothing.none(),
            toolCallBuilder: (context, call) => Text('[${call.name}]'),
          ),
        ),
      );
      expect(find.text('[web_search]'), findsOneWidget);

      await tester.pumpWidget(
        _host(
          StreamingMarkdown(
            controller: c,
            smoothing: const Smoothing.none(),
            showToolCalls: false,
          ),
        ),
      );
      expect(find.text('Used web search'), findsNothing);
    });
  });
}
