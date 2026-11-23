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

### Each item as soon as it is finished

```dart
textStream
    .transform(PartialJsonItemDecoder(
      path: ['recipes'],
      convert: (json) => Recipe.fromJson(json as Map<String, dynamic>),
    ))
    .listen((recipe) => setState(() => recipes.add(recipe)));
```

`onComplete` gives the same for every value: `PartialJsonParser(onComplete:
(path, value) => ...)`. `changedPaths` lists what the last piece touched.

### Snapshots

The parser's maps and lists change in place. For state that is compared by
identity (Riverpod, Bloc), take `parser.snapshot()` or use
`PartialJsonDecoder(snapshots: true)`.

### Repairing model JSON

Models sometimes write single quotes, keys without quotes, comments or
Python's `True`, `False` and `None`. `PartialJsonParser(repair: true)` reads
them anyway, and `repairJson` gives valid JSON:

```dart
repairJson("{name: 'Ann', tags: ['a',], ok: True} // done");
// {"name":"Ann","tags":["a"],"ok":true}
```

It is off by default, since it accepts text that isn't JSON.

### Several documents and tool calls

`PartialJsonDocumentsDecoder` reads documents one after another, such as
JSON Lines, giving each as it grows and once more when it is finished.

`ToolArgumentsParser` follows the arguments of streamed tool calls, which
arrive as JSON pieces per call (OpenAI's `function.arguments`, Anthropic's
`input_json_delta`):

```dart
final args = ToolArgumentsParser();
args.add(call.id, delta); // the arguments so far, per call
args.close(call.id);      // the finished arguments
```

### Settings

| | default | |
| --- | --- | --- |
| `lenient` | `true` | skip text around the document, allow trailing commas |
| `repair` | `false` | read common mistakes in model JSON |
| `partialStrings` | `true` | show a string while it is written |
| `partialNumbers` | `true` | show a number, `true`, `false`, `null` while written |
| `bigInts` | `false` | large whole numbers as exact `BigInt`s |
| `onComplete` | – | told when each value is finished |

Errors are `FormatException`s naming the line and column, with the offset.

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
