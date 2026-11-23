/// Parses JSON that is still arriving: [PartialJsonParser] gives the value
/// so far after every piece, [parsePartialJson] parses a cut-off document
/// and [PartialJsonDecoder] does it for a stream.
library;

export 'src/parser.dart'
    show PartialJsonDecoder, PartialJsonParser, parsePartialJson;
