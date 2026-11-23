import 'dart:async';

import 'package:flutter/widgets.dart';

import 'chat_list_controller.dart';
import 'chat_view.dart';
import 'plain_button.dart';

/// The words [ChatListView] shows and reads to screen readers.
class ChatListLabels {
  /// Labels in English, or the ones given.
  const ChatListLabels({
    this.newChat = 'New chat',
    this.untitled = 'New chat',
    this.delete = 'Delete',
  });

  /// The button that starts a chat.
  final String newChat;

  /// The title of a chat without messages.
  final String untitled;

  /// The button that removes a chat; screen readers hear it followed by
  /// the chat's title.
  final String delete;
}

/// The chats of a [ChatListController] as a list of titles, with a button
/// for a new chat and one to delete each chat. A tap selects a chat.
///
/// Made of plain widgets, to put in a drawer or a side panel:
///
/// ```dart
/// Drawer(child: ChatListView(
///   controller: chats,
///   onSelected: (_) => Navigator.pop(context),
/// ))
/// ```
class ChatListView extends StatefulWidget {
  /// A list of the chats of [controller].
  const ChatListView({
    super.key,
    required this.controller,
    this.style,
    this.labels = const ChatListLabels(),
    this.onSelected,
    this.showNewChat = true,
    this.showDelete = true,
    this.confirmDelete,
    this.itemBuilder,
  });

  /// The chats.
  final ChatListController controller;

  /// The look; defaults to [LlmChatStyle.of] the context.
  final LlmChatStyle? style;

  /// The words shown and read to screen readers.
  final ChatListLabels labels;

  /// Called after a chat was selected by a tap, or made with the new-chat
  /// button, for example to close the drawer.
  final ValueChanged<ChatSession>? onSelected;

  /// Whether the new-chat button is shown.
  final bool showNewChat;

  /// Whether each chat has a delete button.
  final bool showDelete;

  /// Asked before a chat is deleted, for example with a dialog; the chat
  /// stays when it gives false.
  final Future<bool> Function(ChatSession chat)? confirmDelete;

  /// Builds the row of a chat, instead of the title with a delete button;
  /// `selected` tells whether it is the chat being shown. The row is not
  /// tappable by itself: call [ChatListController.select].
  final Widget Function(BuildContext context, ChatSession chat, bool selected)?
  itemBuilder;

  @override
  State<ChatListView> createState() => _ChatListViewState();
}

class _ChatListViewState extends State<ChatListView> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(ChatListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  void _create() {
    final chat = widget.controller.create();
    widget.onSelected?.call(chat);
  }

  void _select(ChatSession chat) {
    widget.controller.select(chat);
    widget.onSelected?.call(chat);
  }

  Future<void> _delete(ChatSession chat) async {
    final confirm = widget.confirmDelete;
    if (confirm != null && !await confirm(chat)) return;
    widget.controller.delete(chat);
  }

  String _title(ChatSession chat) =>
      chat.title.isEmpty ? widget.labels.untitled : chat.title;

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? LlmChatStyle.of(context);
    final chats = widget.controller.chats;
    final selected = widget.controller.selected;
    final iconColor =
        style.textStyle.color?.withValues(alpha: 0.7) ?? style.accentColor;
    return DefaultTextStyle.merge(
      style: style.textStyle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showNewChat)
            Padding(
              padding: style.padding,
              child: PlainButton(
                label: widget.labels.newChat,
                onTap: _create,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: style.borderColor),
                    borderRadius: BorderRadius.circular(style.radius),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: CustomPaint(
                          painter: PlainIconPainter(
                            icon: PlainIcon.add,
                            color: iconColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          widget.labels.newChat,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(
                horizontal: style.padding.horizontal / 4,
              ),
              itemCount: chats.length,
              itemBuilder: (context, index) {
                final chat = chats[index];
                final custom = widget.itemBuilder;
                return KeyedSubtree(
                  key: ValueKey(chat.id),
                  child: custom != null
                      ? custom(context, chat, chat == selected)
                      : _row(chat, chat == selected, style, iconColor),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    ChatSession chat,
    bool selected,
    LlmChatStyle style,
    Color iconColor,
  ) {
    final title = _title(chat);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(
        color: selected ? style.userBubbleColor : null,
        borderRadius: BorderRadius.circular(style.radius),
      ),
      child: Row(
        children: [
          Expanded(
            child: PlainButton(
              label: title,
              selected: selected,
              onTap: () => _select(chat),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          if (widget.showDelete)
            PlainButton(
              label: '${widget.labels.delete} $title',
              onTap: () => unawaited(_delete(chat)),
              child: SizedBox(
                width: 36,
                height: 36,
                child: CustomPaint(
                  painter: PlainIconPainter(
                    icon: PlainIcon.close,
                    color: iconColor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
