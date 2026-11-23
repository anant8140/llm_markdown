import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'chat_controller.dart';

/// One chat of a [ChatListController]: its messages and its title.
class ChatSession {
  ChatSession._(this.id, this.controller, this.createdAt, this._title);

  /// Tells the chats apart.
  final String id;

  /// The messages of this chat.
  final LlmChatController controller;

  /// When the chat was made.
  final DateTime createdAt;

  String? _title;

  /// Whether the title was set with [ChatListController.rename], and so
  /// does not follow the first message.
  bool get hasCustomTitle => _title != null;

  /// The name of the chat: the one given with [ChatListController.rename],
  /// or else the start of the first user message, or else an empty text
  /// (a chat without messages; `ChatListView` shows "New chat" for it).
  String get title {
    final custom = _title;
    if (custom != null) return custom;
    for (final message in controller.messages) {
      if (message.role != ChatRole.user) continue;
      final text = message.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty) continue;
      return text.length <= ChatListController.titleLength
          ? text
          : '${text.substring(0, ChatListController.titleLength).trimRight()}…';
    }
    return '';
  }
}

/// Several chats, one of them selected, each with its own
/// [LlmChatController].
///
/// ```dart
/// final chats = ChatListController(onReply: askModel)..create();
/// // ...
/// ChatListView(controller: chats)                       // in a drawer
/// LlmChatView(controller: chats.selected!.controller)   // the screen
/// ```
class ChatListController extends ChangeNotifier {
  /// A list of chats that ask [onReply] for their replies, or whose
  /// controllers are made by [controllerBuilder] (for example with
  /// `LlmChatController.sse`) from the messages a chat starts with. One of
  /// the two is needed.
  ChatListController({this.onReply, this.controllerBuilder})
    : assert(
        onReply != null || controllerBuilder != null,
        'Give onReply or controllerBuilder',
      );

  /// The chats restored from what [toJson] wrote. Entries that are not
  /// JSON objects are skipped.
  factory ChatListController.fromJson(
    Map<Object?, Object?> json, {
    ChatReplier? onReply,
    LlmChatController Function(List<ChatMessage> history)? controllerBuilder,
  }) {
    final list = ChatListController(
      onReply: onReply,
      controllerBuilder: controllerBuilder,
    );
    final chats = json['chats'];
    if (chats is List) {
      for (final chat in chats) {
        if (chat is! Map) continue;
        final id = chat['id'];
        final title = chat['title'];
        final time = chat['time'];
        final saved = chat['chat'];
        final session = ChatSession._(
          id is String ? id : _newId(),
          list._newController(
            saved is Map ? LlmChatController.messagesFromJson(saved) : const [],
          ),
          (time is String ? DateTime.tryParse(time) : null) ?? DateTime.now(),
          title is String ? title : null,
        );
        list._add(session, list._chats.length);
      }
    }
    final selected = json['selected'];
    for (final chat in list._chats) {
      if (chat.id == selected) list._selected = chat;
    }
    return list;
  }

  /// The version [toJson] writes.
  static const int jsonVersion = 1;

  /// The most characters of the first message used as a title.
  static const int titleLength = 40;

  /// Writes the replies of every chat, unless [controllerBuilder] is
  /// given.
  final ChatReplier? onReply;

  /// Makes the controller of a chat that starts with `history`.
  final LlmChatController Function(List<ChatMessage> history)?
  controllerBuilder;

  final List<ChatSession> _chats = [];
  final Map<ChatSession, VoidCallback> _watchers = {};
  ChatSession? _selected;
  bool _disposed = false;

  static int _count = 0;
  static final String _run = DateTime.now().microsecondsSinceEpoch
      .toRadixString(36);
  static String _newId() => 'chat_${_run}_${_count++}';

  /// The chats, newest first.
  List<ChatSession> get chats => List.unmodifiable(_chats);

  /// The chat being shown, or `null` when there is none.
  ChatSession? get selected => _selected;

  LlmChatController _newController(List<ChatMessage> history) {
    final builder = controllerBuilder;
    if (builder != null) return builder(history);
    return LlmChatController(onReply: onReply!, history: history);
  }

  void _add(ChatSession chat, int index) {
    _chats.insert(index, chat);
    // tell the list when the title changes with the first message
    var shown = chat.title;
    void watch() {
      final title = chat.title;
      if (title == shown) return;
      shown = title;
      notifyListeners();
    }

    _watchers[chat] = watch;
    chat.controller.addListener(watch);
  }

  /// Adds a new chat at the top and, unless [select] is false, selects
  /// it. [title] names it; without one the title follows its first
  /// message. [history] gives it messages to start with.
  ChatSession create({
    String? title,
    Iterable<ChatMessage> history = const [],
    bool select = true,
  }) {
    final chat = ChatSession._(
      _newId(),
      _newController(List.of(history)),
      DateTime.now(),
      title,
    );
    _add(chat, 0);
    if (select || _selected == null) _selected = chat;
    notifyListeners();
    return chat;
  }

  /// Shows [chat], one of [chats].
  void select(ChatSession chat) {
    if (_selected == chat || !_chats.contains(chat)) return;
    _selected = chat;
    notifyListeners();
  }

  /// Names [chat]; `null` or an empty [title] lets the title follow the
  /// first message again.
  void rename(ChatSession chat, String? title) {
    if (!_chats.contains(chat)) return;
    final trimmed = title?.trim() ?? '';
    final next = trimmed.isEmpty ? null : trimmed;
    if (chat._title == next) return;
    chat._title = next;
    notifyListeners();
  }

  /// Removes [chat] and disposes its controller. When it was the selected
  /// one, the chat after it (or else the one before it) is selected.
  void delete(ChatSession chat) {
    final index = _chats.indexOf(chat);
    if (index == -1) return;
    _chats.removeAt(index);
    chat.controller.removeListener(_watchers.remove(chat)!);
    if (_selected == chat) {
      _selected = _chats.isEmpty
          ? null
          : _chats[index < _chats.length ? index : _chats.length - 1];
    }
    notifyListeners();
    _disposeLater(chat.controller);
  }

  // A view may still show the chat until its next frame.
  void _disposeLater(LlmChatController controller) {
    final SchedulerBinding binding;
    try {
      binding = SchedulerBinding.instance;
    } on Object {
      controller.dispose();
      return;
    }
    binding.addPostFrameCallback((_) => controller.dispose());
    binding.ensureVisualUpdate();
  }

  /// Every chat as JSON, to save them and bring them back with
  /// [ChatListController.fromJson]:
  ///
  /// ```json
  /// {"version": 1, "selected": "...", "chats": [
  ///   {"id": "...", "title": "Trip", "time": "...", "chat": {...}}
  /// ]}
  /// ```
  ///
  /// `chat` is what [LlmChatController.toJson] writes, with the same
  /// [thinking], [sources] and [attachmentBytes] options; `title` is only
  /// there for a renamed chat.
  Map<String, Object?> toJson({
    bool thinking = true,
    bool sources = true,
    bool attachmentBytes = true,
  }) => {
    'version': jsonVersion,
    if (_selected != null) 'selected': _selected!.id,
    'chats': [
      for (final chat in _chats)
        {
          'id': chat.id,
          if (chat._title != null) 'title': chat._title,
          'time': chat.createdAt.toUtc().toIso8601String(),
          'chat': chat.controller.toJson(
            thinking: thinking,
            sources: sources,
            attachmentBytes: attachmentBytes,
          ),
        },
    ],
  };

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final chat in _chats) {
      chat.controller.removeListener(_watchers.remove(chat)!);
      chat.controller.dispose();
    }
    super.dispose();
  }
}
