/// Who a message is from.
enum LlmRole {
  /// Instructions for the model.
  system,

  /// The person talking to the model.
  user,

  /// The model.
  assistant,

  /// The result of a tool the model called.
  tool,
}

/// One message of a conversation.
class LlmMessage {
  /// A message from [role]; the named constructors are shorter.
  const LlmMessage({
    required this.role,
    this.text = '',
    this.toolCalls = const [],
    this.toolCallId,
    this.toolName,
  });

  /// Instructions for the model.
  const LlmMessage.system(this.text)
    : role = LlmRole.system,
      toolCalls = const [],
      toolCallId = null,
      toolName = null;

  /// What the user said.
  const LlmMessage.user(this.text)
    : role = LlmRole.user,
      toolCalls = const [],
      toolCallId = null,
      toolName = null;

  /// What the model said, with the tools it called, if any.
  const LlmMessage.assistant(this.text, {this.toolCalls = const []})
    : role = LlmRole.assistant,
      toolCallId = null,
      toolName = null;

  /// The result [text] of the tool call with the ID [toolCallId].
  ///
  /// Gemini and Ollama name the tool in a result. When [toolName] is not
  /// given it is taken from the assistant message that made the call.
  const LlmMessage.tool({
    required String this.toolCallId,
    required this.text,
    this.toolName,
  }) : role = LlmRole.tool,
       toolCalls = const [];

  /// Who the message is from.
  final LlmRole role;

  /// The text of the message; for a tool message, the result.
  final String text;

  /// The tools an assistant message called.
  final List<LlmToolCall> toolCalls;

  /// For a tool message, the ID of the call it answers.
  final String? toolCallId;

  /// For a tool message, the name of the tool that was called.
  final String? toolName;

  @override
  String toString() =>
      'LlmMessage(${role.name}: $text'
      '${toolCalls.isEmpty ? '' : ', toolCalls: $toolCalls'}'
      '${toolCallId == null ? '' : ', toolCallId: $toolCallId'})';
}

/// A tool call the model made.
class LlmToolCall {
  /// A call of the tool [name] with [arguments].
  const LlmToolCall({
    required this.id,
    required this.name,
    this.arguments = const {},
    this.providerData = const {},
  });

  /// The ID of the call; a tool result names it. Gemini and older Ollama
  /// versions send none, so one is made up (`call_0`, `call_1`, ...).
  final String id;

  /// The name of the tool.
  final String name;

  /// The arguments, decoded from JSON.
  final Map<String, Object?> arguments;

  /// Values the provider sent with the call and wants back when the call
  /// is sent again in an assistant message, such as Gemini's
  /// `thoughtSignature`. Empty for most calls.
  final Map<String, Object?> providerData;

  @override
  String toString() => 'LlmToolCall($id, $name, $arguments)';
}

/// A tool the model may call.
class LlmTool {
  /// A tool with a [name], a [description] and the JSON schema of its
  /// [parameters].
  const LlmTool({
    required this.name,
    this.description = '',
    this.parameters = const {'type': 'object', 'properties': {}},
  });

  /// The name the model calls the tool by.
  final String name;

  /// What the tool does, for the model.
  final String description;

  /// The JSON schema of the arguments, an object schema.
  final Map<String, Object?> parameters;
}

/// What to ask a model.
class LlmRequest {
  /// A request to [model] with the conversation so far in [messages].
  const LlmRequest({
    required this.model,
    required this.messages,
    this.tools = const [],
    this.temperature,
    this.maxTokens,
    this.extra = const {},
  });

  /// The model name, as the provider spells it.
  final String model;

  /// The conversation so far.
  final List<LlmMessage> messages;

  /// The tools the model may call.
  final List<LlmTool> tools;

  /// The sampling temperature; the provider's default when null.
  final double? temperature;

  /// The most tokens the reply may have; the provider's default when null.
  final int? maxTokens;

  /// Fields added to the top level of the request body after everything
  /// else, so they replace fields of the same name. For what only one
  /// provider has, such as `{'thinking': {...}}` or `{'tool_choice': ...}`.
  final Map<String, Object?> extra;
}

/// Why a reply ended.
enum LlmFinishReason {
  /// The model finished its reply.
  stop,

  /// The token limit was reached.
  length,

  /// The model called tools and waits for their results.
  toolCalls,

  /// The provider's safety filter stopped the reply.
  contentFilter,

  /// A reason this package has no name for; see [LlmDone.rawFinishReason].
  other,
}

/// One piece of a streamed reply.
sealed class LlmEvent {
  const LlmEvent();
}

