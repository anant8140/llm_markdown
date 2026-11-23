## 0.1.1

* Checked against a real Ollama server, through its own API and its
  OpenAI-compatible endpoint; the README says what was checked.
  `tool/live_ollama.dart` runs the checks. No code change.

## 0.1.0

* First release: `OpenAIProvider` (Chat Completions and compatible
  servers), `AnthropicProvider` (Messages), `GeminiProvider`
  (`streamGenerateContent`) and `OllamaProvider` (`/api/chat`).
* `stream` gives typed events: text, thinking, tool calls with their
  arguments as they are written, usage and the finish reason.
* `text` gives the text only; `complete` collects the whole reply.
* API errors are `LlmException`s with the status, the provider's message
  and the raw body.
* Cancelling the subscription aborts the HTTP request.
