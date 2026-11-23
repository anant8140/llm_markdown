import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:http/http.dart' as http;
import 'package:llm_markdown/llm_markdown.dart';

import 'sse_backend.dart';

/// Who wrote a [ChatMessage].
enum ChatRole {
  /// The person using the app.
  user,

  /// The model.
  assistant,
}

/// A file, image or other item sent with a user's message.
///
/// The package does not pick or read files itself: the app gives these
/// from `LlmChatView.onPickAttachment`, with the [bytes] or a [uri] (a
/// file path or an address) it can read later.
class ChatAttachment {
  /// An attachment called [name].
  const ChatAttachment({
    required this.name,
    this.mimeType,
    this.bytes,
    this.uri,
  });

  /// Reads what [toJson] wrote.
  factory ChatAttachment.fromJson(Map<Object?, Object?> json) {
    final name = json['name'];
    final mimeType = json['mimeType'];
    final bytes = json['bytes'];
    final uri = json['uri'];
    Uint8List? decoded;
    if (bytes is String) {
      try {
        decoded = base64Decode(bytes);
      } on FormatException {
        decoded = null;
      }
    }
    return ChatAttachment(
      name: name is String ? name : '',
      mimeType: mimeType is String ? mimeType : null,
      bytes: decoded,
      uri: uri is String ? uri : null,
    );
  }

  /// The name shown for it, such as the file name.
  final String name;

  /// The kind of content, such as `image/png`.
  final String? mimeType;

  /// The content, when the app holds it in memory.
  final Uint8List? bytes;

  /// Where the content is: a file path or an address.
  final String? uri;

  /// This attachment as JSON; [bytes] are written as base64 unless
  /// [includeBytes] is false.
  Map<String, Object?> toJson({bool includeBytes = true}) => {
    'name': name,
    if (mimeType != null) 'mimeType': mimeType,
    if (uri != null) 'uri': uri,
    if (includeBytes && bytes != null) 'bytes': base64Encode(bytes!),
  };

  @override
  String toString() => 'ChatAttachment($name)';
}

/// One message of a chat.
///
/// A message of the [ChatRole.assistant] has a [reply] controller that holds
/// its text, thinking, tool calls and sources, and streams them in.
class ChatMessage {
  /// A message the person wrote, with the [attachments] sent along.
  ChatMessage.user(
    String text, {
    String? id,
    List<ChatAttachment> attachments = const [],
    this.createdAt,
  }) : id = id ?? _newId(),
       role = ChatRole.user,
       reply = null,
       attachments = List.unmodifiable(attachments),
       _text = text;

  /// A finished reply of the model, for example from a saved chat. It is
  /// shown complete, without a cursor and without being animated in.
  ChatMessage.assistant(
    String text, {
    String? id,
    String thinking = '',
    List<MarkdownSource> sources = const [],
    Object? error,
    this.createdAt,
  }) : id = id ?? _newId(),
       role = ChatRole.assistant,
       reply = _finished(text, thinking, sources, error),
       attachments = const [],
       _text = '';

  ChatMessage._streaming()
    : id = _newId(),
      role = ChatRole.assistant,
      reply = StreamingMarkdownController(),
      attachments = const [],
      createdAt = DateTime.now(),
      _text = '';

  /// Reads what [toJson] wrote. Fields it does not know are ignored.
  factory ChatMessage.fromJson(Map<Object?, Object?> json) {
    final id = json['id'];
    final text = json['text'];
    final time = json['time'];
    final createdAt = time is String ? DateTime.tryParse(time) : null;
    if (json['role'] == ChatRole.assistant.name) {
      final thinking = json['thinking'];
      final sources = json['sources'];
      return ChatMessage.assistant(
        text is String ? text : '',
        id: id is String ? id : null,
        thinking: thinking is String ? thinking : '',
        sources: [
          if (sources is List)
            for (final source in sources)
              if (source is Map) _sourceFromJson(source),
        ],
        error: json['error'],
        createdAt: createdAt,
      );
    }
    final attachments = json['attachments'];
    return ChatMessage.user(
      text is String ? text : '',
      id: id is String ? id : null,
      attachments: [
        if (attachments is List)
          for (final attachment in attachments)
            if (attachment is Map) ChatAttachment.fromJson(attachment),
      ],
      createdAt: createdAt,
    );
  }

