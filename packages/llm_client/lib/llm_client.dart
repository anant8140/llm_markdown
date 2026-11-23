/// One API for streaming chat with OpenAI, Anthropic, Gemini and Ollama.
///
/// Make a provider, such as [OpenAIProvider], and call
/// [LlmProvider.stream] with an [LlmRequest] for typed [LlmEvent]s,
/// [LlmProvider.text] for the text only, or [LlmProvider.complete] for the
/// whole reply as an [LlmResponse].
library;

export 'src/anthropic.dart' show AnthropicProvider;
export 'src/gemini.dart' show GeminiProvider;
export 'src/ollama.dart' show OllamaProvider;
export 'src/openai.dart' show OpenAIProvider;
export 'src/provider.dart' show LlmProvider;
export 'src/types.dart';
