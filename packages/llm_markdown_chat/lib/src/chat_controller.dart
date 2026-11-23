import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:llm_markdown/llm_markdown.dart';

/// Who wrote a [ChatMessage].
enum ChatRole {
  /// The person using the app.
  user,

  /// The model.
  assistant,
}

/// One message of a chat.
///
/// A message of the [ChatRole.assistant] has a [reply] controller that holds
/// its text, thinking, tool calls and sources, and streams them in.
class ChatMessage {
  /// A message the person wrote.
  ChatMessage.user(String text, {String? id})
    : id = id ?? _newId(),
      role = ChatRole.user,
      reply = null,
      _text = text;

  /// A finished reply of the model, for example from a saved chat.
  ChatMessage.assistant(String text, {String? id})
    : id = id ?? _newId(),
      role = ChatRole.assistant,
      reply = StreamingMarkdownController(text: text, isComplete: true),
      _text = '';

  ChatMessage._streaming()
    : id = _newId(),
      role = ChatRole.assistant,
      reply = StreamingMarkdownController(),
      _text = '';

  static int _count = 0;
  static String _newId() => 'message_${_count++}';

  /// Tells the messages apart, also when their text is the same.
  final String id;

  /// Who wrote it.
  final ChatRole role;

  /// The model's reply, for a message of the [ChatRole.assistant]; `null`
  /// for one of the user.
  final StreamingMarkdownController? reply;

  final String _text;

  /// The text so far.
  String get text => reply?.text ?? _text;

  /// Whether this reply ended with an error.
  bool get hasError => reply?.error != null;
}

/// Writes the reply to [prompt] into [reply], for example with
/// `reply.addOpenAIStream(response.stream)`.
///
/// [history] is the chat before [prompt], oldest first. When the returned
/// future ends, a reply that is not complete yet is completed; an error
/// ends it with [StreamingMarkdownController.completeWithError].
typedef ChatReplier =
    Future<void> Function(
      String prompt,
      StreamingMarkdownController reply,
      List<ChatMessage> history,
    );

/// The messages of a chat, and the sending of new ones.
///
/// ```dart
/// final chat = LlmChatController(
///   onReply: (prompt, reply, history) async {
///     final response = await client.send(buildRequest(history, prompt));
///     await reply.addOpenAIStream(response.stream);
///   },
/// );
/// ```
class LlmChatController extends ChangeNotifier {
  /// A chat that asks [onReply] for each reply, starting with [history].
  LlmChatController({
    required this.onReply,
    Iterable<ChatMessage> history = const [],
  }) : _messages = List.of(history);

  /// Writes each reply.
  final ChatReplier onReply;

  final List<ChatMessage> _messages;
  // messages taken out of the list are disposed with the controller, as a
  // view may still show them until its next frame
  final List<ChatMessage> _removed = [];
  ChatMessage? _replying;

  /// The messages, oldest first.
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// Whether a reply is being written; [send] waits for it to end.
  bool get isReplying => _replying != null;

  /// Whether [retry] can ask again: the last message is a reply (finished,
  /// stopped or ended with an error) and nothing is being written.
  bool get canRetry =>
      !isReplying &&
      _messages.length >= 2 &&
      _messages.last.role == ChatRole.assistant &&
      _messages[_messages.length - 2].role == ChatRole.user;

  /// Sends [prompt] and asks [onReply] for the reply.
  ///
  /// Does nothing for an empty prompt or while a reply is being written.
  /// The future ends with the reply.
  Future<void> send(String prompt) async {
    final text = prompt.trim();
    if (text.isEmpty || isReplying) return;
    final history = List<ChatMessage>.unmodifiable(_messages);
    final message = ChatMessage._streaming();
    final reply = message.reply!;
    _messages
      ..add(ChatMessage.user(text))
      ..add(message);
    _replying = message;
    notifyListeners();
    try {
      await onReply(text, reply, history);
      if (_live(message) && !reply.isComplete) reply.complete();
    } catch (error, stackTrace) {
      if (_live(message) && !reply.isComplete) {
        reply.completeWithError(error, stackTrace);
      }
    } finally {
      if (_replying == message) {
        _replying = null;
        if (!_disposed) notifyListeners();
      }
    }
  }

  bool _live(ChatMessage message) => !_disposed && !_removed.contains(message);

  /// Ends the reply being written, keeping what it wrote so far. The
  /// adapters of `llm_markdown` stop reading, which closes the request.
  void stop() {
    final message = _replying;
    if (message == null) return;
    _replying = null;
    message.reply!.complete();
    notifyListeners();
  }

  /// Asks again for the last reply: removes it and its prompt, and sends
  /// the prompt again. See [canRetry].
  Future<void> retry() {
    if (!canRetry) return Future.value();
    final reply = _messages.removeLast();
    final prompt = _messages.removeLast();
    _removed.addAll([reply, prompt]);
    return send(prompt.text);
  }

  /// Removes every message, stopping a reply being written.
  void clear() {
    final message = _replying;
    _replying = null;
    message?.reply!.complete();
    _removed.addAll(_messages);
    _messages.clear();
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _replying?.reply!.complete();
    _replying = null;
    for (final message in [..._messages, ..._removed]) {
      message.reply?.dispose();
    }
    super.dispose();
  }
}
