import 'dart:async';

import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
// ignore: implementation_imports
import 'package:llm_markdown/src/renderer.dart' show StreamingCursor;
import 'package:material_ui/material_ui.dart';

/// Answers every prompt with what the test adds to [reply].
class _Provider extends LlmProvider with ChangeNotifier {
  _Provider(this._history);

  final List<ChatMessage> _history;
  final reply = StreamController<String>();

  @override
  Stream<String> generateStream(
    String prompt, {
    Iterable<Attachment> attachments = const [],
  }) => reply.stream;

  @override
  Stream<String> sendMessageStream(
    String prompt, {
    Iterable<Attachment> attachments = const [],
  }) async* {
    final answer = ChatMessage.llm();
    _history.addAll([ChatMessage.user(prompt, attachments), answer]);
    yield* reply.stream.map((chunk) {
      answer.append(chunk);
      return chunk;
    });
    notifyListeners();
  }

  @override
  Iterable<ChatMessage> get history => _history;

  @override
  set history(Iterable<ChatMessage> history) {
    _history
      ..clear()
      ..addAll(history);
    notifyListeners();
  }
}

void main() {
  testWidgets('LlmChatView shows replies with llm_markdown', (tester) async {
    final provider = _Provider([
      ChatMessage.user('Earlier question', const []),
      ChatMessage.llm()..append('Earlier **answer**'),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LlmChatView(
            provider: provider,
            enableAttachments: false,
            enableVoiceNotes: false,
            responseBuilder: (context, response) => StreamingMarkdown.text(
              response,
              completeAfter: const Duration(seconds: 1),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // the reply from the history is built by llm_markdown, complete
    expect(find.byType(StreamingMarkdown), findsOneWidget);
    expect(
      find.textContaining('Earlier answer', findRichText: true),
      findsWidgets,
    );

    await tester.enterText(find.byType(EditableText), 'Tell me');
    await tester.pump();
    await tester.tap(
      find.byWidgetPredicate((w) => w.runtimeType.toString() == 'InputButton'),
    );
    await tester.pump();

    provider.reply.add('# Title\n\nFirst ');
    await tester.pump(const Duration(milliseconds: 100));
    provider.reply.add('part, **second** part.');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(StreamingMarkdown), findsNWidgets(2));
    expect(find.byType(StreamingCursor), findsOneWidget);
    // while it grows the reply streams; a second after the last chunk it is
    // shown whole, in order
    await tester.pump(const Duration(seconds: 2));
    expect(
      find.textContaining('First part, second part.', findRichText: true),
      findsWidgets,
    );
    expect(find.textContaining('Title', findRichText: true), findsWidgets);
    expect(find.byType(StreamingCursor), findsNothing);
    await provider.reply.close();
    await tester.pump(const Duration(seconds: 2));
  });
}
