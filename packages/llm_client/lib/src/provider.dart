import 'types.dart';

/// A chat API that streams replies. [OpenAIProvider], [AnthropicProvider],
/// [GeminiProvider] and [OllamaProvider] are the ones in this package;
/// extend this class for another API.
abstract class LlmProvider {
  /// For subclasses.
  const LlmProvider();

  /// Sends [request] and gives the reply as it arrives.
  ///
  /// The HTTP request starts when the stream is listened to, and each
  /// listen makes a new one. A complete reply ends with [LlmUsage], when
  /// the provider reports usage, and then [LlmDone]. Cancelling the
  /// subscription aborts the HTTP request.
  ///
  /// The stream ends with an [LlmException] when the API answers with an
  /// error, sends an error in the middle of the stream, or the connection
  /// closes before the reply is finished. Network errors, such as no
  /// connection, come through as `package:http` throws them.
  Stream<LlmEvent> stream(LlmRequest request);

  /// The text of the reply to [request], piece by piece; everything else
  /// in the stream is dropped.
  Stream<String> text(LlmRequest request) => stream(request)
      .where((event) => event is LlmTextDelta)
      .map((e) => (e as LlmTextDelta).text);

  /// Sends [request] and waits for the whole reply.
  Future<LlmResponse> complete(LlmRequest request) async {
    final text = StringBuffer();
    final thinking = StringBuffer();
    final toolCalls = <LlmToolCall>[];
    LlmUsage? usage;
    var finishReason = LlmFinishReason.other;
    String? rawFinishReason;
    await for (final event in stream(request)) {
      switch (event) {
        case LlmTextDelta():
          text.write(event.text);
        case LlmThinkingDelta():
          thinking.write(event.text);
        case LlmToolCallDone():
          toolCalls.add(event.toolCall);
        case LlmUsage():
          usage = event;
        case LlmDone():
          finishReason = event.finishReason;
          rawFinishReason = event.rawFinishReason;
        case LlmToolCallStart() || LlmToolCallDelta():
          break;
      }
    }
    return LlmResponse(
      text: text.toString(),
      thinking: thinking.toString(),
      toolCalls: toolCalls,
      usage: usage,
      finishReason: finishReason,
      rawFinishReason: rawFinishReason,
    );
  }
}
