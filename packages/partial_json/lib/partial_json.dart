/// Parses JSON that is still arriving: [PartialJsonParser] gives the value
/// so far after every piece, [parsePartialJson] parses a cut-off document,
/// and the stream transformers do it for streams: of one document, of the
/// items of a list, or of several documents. [ToolArgumentsParser] follows
/// the arguments of streamed tool calls, and [repairJson] fixes common
/// mistakes in model JSON.
library;

export 'src/parser.dart' show PartialJsonParser, parsePartialJson, repairJson;
export 'src/schema.dart'
    show JsonSchemaIssue, checkJsonSchema, checkPartialJson;
export 'src/streams.dart'
    show
        PartialJsonDecoder,
        PartialJsonDocument,
        PartialJsonDocumentsDecoder,
        PartialJsonItemDecoder,
        PartialJsonValueDecoder,
        ToolArgumentsParser,
        jsonPathMatches;