/// The next piece of the reply's text.
final class LlmTextDelta extends LlmEvent {
  /// A piece of [text].
  const LlmTextDelta(this.text);

  /// The text to add.
  final String text;

  @override
  String toString() => 'LlmTextDelta($text)';
}

/// The next piece of the model's thinking, for models that show it.
final class LlmThinkingDelta extends LlmEvent {
  /// A piece of thinking [text].
  const LlmThinkingDelta(this.text);

  /// The text to add.
  final String text;

  @override
  String toString() => 'LlmThinkingDelta($text)';
}

/// The model started a tool call.
final class LlmToolCallStart extends LlmEvent {
  /// The start of the call [id] of the tool [name].
  const LlmToolCallStart(this.id, this.name);

  /// The ID of the call.
  final String id;

  /// The name of the tool.
  final String name;

  @override
  String toString() => 'LlmToolCallStart($id, $name)';
}

/// More of a tool call's arguments arrived.
final class LlmToolCallDelta extends LlmEvent {
  /// A piece [rawDelta] of the arguments of the call [id].
  const LlmToolCallDelta(this.id, this.argumentsSoFar, this.rawDelta);

  /// The ID of the call.
  final String id;

  /// The arguments received so far, read from the unfinished JSON: a
  /// string holds the text so far, and a key shows once its value started.
  /// A copy, so it stays as it is when more arrives.
  final Map<String, Object?> argumentsSoFar;

  /// The JSON text this event added.
  final String rawDelta;

  @override
  String toString() => 'LlmToolCallDelta($id, $argumentsSoFar)';
}

/// A tool call is complete.
final class LlmToolCallDone extends LlmEvent {
  /// The finished [toolCall].
  const LlmToolCallDone(this.toolCall);

  /// The call, to run and to send back in an assistant message.
  final LlmToolCall toolCall;

  /// The ID of the call.
  String get id => toolCall.id;

  /// The name of the tool.
  String get name => toolCall.name;

  /// The complete arguments.
  Map<String, Object?> get arguments => toolCall.arguments;

  @override
  String toString() => 'LlmToolCallDone($id, $name, $arguments)';
}

/// How many tokens the request used. Sent once, before [LlmDone], when the
/// provider reports it.
final class LlmUsage extends LlmEvent {
  /// A count of tokens.
  const LlmUsage({this.inputTokens, this.outputTokens});

  /// The tokens of the request, or null when not reported.
  final int? inputTokens;

  /// The tokens of the reply, thinking included, or null when not
  /// reported.
  final int? outputTokens;

  @override
  String toString() => 'LlmUsage(in: $inputTokens, out: $outputTokens)';
}

/// The reply is complete; the last event of a stream.
final class LlmDone extends LlmEvent {
  /// The end of a reply, for [finishReason].
  const LlmDone(this.finishReason, {this.rawFinishReason});

  /// Why the reply ended.
  final LlmFinishReason finishReason;

  /// The reason as the provider spelled it, such as `end_turn`, or null
  /// when it gave none.
  final String? rawFinishReason;

  @override
  String toString() => 'LlmDone(${finishReason.name})';
}

/// A whole reply, collected from a stream by `LlmProvider.complete`.
class LlmResponse {
  /// A reply.
  const LlmResponse({
    required this.text,
    this.thinking = '',
    this.toolCalls = const [],
    this.usage,
    required this.finishReason,
    this.rawFinishReason,
  });

  /// The text of the reply.
  final String text;

  /// The thinking the model showed, or an empty string.
  final String thinking;

  /// The tools the model called.
  final List<LlmToolCall> toolCalls;

  /// The tokens used, when the provider reported them.
  final LlmUsage? usage;

  /// Why the reply ended.
  final LlmFinishReason finishReason;

  /// The reason as the provider spelled it.
  final String? rawFinishReason;

  /// The reply as an assistant message, to add to the conversation before
  /// the tool results.
  LlmMessage get message => LlmMessage.assistant(text, toolCalls: toolCalls);
}

/// An error from a provider's API: a status that is not 2xx, an error
/// event in the middle of a stream, or a reply that could not be read.
class LlmException implements Exception {
  /// An error with [message].
  const LlmException(this.message, {this.statusCode, this.body});

  /// The provider's own message when it sent one, such as
  /// `Incorrect API key provided`.
  final String message;

  /// The HTTP status, or null for an error in the middle of a stream.
  final int? statusCode;

  /// The raw response body or event data the error came in.
  final String? body;

  @override
  String toString() =>
      'LlmException${statusCode == null ? '' : ' ($statusCode)'}: $message';
}
