import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown_chat/llm_markdown_chat.dart';
import 'package:server_sent_events/server_sent_events.dart';

Widget _app(Widget child) => WidgetsApp(
  color: const Color(0xFF2196F3),
  builder: (context, _) => DefaultTextStyle(
    style: const TextStyle(fontSize: 14, color: Color(0xFF000000)),
    child: child,
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder _button(String label) => find.bySemanticsLabel(label);

// the blinking cursor of a reply that is still arriving
final _cursor = find.byWidgetPredicate(
  (widget) => '${widget.runtimeType}' == 'StreamingCursor',
);

// `isSelected` is a bool in older Flutter versions and a Tristate in newer
// ones; both print "true" when set.
bool _selected(WidgetTester tester, Finder finder) =>
    '${tester.getSemantics(finder).flagsCollection.isSelected}'
        .toLowerCase()
        .contains('true');

String _input(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText)).controller.text;

void main() {
  late List<String> prompts;
  late LlmChatController chat;

  setUp(() {
    prompts = [];
    chat = LlmChatController(
      history: [
        ChatMessage.user('First'),
        ChatMessage.assistant('Reply **one**'),
        ChatMessage.user('Second'),
        ChatMessage.assistant('Reply two'),
      ],
      onReply: (prompt, reply, history) async {
        prompts.add(prompt);
        reply.append('Answer ${prompts.length} to $prompt');
      },
    );
  });
  tearDown(() => chat.dispose());

  group('message actions', () {
    testWidgets('regenerate replaces the last reply', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(LlmChatView(controller: chat)));
      // every reply can be copied, only the last one asked again
      expect(_button('Copy'), findsNWidgets(2));
      expect(_button('Try again'), findsOneWidget);
      await tester.tap(_button('Try again'));
      await _settle(tester);
      expect(prompts, ['Second']);
      expect(chat.messages.length, 4);
      expect(
        find.textContaining('Reply two', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('Answer 1 to Second', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Second'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('feedback buttons call onFeedback and mark the choice', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final feedback = <(String, bool)>[];
      await tester.pumpWidget(_app(LlmChatView(controller: chat)));
      // not shown without the callback
      expect(_button('Good reply'), findsNothing);
      await tester.pumpWidget(
        _app(
          LlmChatView(
            controller: chat,
            onFeedback: (message, isPositive) =>
                feedback.add((message.text, isPositive)),
          ),
        ),
      );
      expect(_button('Good reply'), findsNWidgets(2));
      expect(_button('Bad reply'), findsNWidgets(2));
      // the list is drawn newest first
      await tester.tap(_button('Good reply').first);
      await tester.pump();
      expect(feedback, [('Reply two', true)]);
      expect(_selected(tester, _button('Good reply').first), isTrue);
      expect(_selected(tester, _button('Bad reply').first), isFalse);
      await tester.tap(_button('Bad reply').last);
      await tester.pump();
      expect(feedback.last, ('Reply **one**', false));
      expect(_selected(tester, _button('Bad reply').last), isTrue);
      semantics.dispose();
    });

    testWidgets('each action can be turned off', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(LlmChatView(controller: chat, showCopy: false)),
      );
      expect(_button('Copy'), findsNothing);
      expect(_button('Try again'), findsOneWidget);
      expect(_button('Edit'), findsNWidgets(2));
      await tester.pumpWidget(
        _app(LlmChatView(controller: chat, showRegenerate: false)),
      );
      expect(_button('Copy'), findsNWidgets(2));
      expect(_button('Try again'), findsNothing);
      await tester.pumpWidget(
        _app(LlmChatView(controller: chat, showEdit: false)),
      );
      expect(_button('Edit'), findsNothing);
      semantics.dispose();
    });

    testWidgets('copyPlainText copies without the Markdown marks', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      await tester.pumpWidget(
        _app(LlmChatView(controller: chat, copyPlainText: true)),
      );
      await tester.tap(_button('Copy').last);
      await tester.pump();
      expect(copied.single.trim(), 'Reply one');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(_app(LlmChatView(controller: chat)));
      await tester.tap(_button('Copy').last);
      await tester.pump();
      expect(copied.last, 'Reply **one**');
      await tester.pump(const Duration(seconds: 3));
      semantics.dispose();
    });

    testWidgets('messageActionsBuilder replaces the buttons', (tester) async {
      final semantics = tester.ensureSemantics();
      final gate = Completer<void>();
      final slow = LlmChatController(
        history: [ChatMessage.user('Q'), ChatMessage.assistant('Done')],
        onReply: (prompt, reply, history) => gate.future,
      );
      addTearDown(slow.dispose);
      await tester.pumpWidget(
        _app(
          LlmChatView(
            controller: slow,
            onFeedback: (message, isPositive) {},
            messageActionsBuilder: (context, message) =>
                Text('actions for ${message.text}'),
          ),
        ),
      );
      expect(find.text('actions for Done'), findsOneWidget);
      expect(_button('Copy'), findsNothing);
      expect(_button('Try again'), findsNothing);
      expect(_button('Good reply'), findsNothing);
      // only under finished replies
      unawaited(slow.send('More'));
      await tester.pump();
      expect(find.textContaining('actions for'), findsOneWidget);
      gate.complete();
      await _settle(tester);
      expect(find.textContaining('actions for'), findsNWidgets(2));
      semantics.dispose();
    });
  });

  group('edit', () {
    testWidgets('puts the text in the input; sending truncates the chat', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(LlmChatView(controller: chat)));
      expect(find.text('Editing message'), findsNothing);
      // the first user message: the list is drawn newest first
      await tester.tap(_button('Edit').last);
      await tester.pump();
      expect(_input(tester), 'First');
      expect(find.text('Editing message'), findsOneWidget);
      // nothing changed yet
      expect(chat.messages.length, 4);

      await tester.enterText(find.byType(EditableText), 'First, better');
      await tester.pump();
      await tester.tap(_button('Send'));
      await _settle(tester);
      expect(prompts, ['First, better']);
      expect(
        [for (final m in chat.messages) m.text],
        ['First, better', 'Answer 1 to First, better'],
      );
      expect(find.text('Second'), findsNothing);
      expect(
        find.textContaining('Reply two', findRichText: true),
        findsNothing,
      );
      expect(find.text('Editing message'), findsNothing);
      expect(_input(tester), isEmpty);

      // the next message is a normal one
      await tester.enterText(find.byType(EditableText), 'Next');
      await tester.pump();
      await tester.tap(_button('Send'));
      await _settle(tester);
      expect(chat.messages.length, 4);
      expect(chat.messages[2].text, 'Next');
      semantics.dispose();
    });

    testWidgets('cancel leaves the chat as it was', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(LlmChatView(controller: chat)));
      await tester.tap(_button('Edit').first);
      await tester.pump();
      expect(_input(tester), 'Second');
      await tester.tap(_button('Cancel'));
      await tester.pump();
      expect(_input(tester), isEmpty);
      expect(find.text('Editing message'), findsNothing);
      await tester.enterText(find.byType(EditableText), 'Third');
      await tester.pump();
      await tester.tap(_button('Send'));
      await _settle(tester);
      expect(chat.messages.length, 6);
      expect(chat.messages[4].text, 'Third');
      semantics.dispose();
    });

    testWidgets('no edit button while a reply is written; a cleared chat '
        'ends the edit', (tester) async {
      final semantics = tester.ensureSemantics();
      final gate = Completer<void>();
      final slow = LlmChatController(
        history: [ChatMessage.user('Q'), ChatMessage.assistant('A')],
        onReply: (prompt, reply, history) => gate.future,
      );
      addTearDown(slow.dispose);
      await tester.pumpWidget(_app(LlmChatView(controller: slow)));
      await tester.tap(_button('Edit'));
      await tester.pump();
      expect(find.text('Editing message'), findsOneWidget);
      slow.clear();
      await tester.pump();
      expect(find.text('Editing message'), findsNothing);
      await tester.tap(_button('Send'));
      await tester.pump();
      expect(slow.messages.first.text, 'Q');
      expect(slow.isReplying, isTrue);
      expect(_button('Edit'), findsNothing);
      gate.complete();
      await _settle(tester);
      expect(_button('Edit'), findsOneWidget);
      semantics.dispose();
    });
  });

  group('restored chat', () {
    testWidgets('replies show complete at once, without a cursor', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final source = StreamController<String>();
      final live = LlmChatController(
        onReply: (prompt, reply, history) => reply.addStream(source.stream),
      );
      addTearDown(live.dispose);
      await tester.pumpWidget(_app(LlmChatView(controller: live)));
      await tester.enterText(find.byType(EditableText), 'Question');
      await tester.pump();
      await tester.tap(_button('Send'));
      await tester.pump();
      source.add('The **answer** is 42');
      await tester.pump(const Duration(milliseconds: 20));
      // a reply that is still arriving has the cursor
      expect(_cursor, findsOneWidget);
      await source.close();
      await _settle(tester);
      expect(_cursor, findsNothing);

      final saved = jsonEncode(live.toJson());
      final restored = LlmChatController.fromJson(
        jsonDecode(saved) as Map<String, Object?>,
        onReply: (prompt, reply, history) async {},
      );
      addTearDown(restored.dispose);
      await tester.pumpWidget(
        _app(
          LlmChatView(key: const ValueKey('restored'), controller: restored),
        ),
      );
      // on the first frame: the whole text, no cursor, the buttons
      expect(
        find.textContaining('The answer is 42', findRichText: true),
        findsOneWidget,
      );
      expect(_cursor, findsNothing);
      expect(find.text('Question'), findsOneWidget);
      expect(_button('Copy'), findsOneWidget);
      expect(_button('Stop'), findsNothing);
      await _settle(tester);
      expect(_cursor, findsNothing);
      semantics.dispose();
    });
  });

  group('welcome and suggestions', () {
    testWidgets('are shown while the chat is empty; a tap sends', (
      tester,
    ) async {
      final empty = LlmChatController(
        onReply: (prompt, reply, history) async {
          prompts.add(prompt);
          reply.append('ok');
        },
      );
      addTearDown(empty.dispose);
      await tester.pumpWidget(
        _app(
          LlmChatView(
            controller: empty,
            welcome: const Text('Welcome!'),
            suggestions: const ['Tell a joke', 'Plan a trip'],
          ),
        ),
      );
      expect(find.text('Welcome!'), findsOneWidget);
      expect(find.text('Tell a joke'), findsOneWidget);
      await tester.tap(find.text('Tell a joke'));
      await _settle(tester);
      expect(prompts, ['Tell a joke']);
      expect(empty.messages.first.text, 'Tell a joke');
      expect(find.text('Welcome!'), findsNothing);
      expect(find.text('Plan a trip'), findsNothing);
      // back when the chat is emptied
      empty.clear();
      await tester.pump();
      expect(find.text('Welcome!'), findsOneWidget);
    });

    testWidgets('emptyBuilder is used instead of welcome', (tester) async {
      final empty = LlmChatController(
        onReply: (prompt, reply, history) async {},
      );
      addTearDown(empty.dispose);
      await tester.pumpWidget(
        _app(
          LlmChatView(
            controller: empty,
            welcome: const Text('Welcome!'),
            emptyBuilder: (context) => const Text('Built'),
          ),
        ),
      );
      expect(find.text('Built'), findsOneWidget);
      expect(find.text('Welcome!'), findsNothing);
    });
  });

  group('attachments', () {
    const photo = ChatAttachment(name: 'photo.png', mimeType: 'image/png');
    const notes = ChatAttachment(name: 'notes.txt', uri: '/tmp/notes.txt');

    testWidgets('picked ones are listed, can be removed, and are sent', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(LlmChatView(controller: chat)));
      expect(_button('Attach'), findsNothing);
      await tester.pumpWidget(
        _app(
          LlmChatView(
            controller: chat,
            onPickAttachment: () async => const [photo, notes],
          ),
        ),
      );
      await tester.tap(_button('Attach'));
      await tester.pump();
      await tester.pump();
      expect(find.text('photo.png'), findsOneWidget);
      expect(find.text('notes.txt'), findsOneWidget);

      await tester.tap(_button('Remove notes.txt'));
      await tester.pump();
      expect(find.text('notes.txt'), findsNothing);
      expect(find.text('photo.png'), findsOneWidget);

      // attachments alone can be sent
      await tester.tap(_button('Send'));
      await _settle(tester);
      final sent = chat.messages[4];
      expect(sent.role, ChatRole.user);
      expect(sent.attachments, [photo]);
      expect(sent.text, '');
      // shown in the message, gone from the input
      expect(find.text('photo.png'), findsOneWidget);
      expect(_button('Remove photo.png'), findsNothing);

      // with text, and picking twice adds up
      await tester.tap(_button('Attach'));
      await tester.pump();
      await tester.pump();
      await tester.tap(_button('Remove photo.png'));
      await tester.pump();
      await tester.tap(_button('Attach'));
      await tester.pump();
      await tester.pump();
      expect(_button('Remove notes.txt'), findsNWidgets(2));
      await tester.enterText(find.byType(EditableText), 'Look at these');
      await tester.pump();
      await tester.tap(_button('Send'));
      await _settle(tester);
      expect(chat.messages[6].text, 'Look at these');
      expect(chat.messages[6].attachments, [notes, photo, notes]);
      semantics.dispose();
    });

    testWidgets('attachmentBuilder draws them, and an edit brings them back', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final withFile = LlmChatController(
        history: [
          ChatMessage.user('See this', attachments: const [photo]),
          ChatMessage.assistant('Nice'),
        ],
        onReply: (prompt, reply, history) async => reply.append('Again'),
      );
      addTearDown(withFile.dispose);
      await tester.pumpWidget(
        _app(
          LlmChatView(
            controller: withFile,
            attachmentBuilder: (context, attachment) =>
                Text('file:${attachment.name}'),
          ),
        ),
      );
      expect(find.text('file:photo.png'), findsOneWidget);
      expect(find.text('See this'), findsOneWidget);

      await tester.tap(_button('Edit'));
      await tester.pump();
      expect(_button('Remove photo.png'), findsOneWidget);
      await tester.enterText(find.byType(EditableText), 'See this again');
      await tester.pump();
      await tester.tap(_button('Send'));
      await _settle(tester);
      expect(withFile.messages.length, 2);
      expect(withFile.messages.first.text, 'See this again');
      expect(withFile.messages.first.attachments, [photo]);
      semantics.dispose();
    });

    testWidgets('a failing picker is reported and the chat goes on', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var calls = 0;
      await tester.pumpWidget(
        _app(
          LlmChatView(
            controller: chat,
            onPickAttachment: () async {
              calls++;
              throw StateError('no access');
            },
          ),
        ),
      );
      await tester.tap(_button('Attach'));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isStateError);
      // the button works again
      await tester.tap(_button('Attach'));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isStateError);
      expect(calls, 2);
      semantics.dispose();
    });
  });

  group('voice input', () {
    testWidgets('puts the heard text in the input', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(LlmChatView(controller: chat)));
      expect(_button('Voice input'), findsNothing);
      String? heard = 'hello world';
      await tester.pumpWidget(
        _app(LlmChatView(controller: chat, onVoiceInput: () async => heard)),
      );
      await tester.tap(_button('Voice input'));
      await tester.pump();
      await tester.pump();
      expect(_input(tester), 'hello world');
      // nothing was sent
      expect(prompts, isEmpty);

      // added after what is there; nothing heard changes nothing
      heard = ' again ';
      await tester.tap(_button('Voice input'));
      await tester.pump();
      await tester.pump();
      expect(_input(tester), 'hello world again');
      heard = null;
      await tester.tap(_button('Voice input'));
      await tester.pump();
      await tester.pump();
      expect(_input(tester), 'hello world again');

      await tester.tap(_button('Send'));
      await _settle(tester);
      expect(prompts, ['hello world again']);
      semantics.dispose();
    });

    testWidgets('the button is off while listening', (tester) async {
      final semantics = tester.ensureSemantics();
      final gate = Completer<String?>();
      var calls = 0;
      await tester.pumpWidget(
        _app(
          LlmChatView(
            controller: chat,
            onVoiceInput: () {
              calls++;
              return gate.future;
            },
          ),
        ),
      );
      await tester.tap(_button('Voice input'));
      await tester.pump();
      await tester.tap(_button('Voice input'), warnIfMissed: false);
      await tester.pump();
      expect(calls, 1);
      gate.complete('done');
      await tester.pump();
      await tester.pump();
      expect(_input(tester), 'done');
      semantics.dispose();
    });
  });

  group('errors', () {
    testWidgets('the message of an API error is shown under the reply', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final failing = LlmChatController(
        onReply: (prompt, reply, history) async {
          reply.append('Half an answer');
          throw const SseException(
            'HTTP 429',
            statusCode: 429,
            body: '{"error": {"message": "Rate limit reached"}}',
          );
        },
      );
      addTearDown(failing.dispose);
      await tester.pumpWidget(
        _app(LlmChatView(controller: failing, onFeedback: (m, p) {})),
      );
      await tester.enterText(find.byType(EditableText), 'Hi');
      await tester.pump();
      await tester.tap(_button('Send'));
      await _settle(tester);
      expect(find.text('Rate limit reached'), findsOneWidget);
      expect(
        find.textContaining('Half an answer', findRichText: true),
        findsOneWidget,
      );
      expect(_button('Try again'), findsOneWidget);
      // a failed reply is not rated
      expect(_button('Good reply'), findsNothing);

      await tester.pumpWidget(
        _app(
          LlmChatView(
            controller: failing,
            errorBuilder: (context, message) =>
                Text('Failed: ${message.reply!.error.runtimeType}'),
          ),
        ),
      );
      expect(find.text('Failed: SseException'), findsOneWidget);
      expect(find.text('Rate limit reached'), findsNothing);

      // a replyBuilder may show the error itself
      await tester.pumpWidget(
        _app(
          LlmChatView(
            controller: failing,
            replyBuilder: (context, message) =>
                StreamingMarkdown(controller: message.reply!),
          ),
        ),
      );
      expect(find.text('Rate limit reached'), findsNothing);
      semantics.dispose();
    });
  });
}
