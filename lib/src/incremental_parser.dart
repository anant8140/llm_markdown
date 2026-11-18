import 'dart:collection';

import 'package:markdown/markdown.dart' as md;

import 'block_splitter.dart';
import 'healer.dart';
import 'math.dart';

// Footnotes need the whole document (numbering, the list at the end), so
// once a definition shows up we stop splitting. Rare in practice.
final RegExp _footnoteDefinition = RegExp(
  r'^ {0,3}\[\^[^\]\n]+\]:',
  multiLine: true,
);

class FrozenBlock {
  FrozenBlock(this.id, this.source, this.nodes);

  final int id;

  final String source;

  final List<md.Node> nodes;
}

class IncrementalMarkdownParser {
  IncrementalMarkdownParser() {
    _document = _newDocument();
  }

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

  List<FrozenBlock> get frozenBlocks => _frozenView;

  List<md.Node> get openNodes => _openNodes;

  String get text => _text;

  bool get isComplete => _complete;

  static md.Document _newDocument() => newMarkdownDocument();

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
      _openNodes = document.parse(healIncompleteMarkdown(open));
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
      _openNodes = _document.parse(healIncompleteMarkdown(text));
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
