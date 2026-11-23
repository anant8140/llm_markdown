/// A server-sent events (SSE) client: [connectSse] and [SseClient] open an
/// event stream over HTTP, with any method, headers and body, and give
/// [SseEvent]s. [SseDecoder] decodes a byte stream you already have, and
/// [SseEncoder] writes events for a server.
///
/// For tests, `package:server_sent_events/testing.dart` has a fake client.
library;

export 'src/client.dart'
    show SseClient, SseEventStream, SseReconnect, SseStatus, connectSse;
export 'src/decoder.dart' show SseDecoder;
export 'src/encoder.dart' show SseEncoder, encodeSseComment, encodeSseEvent;
export 'src/event.dart' show SseEvent, SseException;
