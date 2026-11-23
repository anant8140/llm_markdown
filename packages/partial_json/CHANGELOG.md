## 0.2.0

* `onComplete(path, value)`: told when each value is finished.
* `PartialJsonItemDecoder`: each item of a list, converted, as soon as it is
  finished.
* `PartialJsonValueDecoder` and `jsonPathMatches`: values by path, with
  `'*'` for any key or index.
* `snapshot()` and `PartialJsonDecoder(snapshots: true)`: copies that later
  pieces leave alone.
* `changedPaths`: what the last piece started, changed or finished.
* `repair`: single quotes, keys without quotes, comments, `True`/`False`/
  `None`; and `repairJson`, which gives valid JSON.
* `PartialJsonDocumentsDecoder`: several documents in one stream, such as
  JSON Lines.
* `ToolArgumentsParser`: the arguments of streamed tool calls, per call.
* `partialStrings` and `partialNumbers`: show only finished values.
* `bigInts`: large whole numbers stay exact, on the web too.
* Errors name the line and column.

## 0.1.0

* `PartialJsonParser`: the value so far of JSON that arrives in pieces,
  read incrementally, with `isComplete`, `pendingPath` and `close()`.
* `parsePartialJson` for a cut-off document and `PartialJsonDecoder` for a
  stream.
* Lenient by default: text around the document and trailing commas are
  allowed; strict mode accepts only JSON.
