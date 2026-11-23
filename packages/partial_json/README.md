# partial_json

Parse JSON while it streams in. A cut-off JSON document gives the objects,
lists and strings so far, so an app can show an AI model's structured
output, or the arguments of a tool call, as they are written.

```dart
import 'package:partial_json/partial_json.dart';

parsePartialJson('{"title": "Stre');               // {title: Stre}
parsePartialJson('{"title": "Streaming", "tags": ["a", "b');
                                                   // {title: Streaming, tags: [a, b]}
```

- **Every prefix parses:** strings show the text so far, numbers the digits
  so far, `t`, `f` and `n` already show `true`, `false` and `null`, and a
  key shows once its value has started. Escapes and emoji cut in half wait
  for their other half.
- **Incremental:** `PartialJsonParser` reads each piece once, so a long
  reply costs no more than parsing it whole. A 157 KB document in 20,000
  pieces took 26 ms, against about 50 s for parsing the text so far again
  after every piece.
- **Knows what is finished:** `pendingPath` is the path of the value still
  being written, like `['items', 2, 'title']`; everything else is final.
- **Made for model output:** by default text around the JSON is skipped, so
  ```` ```json ... ``` ```` fences and "Here it is:" lead-ins parse, and a
  trailing comma is allowed. JSON that is wrong, not just unfinished, throws
  a `FormatException` with the offset.

Pure Dart, no dependencies; Flutter, server and web.

## Usage

```dart
final parser = PartialJsonParser();

await for (final chunk in modelStream) {
  parser.add(chunk);
  if (parser.hasValue) render(parser.value);
}
final result = parser.close(); // throws if the JSON ended in the middle
```

Or as a stream transformer:

```dart
textStream
    .transform(const PartialJsonDecoder())
    .listen((value) => setState(() => _recipe = value as Map));
```

The maps and lists the parser gives are its own and are updated in place as
more arrives; copy them to keep a snapshot.

### What is finished

```dart
parser.add('{"items": [{"title": "Pasta"}, {"title": "Sal');
parser.pendingPath; // ['items', 1, 'title']
// items[0] is final; items[1].title is still being written
```

### Strict mode

`PartialJsonParser(lenient: false)` accepts only JSON: nothing around the
document, no trailing comma, and any value at the root, including a
number, which completes at `close()`.

## With other packages

- [server_sent_events](https://pub.dev/packages/server_sent_events) reads
  the streams of AI APIs.
- [llm_markdown](https://pub.dev/packages/llm_markdown) shows their
  Markdown replies as they stream in.

## License

MIT
