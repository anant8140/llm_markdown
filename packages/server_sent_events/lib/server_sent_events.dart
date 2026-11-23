/// A server-sent events (SSE) client: [connectSse] opens an event stream
/// over HTTP, with any method, headers and body, and gives [SseEvent]s.
/// [SseDecoder] decodes a byte stream you already have.
library;

export 'src/client.dart' show SseEventStream, SseReconnect, connectSse;
export 'src/decoder.dart' show SseDecoder;
export 'src/event.dart' show SseEvent, SseException;
