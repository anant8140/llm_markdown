## 0.1.0

* `PartialJsonParser`: the value so far of JSON that arrives in pieces,
  read incrementally, with `isComplete`, `pendingPath` and `close()`.
* `parsePartialJson` for a cut-off document and `PartialJsonDecoder` for a
  stream.
* Lenient by default: text around the document and trailing commas are
  allowed; strict mode accepts only JSON.
