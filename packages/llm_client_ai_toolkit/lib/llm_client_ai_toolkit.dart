/// An `LlmProvider` for the Flutter AI Toolkit that talks to any model
/// `llm_client` supports: OpenAI and OpenAI-compatible servers, Anthropic,
/// Gemini and Ollama.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';
import 'package:llm_client/llm_client.dart' as llm;

/// Gives `LlmChatView` a model through `llm_client`.
///
/// ```dart
/// LlmChatView(
///   provider: LlmClientProvider(
///     client: llm.OpenAIProvider(apiKey: key),
///     model: 'gpt-4.1-mini',
///     system: 'You are a helpful assistant.',
///   ),
/// )
/// ```
///
/// The chat's history is sent with every prompt. Cancelling a reply (the
/// toolkit's stop button) aborts the request.
///
/// Attachments: a link is added to the prompt as its URL; files and images
/// are not sent, since `llm_client` sends text only. Set
/// [onUnsupportedAttachment] to hear about those, or the reply fails with
/// an [LlmFailureException] when [failOnUnsupportedAttachment] is true.
class LlmClientProvider extends LlmProvider with ChangeNotifier {
  /// A provider that asks [client] for [model].
  LlmClientProvider({
    required this.client,
    required this.model,
    this.system,
    this.temperature,
    this.maxTokens,
    this.extra = const {},
    this.failOnUnsupportedAttachment = false,
    this.onUnsupportedAttachment,
    Iterable<ChatMessage>? history,
  }) : _history = List<ChatMessage>.of(history ?? const []);

  /// The `llm_client` provider: `OpenAIProvider`, `AnthropicProvider`,
  /// `GeminiProvider` or `OllamaProvider`.
  final llm.LlmProvider client;

  /// The model's name.
  final String model;

  /// The system prompt, if any.
  final String? system;

  /// The sampling temperature, if set.
  final double? temperature;

  /// The most tokens a reply may have, if set.
  final int? maxTokens;

  /// Extra fields for the request body, as in `llm.LlmRequest.extra`.
  final Map<String, Object?> extra;

  /// Whether a file or image attachment, which can't be sent, fails the
  /// reply instead of being left out.
  final bool failOnUnsupportedAttachment;

  /// Called with each attachment that is left out.
  final void Function(Attachment attachment)? onUnsupportedAttachment;

  final List<ChatMessage> _history;

  @override
  Iterable<ChatMessage> get history => _history;

  @override
  set history(Iterable<ChatMessage> history) {
    _history
      ..clear()
      ..addAll(history);
    notifyListeners();
  }

  @override
  Stream<String> generateStream(
    String prompt, {
    Iterable<Attachment> attachments = const [],
  }) => _reply([
    if (system != null) llm.LlmMessage.system(system!),
    llm.LlmMessage.user(_withLinks(prompt, attachments)),
  ]);

  @override
  Stream<String> sendMessageStream(
    String prompt, {
    Iterable<Attachment> attachments = const [],
  }) {
    final earlier = [
      for (final message in _history)
        if ((message.text ?? '').isNotEmpty)
          message.origin.isUser
              ? llm.LlmMessage.user(
                  _withLinks(message.text!, message.attachments, tell: false),
                )
              : llm.LlmMessage.assistant(message.text!),
    ];
    final question = ChatMessage.user(prompt, attachments);
    final answer = ChatMessage.llm();
    _history.addAll([question, answer]);
    notifyListeners();
    final String text;
    try {
      text = _withLinks(prompt, attachments);
    } on LlmFailureException catch (error) {
      return Stream.error(error);
    }
    return _reply(
      [
        if (system != null) llm.LlmMessage.system(system!),
        ...earlier,
        llm.LlmMessage.user(text),
      ],
      onText: answer.append,
      onDone: notifyListeners,
    );
  }

  // The prompt with the URLs of link attachments under it.
  String _withLinks(
    String prompt,
    Iterable<Attachment> attachments, {
    bool tell = true,
  }) {
    final links = <String>[];
    for (final attachment in attachments) {
      if (attachment is LinkAttachment) {
        links.add('${attachment.url}');
      } else if (tell) {
        onUnsupportedAttachment?.call(attachment);
        if (failOnUnsupportedAttachment) {
          throw LlmFailureException(
            'The attachment "${attachment.name}" can\'t be sent: this '
            'provider sends text only.',
          );
        }
      }
    }
    return links.isEmpty ? prompt : '$prompt\n\n${links.join('\n')}';
  }

  Stream<String> _reply(
    List<llm.LlmMessage> messages, {
    void Function(String text)? onText,
    VoidCallback? onDone,
  }) {
    final Stream<String> text;
    try {
      text = client.text(
        llm.LlmRequest(
          model: model,
          messages: messages,
          temperature: temperature,
          maxTokens: maxTokens,
          extra: extra,
        ),
      );
    } catch (error) {
      return Stream.error(LlmFailureException('$error'));
    }
    late final StreamController<String> out;
    StreamSubscription<String>? inner;
    out = StreamController<String>(
      onListen: () {
        inner = text.listen(
          (chunk) {
            onText?.call(chunk);
            out.add(chunk);
          },
          onError: (Object error) {
            // the toolkit shows its own exceptions in the chat
            out.addError(
              LlmFailureException(
                error is llm.LlmException ? error.message : '$error',
              ),
            );
            onDone?.call();
            out.close();
          },
          onDone: () {
            onDone?.call();
            out.close();
          },
        );
      },
      onPause: () => inner?.pause(),
      onResume: () => inner?.resume(),
      // cancelling aborts the request
      onCancel: () {
        onDone?.call();
        return inner?.cancel();
      },
    );
    return out.stream;
  }
}
