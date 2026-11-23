import 'dart:async';
import 'dart:convert';

import 'package:llm_client/llm_client.dart';
import 'package:server_sent_events/testing.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// A provider that plays back [events], then fails with [error] if set.
class ScriptedProvider extends LlmProvider {
  ScriptedProvider(this.events, {this.error});

  final List<LlmEvent> events;
  final Object? error;
  final requests = <LlmRequest>[];
  var cancels = 0;

  @override
  Stream<LlmEvent> stream(LlmRequest request) {
    requests.add(request);
    late final StreamController<LlmEvent> out;
    out = StreamController(
      onListen: () {
        events.forEach(out.add);
        if (error != null) out.addError(error!);
        if (error != null || events.lastOrNull is LlmDone) out.close();
      },
      onCancel: () => cancels++,
    );
    return out.stream;
  }
}

const call = LlmToolCall(
  id: 'call_1',
  name: 'get_weather',
  arguments: {'city': 'Paris'},
);

void main() {
  group('text()', () {
    test('gives the text deltas only', () async {
      final provider = ScriptedProvider(const [
        LlmThinkingDelta('Hm.'),
        LlmTextDelta('Hel'),
        LlmToolCallStart('call_1', 'get_weather'),
        LlmToolCallDelta('call_1', {}, '{}'),
        LlmToolCallDone(call),
        LlmTextDelta('lo'),
        LlmUsage(inputTokens: 1, outputTokens: 2),
        LlmDone(LlmFinishReason.stop),
      ]);
      expect(await provider.text(plainRequest).toList(), ['Hel', 'lo']);
      expect(provider.requests.single, same(plainRequest));
    });

    test('passes errors on', () {
      final provider = ScriptedProvider(const [
        LlmTextDelta('Hi'),
      ], error: const LlmException('Overloaded'));
      expect(
        provider.text(plainRequest),
        emitsInOrder(['Hi', emitsError(isA<LlmException>()), emitsDone]),
      );
    });

    test('cancel reaches the provider', () async {
      final provider = ScriptedProvider(const [LlmTextDelta('Hi')]);
      final first = Completer<String>();
      final subscription = provider.text(plainRequest).listen(first.complete);
      expect(await first.future, 'Hi');
      await subscription.cancel();
      expect(provider.cancels, 1);
    });

    test('over a real provider', () async {
      final fake = sseFake([
        {
          'choices': [
            {
              'delta': {'content': 'Hi'},
            },
          ],
        },
        {
          'choices': [
            {
              'delta': {'content': '!'},
              'finish_reason': 'stop',
            },
          ],
        },
        '[DONE]',
      ]);
      expect(
        await OpenAIProvider(
          apiKey: 'k',
          client: fake,
        ).text(plainRequest).join(),
        'Hi!',
      );
    });
  });

  group('complete()', () {
    test('collects text, thinking, tool calls, usage and the reason', () async {
      final provider = ScriptedProvider(const [
        LlmThinkingDelta('Let me '),
        LlmThinkingDelta('see.'),
        LlmTextDelta('Check'),
        LlmTextDelta('ing.'),
        LlmToolCallStart('call_1', 'get_weather'),
        LlmToolCallDelta('call_1', {'city': 'Par'}, '{"city": "Par'),
        LlmToolCallDone(call),
        LlmToolCallDone(LlmToolCall(id: 'call_2', name: 'get_time')),
        LlmUsage(inputTokens: 20, outputTokens: 9),
        LlmDone(LlmFinishReason.toolCalls, rawFinishReason: 'tool_calls'),
      ]);
      final response = await provider.complete(toolRequest);
      expect(response.text, 'Checking.');
      expect(response.thinking, 'Let me see.');
      expect(response.toolCalls.map((c) => c.id), ['call_1', 'call_2']);
      expect(response.toolCalls.first.name, 'get_weather');
      expect(response.toolCalls.first.arguments, {'city': 'Paris'});
      expect(response.usage!.inputTokens, 20);
      expect(response.usage!.outputTokens, 9);
      expect(response.finishReason, LlmFinishReason.toolCalls);
      expect(response.rawFinishReason, 'tool_calls');

      final message = response.message;
      expect(message.role, LlmRole.assistant);
      expect(message.text, 'Checking.');
      expect(message.toolCalls, response.toolCalls);
    });

    test('a reply without usage', () async {
      final response = await ScriptedProvider(const [
        LlmTextDelta('Hi'),
        LlmDone(LlmFinishReason.length),
      ]).complete(plainRequest);
      expect(response.text, 'Hi');
      expect(response.thinking, '');
      expect(response.toolCalls, isEmpty);
      expect(response.usage, isNull);
      expect(response.finishReason, LlmFinishReason.length);
    });

    test('throws the stream\'s error', () {
      final provider = ScriptedProvider(const [
        LlmTextDelta('Hi'),
      ], error: const LlmException('Overloaded', statusCode: 529));
      expect(
        provider.complete(plainRequest),
        throwsA(
          isA<LlmException>().having((e) => e.statusCode, 'statusCode', 529),
        ),
      );
    });

    test('a whole tool round trip over a real provider', () async {
      final bodies = <Map<String, Object?>>[];
      final replies = [
        [
          {
            'type': 'content_block_start',
            'index': 0,
            'content_block': {
              'type': 'tool_use',
              'id': 'toolu_1',
              'name': 'get_weather',
              'input': {},
            },
          },
          {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {
              'type': 'input_json_delta',
              'partial_json': '{"city": "Paris"}',
            },
          },
          {'type': 'content_block_stop', 'index': 0},
          {
            'type': 'message_delta',
            'delta': {'stop_reason': 'tool_use'},
            'usage': {'output_tokens': 12},
          },
          {'type': 'message_stop'},
        ],
        [
          {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'text_delta', 'text': '21 degrees.'},
          },
          {
            'type': 'message_delta',
            'delta': {'stop_reason': 'end_turn'},
          },
          {'type': 'message_stop'},
        ],
      ];
      var turn = 0;
      final fake = FakeSseClient(
        (_) => FakeSseResponse.raw([
          for (final event in replies[turn++])
            'event: ${event['type']}\ndata: ${jsonEncode(event)}\n\n',
        ]),
      );
      final provider = AnthropicProvider(apiKey: 'k', client: fake);

      final messages = [const LlmMessage.user('Weather in Paris?')];
      final first = await provider.complete(
        LlmRequest(model: 'm', messages: messages, tools: const [weatherTool]),
      );
      expect(first.finishReason, LlmFinishReason.toolCalls);
      expect(first.usage!.inputTokens, isNull);
      expect(first.usage!.outputTokens, 12);
      messages.add(first.message);
      for (final call in first.toolCalls) {
        messages.add(
          LlmMessage.tool(
            toolCallId: call.id,
            text: '21 in ${call.arguments['city']}',
          ),
        );
      }
      final second = await provider.complete(
        LlmRequest(model: 'm', messages: messages, tools: const [weatherTool]),
      );
      expect(second.text, '21 degrees.');
      expect(second.finishReason, LlmFinishReason.stop);

      bodies.addAll(
        fake.bodies.map((b) => jsonDecode(b) as Map<String, Object?>),
      );
      expect(bodies[1]['messages'], [
        {'role': 'user', 'content': 'Weather in Paris?'},
        {
          'role': 'assistant',
          'content': [
            {
              'type': 'tool_use',
              'id': 'toolu_1',
              'name': 'get_weather',
              'input': {'city': 'Paris'},
            },
          ],
        },
        {
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': 'toolu_1',
              'content': '21 in Paris',
            },
          ],
        },
      ]);
    });
  });

  group('types', () {
    test('LlmException shows the status and message', () {
      expect(
        '${const LlmException('Bad key', statusCode: 401, body: '{}')}',
        'LlmException (401): Bad key',
      );
      expect('${const LlmException('Overloaded')}', 'LlmException: Overloaded');
    });

    test('LlmMessage constructors', () {
      const tool = LlmMessage.tool(toolCallId: 'c', text: 'r', toolName: 'f');
      expect(tool.role, LlmRole.tool);
      expect(tool.toolCallId, 'c');
      expect(tool.toolName, 'f');
      expect(const LlmMessage.system('s').role, LlmRole.system);
      expect(const LlmMessage.user('u').role, LlmRole.user);
      expect(const LlmMessage.assistant('a').toolCalls, isEmpty);
    });
  });
}
