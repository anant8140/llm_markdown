import 'dart:collection';

import 'package:markdown/markdown.dart' as md;

import 'block_splitter.dart';
import 'healer.dart';
import 'math.dart';
import 'syntaxes.dart';

// Footnotes need the whole document (numbering, the list at the end), so
// once a definition shows up we stop splitting. Rare in practice.
final RegExp _footnoteDefinition = RegExp(
  r'^ {0,3}\[\^[^\]\n]+\]:',
  multiLine: true,
);

/// A finished block: its text no longer changes, so it is parsed once.
class FrozenBlock {
  /// Creates a frozen block.
  FrozenBlock(this.id, this.source, this.nodes);

  /// A number that stays the same as long as the block does, for caching
  /// what is built from it.
  final int id;

  /// The Markdown text of the block.
  final String source;

  /// The parsed block.
  final List<md.Node> nodes;
}

/// Parses Markdown that grows at the end, such as a streamed AI reply.
///
/// Finished blocks are parsed once and kept in [frozenBlocks]; only the
/// last, open block is parsed again on every [update], after its unfinished
/// syntax is closed by `healIncompleteMarkdown`. Once complete, the blocks
/// match a parse of the whole text.
class IncrementalMarkdownParser {
  /// Creates a parser for the extensions in [syntax].
  IncrementalMarkdownParser({this.syntax = const MarkdownSyntax()}) {
    _document = _newDocument();
  }

  /// The Markdown extensions that are recognized.
  final MarkdownSyntax syntax;

  late md.Document _document;
  final List<FrozenBlock> _frozen = [];
  late final UnmodifiableListView<FrozenBlock> _frozenView =
      UnmodifiableListView(_frozen);
  int _openStart = 0;
  int _nextId = 0;
  String _text = '';
  bool _complete = false;
  bool _started = false;
  bool _wholeDocument = false;
  List<md.Node> _openNodes = const [];

  /// The finished blocks, in order.
  List<FrozenBlock> get frozenBlocks => _frozenView;

  /// The parsed open block, with its unfinished syntax closed.
  List<md.Node> get openNodes => _openNodes;

  /// The text of the last [update].
  String get text => _text;

  /// Whether the last [update] was the whole text.
  bool get isComplete => _complete;

  md.Document _newDocument() => newMarkdownDocument(syntax);

  /// Forgets everything parsed so far.
  void reset() {
    _document = _newDocument();
    _frozen.clear();
    _openStart = 0;
    _text = '';
    _complete = false;
    _started = false;
    _wholeDocument = false;
    _openNodes = const [];
  }

  /// Parses [text], reusing the blocks of the previous text when [text]
  /// starts with it. Returns whether anything changed.
  bool update(String text, {required bool complete}) {
    if (_started && text == _text && complete == _complete) return false;
    if (!text.startsWith(_text) || (_complete && !complete)) reset();
    _started = true;
    _text = text;
    _complete = complete;

    if (_wholeDocument || _footnoteDefinition.hasMatch(text)) {
      _parseWhole(text, complete);
      return true;
    }

    var newReferences = false;
    var start = _openStart;
    for (final boundary in findBlockBoundaries(
      text,
      start,
      complete: complete,
      dollarMath: syntax.dollarMath,
    )) {
      newReferences |= _freeze(text.substring(start, boundary));
      start = boundary;
    }
    if (complete && start < text.length) {
      newReferences |= _freeze(text.substring(start));
      start = text.length;
    }
    _openStart = start;
    if (newReferences) _parseFrozenAgain();

    final open = text.substring(_openStart);
    if (isBlank(open)) {
      _openNodes = const [];
    } else {
      final document = _newDocument()
        ..linkReferences.addAll(_document.linkReferences);
      _openNodes = document.parse(
        healIncompleteMarkdown(open, dollarMath: syntax.dollarMath),
      );
    }
    return true;
  }

  void _parseWhole(String text, bool complete) {
    _wholeDocument = true;
    _frozen.clear();
    _document = _newDocument();
    if (complete) {
      _frozen.add(FrozenBlock(_nextId++, text, _document.parse(text)));
      _openStart = text.length;
      _openNodes = const [];
    } else {
      _openStart = 0;
      _openNodes = _document.parse(
        healIncompleteMarkdown(text, dollarMath: syntax.dollarMath),
      );
    }
  }

  bool _freeze(String source) {
    if (isBlank(source)) return false;
    final before = _document.linkReferences.length;
    _frozen.add(FrozenBlock(_nextId++, source, _document.parse(source)));
    return _document.linkReferences.length != before && _frozen.length > 1;
  }

  void _parseFrozenAgain() {
    for (var i = 0; i < _frozen.length; i++) {
      final source = _frozen[i].source;
      _frozen[i] = FrozenBlock(_nextId++, source, _document.parse(source));
    }
  }
}