  static StreamingMarkdownController _finished(
    String text,
    String thinking,
    List<MarkdownSource> sources,
    Object? error,
  ) {
    if (thinking.isEmpty && sources.isEmpty && error == null) {
      return StreamingMarkdownController(text: text, isComplete: true);
    }
    final reply = StreamingMarkdownController()
      ..appendThinking(thinking)
      ..append(text);
    for (final source in sources) {
      reply.addSource(source);
    }
    if (error == null) {
      reply.complete();
    } else {
      reply.completeWithError(error);
    }
    return reply;
  }

  static MarkdownSource _sourceFromJson(Map<Object?, Object?> json) {
    final url = json['url'];
    final title = json['title'];
    final citedText = json['citedText'];
    return MarkdownSource(
      url: url is String ? url : null,
      title: title is String ? title : null,
      citedText: citedText is String ? citedText : null,
    );
  }

  static int _count = 0;
  // made of the start time too, so that the messages of a restored chat
  // and new ones don't get the same id
  static final String _run = DateTime.now().microsecondsSinceEpoch
      .toRadixString(36);
  static String _newId() => 'message_${_run}_${_count++}';

  /// Tells the messages apart, also when their text is the same.
  final String id;

  /// Who wrote it.
  final ChatRole role;

  /// The model's reply, for a message of the [ChatRole.assistant]; `null`
  /// for one of the user.
  final StreamingMarkdownController? reply;

  /// What the user sent along with the text; empty for a reply.
  final List<ChatAttachment> attachments;

  /// When the message was sent, if known. Messages made by
  /// [LlmChatController.send] have it.
  final DateTime? createdAt;

  final String _text;

  /// The text so far.
  String get text => reply?.text ?? _text;

  /// Whether this reply ended with an error.
  bool get hasError => reply?.error != null;

  /// This message as JSON: `id`, `role`, `text` and `time`; a user's
  /// message also has its `attachments`, a reply its `thinking`,
  /// `sources` and `error` (as text). A reply still being written is
  /// saved with the text so far.
  ///
  /// [thinking], [sources] and [attachmentBytes] leave those parts out
  /// when false. Tool calls are not saved.
  Map<String, Object?> toJson({
    bool thinking = true,
    bool sources = true,
    bool attachmentBytes = true,
  }) {
    final reply = this.reply;
    return {
      'id': id,
      'role': role.name,
      'text': text,
      if (createdAt != null) 'time': createdAt!.toUtc().toIso8601String(),
      if (attachments.isNotEmpty)
        'attachments': [
          for (final attachment in attachments)
            attachment.toJson(includeBytes: attachmentBytes),
        ],
      if (reply != null && thinking && reply.thinking.isNotEmpty)
        'thinking': reply.thinking,
      if (reply != null && sources && reply.sources.isNotEmpty)
        'sources': [
          for (final source in reply.sources)
            {
              if (source.url != null) 'url': source.url,
              if (source.title != null) 'title': source.title,
              if (source.citedText != null) 'citedText': source.citedText,
            },
        ],
      if (reply != null && reply.error != null) 'error': '${reply.error}',
    };
  }
}

