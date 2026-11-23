## 0.1.0

First release.

- `StructuredStreamController`: takes the pieces of a JSON document
  (`add`, `close`, `reset`, `addStream`), with `value`, `data`,
  `isComplete`, `pendingPath` and `error`, and a `repair` option.
- `StructuredValue`: reads the document so far without null or type
  errors, with `exists`, `isPending`, `isDone` and `isAwaited`.
- `StructuredBuilder`: rebuilds from a controller or a `Stream<String>`,
  with an `errorBuilder`.
- Widgets: `StructuredText` (plain or Markdown), `StructuredList`,
  `StructuredFields`, `StructuredCard` and `StructuredAuto`, plus
  `StructuredCursor` and `StructuredPlaceholder`.
- `StructuredStyle` and `StructuredTheme` for the look.
