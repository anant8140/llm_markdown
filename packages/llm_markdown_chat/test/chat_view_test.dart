import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown_chat/llm_markdown_chat.dart';

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

void main() {
  late StreamController<String> source;
  late List<String> prompts;
  late LlmChatController chat;

  setUp(() {
    source = StreamController<String>();
    prompts = [];
    chat = LlmChatController(
      onReply: (prompt, reply, history) {
        prompts.add(prompt);
        return reply.addStream(source.stream);
      },
    );
  });
  tearDown(() => chat.dispose());

  testWidgets('type, send, stream the reply, copy it', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(LlmChatView(controller: chat)));
    expect(find.text('Message'), findsOneWidget);

    // the send button does nothing while the box is empty
    await tester.tap(_button('Send'));
    await tester.pump();
    expect(prompts, isEmpty);

    await tester.enterText(find.byType(EditableText), 'Explain **this**');
    await tester.pump();
    expect(find.text('Message'), findsNothing);
    await tester.tap(_button('Send'));
    await tester.pump();
    expect(prompts, ['Explain **this**']);
    // the user's text is shown as written, the box is empty again
    expect(find.text('Explain **this**'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
    // while replying the button stops
    expect(_button('Stop'), findsOneWidget);

    source.add('# Answer\n\nIt is **bold**.');
    await _settle(tester);
    expect(
      find.textContaining('It is bold.', findRichText: true),
      findsOneWidget,
    );
    expect(_button('Copy'), findsNothing);
    await source.close();
    await _settle(tester);
    expect(_button('Send'), findsOneWidget);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    await tester.tap(_button('Copy'));
    await tester.pump();
    expect(copied, '# Answer\n\nIt is **bold**.');
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Copy'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('stop keeps the text and offers to try again', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(LlmChatView(controller: chat)));
    await tester.enterText(find.byType(EditableText), 'Q');
    await tester.pump();
    await tester.tap(_button('Send'));
    await tester.pump();
    source.add('Half');
    await _settle(tester);
    await tester.tap(_button('Stop'));
    await _settle(tester);
    expect(chat.isReplying, isFalse);
    expect(source.hasListener, isFalse);
    expect(find.textContaining('Half', findRichText: true), findsOneWidget);
    expect(_button('Try again'), findsOneWidget);

    source = StreamController<String>();
    await tester.tap(_button('Try again'));
    await tester.pump();
    expect(prompts, ['Q', 'Q']);
    expect(find.text('Q'), findsOneWidget);
    source.add('Whole');
    await source.close();
    await _settle(tester);
    expect(find.textContaining('Whole', findRichText: true), findsOneWidget);
    expect(find.textContaining('Half', findRichText: true), findsNothing);
    semantics.dispose();
  });

  testWidgets('Enter sends and Shift+Enter makes a new line', (tester) async {
    await tester.pumpWidget(
      _app(LlmChatView(controller: chat, autofocus: true)),
    );
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'Line one');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(prompts, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(prompts, ['Line one']);
  });

  testWidgets('suggestions are shown while empty and send on tap', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        LlmChatView(
          controller: chat,
          emptyBuilder: (context) => const Text('How can I help?'),
          suggestions: const ['Write a poem', 'Plan a trip'],
        ),
      ),
    );
    expect(find.text('How can I help?'), findsOneWidget);
    await tester.tap(find.text('Plan a trip'));
    await tester.pump();
    expect(prompts, ['Plan a trip']);
    expect(find.text('How can I help?'), findsNothing);
    expect(find.text('Write a poem'), findsNothing);
  });

  testWidgets('history, custom builders and labels', (tester) async {
    final history = LlmChatController(
      history: [ChatMessage.user('Old Q'), ChatMessage.assistant('Old *A*')],
      onReply: (prompt, reply, history) async {},
    );
    addTearDown(history.dispose);
    await tester.pumpWidget(
      _app(
        LlmChatView(
          controller: history,
          labels: const LlmChatLabels(hint: 'Ask anything'),
          userMessageBuilder: (context, message) =>
              Text('You: ${message.text}'),
          replyBuilder: (context, message) =>
              StreamingMarkdown(controller: message.reply!, showCursor: false),
        ),
      ),
    );
    expect(find.text('You: Old Q'), findsOneWidget);
    expect(find.textContaining('Old A', findRichText: true), findsOneWidget);
    expect(find.text('Ask anything'), findsOneWidget);
  });

  testWidgets('a long chat keeps the newest message in view', (tester) async {
    final long = LlmChatController(
      history: [
        for (var i = 0; i < 40; i++) ...[
          ChatMessage.user('Question $i'),
          ChatMessage.assistant('Answer $i'),
        ],
      ],
      onReply: (prompt, reply, history) async {},
    );
    addTearDown(long.dispose);
    await tester.pumpWidget(_app(LlmChatView(controller: long)));
    await tester.pump();
    expect(
      find.textContaining('Answer 39', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Question 0'), findsNothing);
    // newest at the bottom, just above the input box
    final answer = tester.getRect(
      find.textContaining('Answer 39', findRichText: true),
    );
    final question = tester.getRect(find.text('Question 39'));
    final input = tester.getRect(find.byType(EditableText));
    expect(question.top, lessThan(answer.top));
    expect(answer.bottom, lessThan(input.top));
    expect(input.top - answer.bottom, lessThan(120));
  });

  testWidgets('Enter that picks an input method candidate does not send', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(LlmChatView(controller: chat, autofocus: true)),
    );
    await tester.pump();
    await tester.showKeyboard(find.byType(EditableText));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'ni',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(prompts, isEmpty);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '你',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(prompts, ['你']);
  });

  testWidgets('a held Enter sends once and adds no new lines', (tester) async {
    await tester.pumpWidget(
      _app(LlmChatView(controller: chat, autofocus: true)),
    );
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'Once');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(prompts, ['Once']);
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.controller.text, isEmpty);
  });

  testWidgets('the input is one text field named by the hint', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(LlmChatView(controller: chat)));
    final node = tester.getSemantics(find.byType(EditableText));
    expect(node.label, 'Message');
    expect(node.flagsCollection.isTextField, isTrue);
    expect(_button('Send'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('replies taken out by retry are disposed after a frame', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(LlmChatView(controller: chat)));
    await tester.enterText(find.byType(EditableText), 'Q');
    await tester.pump();
    await tester.tap(_button('Send'));
    await tester.pump();
    await source.close();
    await _settle(tester);
    final old = chat.messages.last.reply!;
    source = StreamController<String>();
    await tester.tap(_button('Try again'));
    await tester.pump();
    await tester.pump();
    expect(() => old.addListener(() {}), throwsFlutterError);
    await source.close();
    await _settle(tester);
    semantics.dispose();
  });
}