/// Writes the reply to [prompt] into [reply], for example with
/// `reply.addOpenAIStream(response.stream)`.
///
/// [history] is the chat before [prompt], oldest first, without the turns
/// whose reply failed or was stopped before it wrote anything, so it can be
/// sent to a model as it is. When the returned
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

  /// A chat restored from what [toJson] wrote, asking [onReply] for new
  /// replies. The restored replies are complete: they are shown at once,
  /// without a cursor.
  ///
  /// Any `version` written so far can be read; messages that are not JSON
  /// objects are skipped.
  LlmChatController.fromJson(
    Map<Object?, Object?> json, {
    required ChatReplier onReply,
  }) : this(onReply: onReply, history: messagesFromJson(json));

  /// A chat whose replies come from a streaming HTTP endpoint that answers
  /// with server-sent events, through `package:server_sent_events`.
  ///
  /// [body] makes the request body from the messages to send (the chat so
  /// far and the new prompt); [text] takes the reply's text out of the
  /// events and defaults to OpenAI Chat Completions. An error of the API
  /// ends the reply with it, and [stop] aborts the request. See
  /// [SseChatBackend] for the options.
  ///
  /// ```dart
  /// final chat = LlmChatController.sse(
  ///   url: Uri.parse('https://api.openai.com/v1/chat/completions'),
  ///   headers: {'Authorization': 'Bearer $apiKey'},
  ///   body: SseChatBackend.openAIBody(model: 'gpt-4.1-mini'),
  /// );
  /// ```
  factory LlmChatController.sse({
    required Uri url,
    required SseBodyBuilder body,
    Map<String, String> headers = const {},
    SseTextExtractor? text,
    String method = 'POST',
    http.Client? client,
    Duration? connectTimeout,
    Duration? idleTimeout,
    Iterable<ChatMessage> history = const [],
  }) {
    final backend = SseChatBackend(
      url: url,
      body: body,
      headers: headers,
      text: text,
      method: method,
      client: client,
      connectTimeout: connectTimeout,
      idleTimeout: idleTimeout,
    );
    late final LlmChatController chat;
    chat = LlmChatController(
      history: history,
      onReply: (prompt, reply, history) {
        // the prompt as it is in the chat, with its attachments
        final sent = chat.lastUserMessage;
        return backend.reply([
          ...history,
          sent ?? ChatMessage.user(prompt),
        ], reply);
      },
    );
    return chat;
  }

  /// The version [toJson] writes.
  static const int jsonVersion = 1;

  /// The messages in what [toJson] wrote, for example to pass as the
  /// `history` of a controller you construct yourself.
  static List<ChatMessage> messagesFromJson(Map<Object?, Object?> json) {
    final messages = json['messages'];
    return [
      if (messages is List)
        for (final message in messages)
          if (message is Map) ChatMessage.fromJson(message),
    ];
  }

  /// Writes each reply.
  final ChatReplier onReply;

  final List<ChatMessage> _messages;
  // messages taken out of the list, until their replies are disposed: a
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

  /// The newest message of the user, or `null` in an empty chat. While
  /// [onReply] runs this is the prompt being answered, with its
  /// [ChatMessage.attachments].
  ChatMessage? get lastUserMessage {
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].role == ChatRole.user) return _messages[i];
    }
    return null;
  }

  /// The chat as JSON, to save it and bring it back with
  /// [LlmChatController.fromJson]:
  ///
  /// ```json
  /// {"version": 1, "messages": [{"id": "...", "role": "user", "text": "Hi"}]}
  /// ```
  ///
  /// See [ChatMessage.toJson] for the fields of a message and for
  /// [thinking], [sources] and [attachmentBytes].
  Map<String, Object?> toJson({
    bool thinking = true,
    bool sources = true,
    bool attachmentBytes = true,
  }) => {
    'version': jsonVersion,
    'messages': [
      for (final message in _messages)
        message.toJson(
          thinking: thinking,
          sources: sources,
          attachmentBytes: attachmentBytes,
        ),
    ],
  };

  /// Sends [prompt], with [attachments], and asks [onReply] for the reply.
  ///
  /// Does nothing for an empty prompt without attachments, or while a
  /// reply is being written. The future ends with the reply.
  Future<void> send(
    String prompt, {
    List<ChatAttachment> attachments = const [],
  }) async {
    final text = prompt.trim();
    if (_disposed || isReplying) return;
    if (text.isEmpty && attachments.isEmpty) return;
    final history = List<ChatMessage>.unmodifiable(_history());
    final message = ChatMessage._streaming();
    final reply = message.reply!;
    _messages
      ..add(
        ChatMessage.user(
          text,
          attachments: attachments,
          createdAt: DateTime.now(),
        ),
      )
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

  // The messages to give a model: a reply that ended with an error or
  // wrote nothing is left out with its prompt, as most APIs refuse empty
  // messages and want the roles to take turns.
  List<ChatMessage> _history() {
    final kept = <ChatMessage>[];
    for (final message in _messages) {
      final failed =
          message.role == ChatRole.assistant &&
          (message.hasError || message.text.trim().isEmpty);
      if (!failed) {
        kept.add(message);
      } else if (kept.isNotEmpty && kept.last.role == ChatRole.user) {
        kept.removeLast();
      }
    }
    return kept;
  }

  bool _live(ChatMessage message) => !_disposed && !_removed.contains(message);

  /// Ends the reply being written, keeping what it wrote so far. The
  /// adapters of `llm_markdown` stop reading, which closes the request.
  void stop() {
    if (_disposed) return;
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
    return regenerate(_messages.last);
  }

  /// Whether [regenerate] can ask again for [reply]: it is a reply of this
  /// chat that follows a message of the user, and nothing is being
  /// written.
  bool canRegenerate(ChatMessage reply) {
    if (_disposed || isReplying || reply.role != ChatRole.assistant) {
      return false;
    }
    final index = _messages.indexOf(reply);
    return index >= 1 && _messages[index - 1].role == ChatRole.user;
  }

  /// Asks again for [reply]: removes it, its prompt and every message
  /// after them, and sends the prompt again with its attachments. See
  /// [canRegenerate].
  Future<void> regenerate(ChatMessage reply) {
    if (!canRegenerate(reply)) return Future.value();
    final prompt = _messages[_messages.indexOf(reply) - 1];
    _removeFrom(prompt);
    return send(prompt.text, attachments: prompt.attachments);
  }

  /// Whether [edit] can replace [message]: it is a message of the user in
  /// this chat, and nothing is being written.
  bool canEdit(ChatMessage message) =>
      !_disposed &&
      !isReplying &&
      message.role == ChatRole.user &&
      _messages.contains(message);

  /// Replaces the user's [message] with [text]: removes it and every
  /// message after it, and sends [text]. The [attachments] default to the
  /// ones [message] had. See [canEdit].
  ///
  /// Does nothing when [text] is empty and there are no attachments.
  Future<void> edit(
    ChatMessage message,
    String text, {
    List<ChatAttachment>? attachments,
  }) {
    final files = attachments ?? message.attachments;
    if (!canEdit(message) || (text.trim().isEmpty && files.isEmpty)) {
      return Future.value();
    }
    _removeFrom(message);
    return send(text, attachments: files);
  }

  // Takes [first] and everything after it out of the chat.
  void _removeFrom(ChatMessage first) {
    final index = _messages.indexOf(first);
    final removed = _messages.sublist(index);
    _messages.removeRange(index, _messages.length);
    _retire(removed);
  }

  /// Removes every message, stopping a reply being written.
  void clear() {
    if (_disposed) return;
    final message = _replying;
    _replying = null;
    message?.reply!.complete();
    _retire(_messages);
    _messages.clear();
    notifyListeners();
  }

  // Disposes the replies of removed messages once the view has drawn a
  // frame without them; without a running app, when this is disposed.
  void _retire(Iterable<ChatMessage> messages) {
    final removed = [
      for (final message in messages)
        if (message.reply != null) message,
    ];
    if (removed.isEmpty) return;
    _removed.addAll(removed);
    final SchedulerBinding binding;
    try {
      binding = SchedulerBinding.instance;
    } on Object {
      return;
    }
    binding.addPostFrameCallback((_) {
      if (_disposed) return;
      for (final message in removed) {
        if (_removed.remove(message)) message.reply!.dispose();
      }
    });
    binding.ensureVisualUpdate();
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
