import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown_chat/llm_markdown_chat.dart';

Future<void> _echo(
  String prompt,
  StreamingMarkdownController reply,
  List<ChatMessage> history,
) async => reply.append('Re: $prompt');

Widget _app(Widget child) => WidgetsApp(
  color: const Color(0xFF2196F3),
  builder: (context, _) => DefaultTextStyle(
    style: const TextStyle(fontSize: 14, color: Color(0xFF000000)),
    child: child,
  ),
);

Finder _button(String label) => find.bySemanticsLabel(label);

// `isSelected` is a bool in older Flutter versions and a Tristate in newer
// ones; both print "true" when set.
bool _selected(WidgetTester tester, Finder finder) =>
    '${tester.getSemantics(finder).flagsCollection.isSelected}'
        .toLowerCase()
        .contains('true');

void main() {
  group('ChatListController', () {
    test('create, select, rename and delete', () async {
      final list = ChatListController(onReply: _echo);
      addTearDown(list.dispose);
      var notified = 0;
      list.addListener(() => notified++);
      expect(list.chats, isEmpty);
      expect(list.selected, isNull);

      final first = list.create();
      expect(list.selected, first);
      expect(first.title, '');
      expect(notified, 1);

      // the title follows the first user message, shortened
      await first.controller.send(
        'Plan a   trip to the mountains\nfor next summer, with hikes',
      );
      expect(first.title, 'Plan a trip to the mountains for next su…');
      expect(first.hasCustomTitle, isFalse);
      expect(notified, 2);
      await first.controller.send('And more');
      expect(notified, 2);

      final second = list.create(title: 'Work');
      final third = list.create(select: false);
      expect(list.chats, [third, second, first]);
      expect(list.selected, second);
      expect(second.title, 'Work');
      expect(second.controller, isNot(same(first.controller)));
      expect({for (final chat in list.chats) chat.id}.length, 3);

      list.select(first);
      expect(list.selected, first);
      final before = notified;
      list.select(first);
      expect(notified, before);

      list.rename(first, '  Holidays ');
      expect(first.title, 'Holidays');
      expect(first.hasCustomTitle, isTrue);
      expect(notified, before + 1);
      list.rename(first, '');
      expect(first.title, 'Plan a trip to the mountains for next su…');

      // deleting the selected chat selects its neighbour
      list.delete(first);
      expect(list.chats, [third, second]);
      expect(list.selected, second);
      list.delete(third);
      expect(list.selected, second);
      list.delete(second);
      expect(list.chats, isEmpty);
      expect(list.selected, isNull);
      // a chat that is gone is ignored
      list
        ..select(first)
        ..rename(first, 'x')
        ..delete(first);
      expect(list.selected, isNull);
      expect(first.title, isNot('x'));
    });

    testWidgets('a deleted chat is disposed after a frame', (tester) async {
      final list = ChatListController(onReply: _echo);
      addTearDown(list.dispose);
      final chat = list.create();
      list.create();
      var notified = 0;
      list.addListener(() => notified++);
      list.delete(chat);
      expect(notified, 1);
      // a view may still show it during this frame
      chat.controller.addListener(() {});
      await tester.pump();
      expect(notified, 1);
      expect(() => chat.controller.addListener(() {}), throwsFlutterError);
    });

    test('toJson and fromJson give the same chats', () async {
      final list = ChatListController(onReply: _echo);
      addTearDown(list.dispose);
      final first = list.create();
      await first.controller.send('Hello there');
      final second = list.create(title: 'Named');
      await second.controller.send('Second chat');
      list.create(select: false);
      list.select(first);

      final json = list.toJson();
      expect(json['version'], 1);
      final prompts = <String>[];
      final restored = ChatListController.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, Object?>,
        onReply: (prompt, reply, history) async {
          prompts.add(prompt);
          reply.append('New');
        },
      );
      addTearDown(restored.dispose);

      expect(
        [for (final chat in restored.chats) chat.id],
        [for (final chat in list.chats) chat.id],
      );
      expect(
        [for (final chat in restored.chats) chat.title],
        ['', 'Named', 'Hello there'],
      );
      expect(restored.chats[1].hasCustomTitle, isTrue);
      expect(restored.chats[2].hasCustomTitle, isFalse);
      expect(restored.selected!.id, first.id);
      expect(
        restored.chats[2].createdAt.isAtSameMomentAs(first.createdAt),
        isTrue,
      );
      expect(
        [for (final m in restored.selected!.controller.messages) m.text],
        ['Hello there', 'Re: Hello there'],
      );
      expect(jsonEncode(restored.toJson()), jsonEncode(json));

      // the restored chats work, and their titles are still followed
      var notified = 0;
      restored.addListener(() => notified++);
      await restored.chats[0].controller.send('Fresh');
      expect(prompts, ['Fresh']);
      expect(restored.chats[0].title, 'Fresh');
      expect(notified, 1);
    });

    test('controllerBuilder makes the controllers', () {
      final made = <List<ChatMessage>>[];
      final list = ChatListController(
        controllerBuilder: (history) {
          made.add(history);
          return LlmChatController(onReply: _echo, history: history);
        },
      );
      addTearDown(list.dispose);
      final chat = list.create(history: [ChatMessage.user('Old')]);
      expect(made.single.single.text, 'Old');
      expect(chat.title, 'Old');
      expect(
        ChatListController.fromJson(const {'chats': 'none'}, onReply: _echo)
          ..dispose(),
        isA<ChatListController>(),
      );
    });
  });

  group('ChatListView', () {
    testWidgets('lists the titles, selects, creates and deletes', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final list = ChatListController(onReply: _echo);
      addTearDown(list.dispose);
      final first = list.create(history: [ChatMessage.user('First chat')]);
      final second = list.create(title: 'Second');
      final picked = <ChatSession>[];
      await tester.pumpWidget(
        _app(ChatListView(controller: list, onSelected: picked.add)),
      );

      expect(find.text('First chat'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
      // newest first
      expect(
        tester.getTopLeft(find.text('Second')).dy,
        lessThan(tester.getTopLeft(find.text('First chat')).dy),
      );
      expect(_selected(tester, _button('Second')), isTrue);

      await tester.tap(find.text('First chat'));
      await tester.pump();
      expect(list.selected, first);
      expect(picked, [first]);
      expect(_selected(tester, _button('Second')), isFalse);
      expect(_selected(tester, _button('First chat')), isTrue);

      // a new chat is shown as "New chat" and selected
      await tester.tap(_button('New chat'));
      await tester.pump();
      expect(list.chats.length, 3);
      expect(list.selected, list.chats.first);
      expect(picked.last, list.chats.first);
      expect(find.text('New chat'), findsNWidgets(2));

      // a rename shows at once
      list.rename(second, 'Renamed');
      await tester.pump();
      expect(find.text('Renamed'), findsOneWidget);
      expect(find.text('Second'), findsNothing);

      await tester.tap(_button('Delete Renamed'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Renamed'), findsNothing);
      expect(list.chats.contains(second), isFalse);
      expect(list.chats.length, 2);
      semantics.dispose();
    });

    testWidgets('options: no buttons, confirm, own rows and labels', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final list = ChatListController(onReply: _echo);
      addTearDown(list.dispose);
      final chat = list.create(title: 'Keep me');
      var answer = false;
      await tester.pumpWidget(
        _app(
          ChatListView(
            controller: list,
            labels: const ChatListLabels(newChat: 'Start', delete: 'Remove'),
            confirmDelete: (chat) async => answer,
          ),
        ),
      );
      expect(_button('Start'), findsOneWidget);
      await tester.tap(_button('Remove Keep me'));
      await tester.pump();
      expect(list.chats, [chat]);
      answer = true;
      await tester.tap(_button('Remove Keep me'));
      await tester.pump();
      await tester.pump();
      expect(list.chats, isEmpty);

      list.create(title: 'Mine');
      await tester.pumpWidget(
        _app(
          ChatListView(
            controller: list,
            showNewChat: false,
            showDelete: false,
            itemBuilder: (context, chat, selected) =>
                Text('${chat.title} ${selected ? 'on' : 'off'}'),
          ),
        ),
      );
      expect(find.text('Mine on'), findsOneWidget);
      expect(_button('New chat'), findsNothing);
      await tester.pumpWidget(
        _app(
          ChatListView(controller: list, showNewChat: false, showDelete: false),
        ),
      );
      expect(find.text('Mine'), findsOneWidget);
      expect(_button('Delete Mine'), findsNothing);
      semantics.dispose();
    });

    testWidgets('the chat screen follows the selected chat', (tester) async {
      final list = ChatListController(onReply: _echo);
      addTearDown(list.dispose);
      final first = list.create(history: [ChatMessage.user('Alpha')]);
      list.create(history: [ChatMessage.user('Beta')]);
      await tester.pumpWidget(
        _app(
          ListenableBuilder(
            listenable: list,
            builder: (context, _) => Row(
              children: [
                SizedBox(width: 200, child: ChatListView(controller: list)),
                Expanded(
                  child: LlmChatView(controller: list.selected!.controller),
                ),
              ],
            ),
          ),
        ),
      );
      // once in the list, once as the message
      expect(find.text('Beta'), findsNWidgets(2));
      expect(find.text('Alpha'), findsOneWidget);
      await tester.enterText(find.byType(EditableText), 'draft');
      list.select(first);
      await tester.pump();
      expect(find.text('Alpha'), findsNWidgets(2));
      expect(find.text('Beta'), findsOneWidget);
      // what was typed for the other chat is not carried over
      expect(find.text('draft'), findsNothing);
    });
  });
}
