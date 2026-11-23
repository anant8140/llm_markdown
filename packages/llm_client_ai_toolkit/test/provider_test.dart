import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_client/llm_client.dart' as llm;
import 'package:llm_client_ai_toolkit/llm_client_ai_toolkit.dart';
import 'package:material_ui/material_ui.dart';
import 'package:server_sent_events/server_sent_events.dart';
import 'package:server_sent_events/testing.dart';

SseEvent delta(String text) => SseEvent(
  jsonEncode({
    'choices': [
      {
        'index': 0,
        'delta': {'content': text},
        'finish_reason': null,
      },
    ],
  }),
);

final stop = SseEvent(
  jsonEncode({
    'choices': [
      {'index': 0, 'delta': <String, Object?>{}, 'finish_reason': 'stop'},
    ],
  }),
);

FakeSseResponse reply(List<String> pieces, {bool keepOpen = false}) =>
    FakeSseResponse.events([
      for (final piece in pieces) delta(piece),
      if (!keepOpen) ...[stop, const SseEvent('[DONE]')],
    ], keepOpen: keepOpen);

LlmClientProvider provider(
  FakeSseClient fake, {
  String? system,
  bool fail = false,
  List<Attachment>? left,
}) => LlmClientProvider(
  client: llm.OpenAIProvider(apiKey: 'k', client: fake),
  model: 'm',
  system: system,
  failOnUnsupportedAttachment: fail,
  onUnsupportedAttachment: left?.add,
);

List<Object?> messages(String body) =>
    (jsonDecode(body) as Map)['messages'] as List;

void main() {
  test(
    'sendMessageStream streams text, keeps the history and sends it',
    () async {
      final fake = FakeSseClient((_) => reply(['Hel', 'lo']));
      final chat = provider(fake, system: 'Be brief.');
      var notified = 0;
      chat.addListener(() => notified++);

      expect(await chat.sendMessageStream('Hi').toList(), ['Hel', 'lo']);
      expect(chat.history.map((m) => '${m.origin.name}:${m.text}'), [
        'user:Hi',
        'llm:Hello',
      ]);
      expect(notified, greaterThanOrEqualTo(1));
      expect(messages(fake.bodies[0]), [
        {'role': 'system', 'content': 'Be brief.'},
        {'role': 'user', 'content': 'Hi'},
      ]);

      await chat.sendMessageStream('More').drain<void>();
      expect(messages(fake.bodies[1]), [
        {'role': 'system', 'content': 'Be brief.'},
        {'role': 'user', 'content': 'Hi'},
        {'role': 'assistant', 'content': 'Hello'},
        {'role': 'user', 'content': 'More'},
      ]);
      expect(chat.history, hasLength(4));
    },
  );

  test('generateStream sends no history and keeps none', () async {
    final fake = FakeSseClient((_) => reply(['x']));
    final chat = provider(fake);
    await chat.sendMessageStream('one').drain<void>();
    expect(await chat.generateStream('two').toList(), ['x']);
    expect(messages(fake.bodies[1]), [
      {'role': 'user', 'content': 'two'},
    ]);
    expect(chat.history, hasLength(2));
  });

  test('an API error becomes the toolkit\'s LlmFailureException', () async {
    final fake = FakeSseClient(
      (_) =>
          FakeSseResponse.error(401, '{"error":{"message":"Invalid API key"}}'),
    );
    await expectLater(
      provider(fake).sendMessageStream('Hi').toList(),
      throwsA(
        isA<LlmFailureException>().having(
          (e) => e.message,
          'message',
          contains('Invalid API key'),
        ),
      ),
    );
  });

  test('cancelling the reply aborts the request and keeps what came', () async {
    final fake = FakeSseClient((_) => reply(['partial'], keepOpen: true));
    final chat = provider(fake);
    expect(await chat.sendMessageStream('Hi').first, 'partial');
    await Future<void>.delayed(Duration.zero);
    expect(fake.aborted, 1);
    expect(chat.history.last.text, 'partial');
  });

  test('links go into the prompt; files are left out and reported', () async {
    final fake = FakeSseClient((_) => reply(['ok']));
    final left = <Attachment>[];
    final chat = provider(fake, left: left);
    final file = FileAttachment(
      name: 'notes.txt',
      mimeType: 'text/plain',
      bytes: Uint8List.fromList([1, 2]),
    );
    await chat
        .sendMessageStream(
          'Read this',
          attachments: [
            LinkAttachment(name: 'page', url: Uri.parse('https://dart.dev')),
            file,
          ],
        )
        .drain<void>();
    expect(messages(fake.bodies.single), [
      {'role': 'user', 'content': 'Read this\n\nhttps://dart.dev'},
    ]);
    expect(left, [file]);

    await expectLater(
      provider(
        fake,
        fail: true,
      ).sendMessageStream('x', attachments: [file]).toList(),
      throwsA(isA<LlmFailureException>()),
    );
  });

  test('setting the history replaces it and notifies', () {
    final chat = provider(FakeSseClient((_) => reply(['x'])));
    var notified = 0;
    chat.addListener(() => notified++);
    chat.history = [ChatMessage.user('old', const [])];
    expect(chat.history.single.text, 'old');
    expect(notified, 1);
  });

  testWidgets('LlmChatView shows a reply from the provider', (tester) async {
    final fake = FakeSseClient((_) => reply(['Hello ', 'there']));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LlmChatView(
            provider: provider(fake),
            enableAttachments: false,
            enableVoiceNotes: false,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(EditableText), 'Hi');
    await tester.pump();
    await tester.tap(
      find.byWidgetPredicate((w) => w.runtimeType.toString() == 'InputButton'),
    );
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      find.textContaining('Hello there', findRichText: true),
      findsWidgets,
    );
    expect(fake.requests, hasLength(1));
  });
}
