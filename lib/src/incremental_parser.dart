import 'dart:collection';

import 'package:markdown/markdown.dart' as md;

import 'block_splitter.dart';
import 'healer.dart';

/// A part of the document whose source will not change any more.
class FrozenBlock {
  /// Creates a frozen block.
  FrozenBlock(this.id, this.source, this.nodes);

  /// A number that is unique within one parser and changes whenever the
  /// block has to be shown differently.
  final int id;

  /// The Markdown source of this block.
  final String source;

  /// The parsed top-level nodes of this block.
  final List<md.Node> nodes;
}

/// Parses Markdown that grows at its end, doing work only for the new part.
///
/// Text is cut into blocks at places where the part before the cut can no
/// longer change (see [findBlockBoundaries]). Those blocks are parsed once
/// and kept. Only the last, open block is parsed again on each update,
/// after [healIncompleteMarkdown] has tidied its unfinished end.
class IncrementalMarkdownParser {
  /// Creates a parser for GitHub-flavored Markdown.
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
  List<md.Node> _openNodes = const [];

  /// The blocks that will not change any more, in document order.
  List<FrozenBlock> get frozenBlocks => _frozenView;

  /// The nodes of the open block, parsed from its healed source.
  List<md.Node> get openNodes => _openNodes;

  /// The text given to the last [update].
  String get text => _text;

  /// Whether the last [update] said the text was complete.
  bool get isComplete => _complete;

  static md.Document _newDocument() => md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  );

  /// Forgets everything parsed so far.
  void reset() {
    _document = _newDocument();
    _frozen.clear();
    _openStart = 0;
    _text = '';
    _complete = false;
    _started = false;
    _openNodes = const [];
  }

  /// Parses [text], which usually is the previous text plus more at its end.
  ///
  /// When [text] does not start with the previous text, everything is parsed
  /// again. When [complete] is true the open block is parsed as it is,
  /// without healing, and frozen. Returns whether anything changed.
  bool update(String text, {required bool complete}) {
    if (_started && text == _text && complete == _complete) return false;
    if (!text.startsWith(_text) || (_complete && !complete)) reset();
    _started = true;
    _text = text;
    _complete = complete;

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
    if (open.trim().isEmpty) {
      _openNodes = const [];
    } else {
      final document = _newDocument()
        ..linkReferences.addAll(_document.linkReferences);
      _openNodes = document.parse(healIncompleteMarkdown(open));
    }
    return true;
  }

  /// Freezes [source] and returns whether it defined new link references
  /// that earlier blocks may use.
  bool _freeze(String source) {
    if (source.trim().isEmpty) return false;
    final before = _document.linkReferences.length;
    _frozen.add(FrozenBlock(_nextId++, source, _document.parse(source)));
    return _document.linkReferences.length != before && _frozen.length > 1;
  }

  /// A reference such as `[docs]: https://...` also applies to links above
  /// it, so the earlier blocks are parsed again with the new references.
  void _parseFrozenAgain() {
    for (var i = 0; i < _frozen.length; i++) {
      final source = _frozen[i].source;
      _frozen[i] = FrozenBlock(_nextId++, source, _document.parse(source));
    }
  }
}
