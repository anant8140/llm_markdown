import 'dart:async';
import 'dart:convert';

import 'event.dart';

/// Decodes the bytes of an event stream into events, as the HTML standard
/// describes: `\n`, `\r\n` and `\r` line ends, comments, a leading
/// byte-order mark, `id` that lasts across events and `retry`.
class SseDecoder extends StreamTransformerBase<List<int>, SseEvent> {
  /// A decoder; [lastEventId] is the ID to start from, as after a
  /// reconnect.
  const SseDecoder({
    this.lastEventId,
    this.onRetry,
    this.onLastEventId,
    this.onLine,
    this.maxEventSize,
  });

  /// The last event ID before the first event.
  final String? lastEventId;

  /// Called when the server sets the reconnection time with `retry:`,
  /// with or without an event.
  final void Function(Duration retry)? onRetry;

  /// Called when an event block ends that changes the last event ID,
  /// whether it carries data or not.
  final void Function(String? id)? onLastEventId;

  /// Called with every line as it arrives, comments and blank lines
  /// included, for logging and debugging.
  final void Function(String line)? onLine;

  /// The most characters one event (its lines together) may have; a larger
  /// one ends the stream with an [SseException], so a broken server can't
  /// fill the memory. No limit when null.
  final int? maxEventSize;

  @override
  Stream<SseEvent> bind(Stream<List<int>> stream) =>
      Stream<SseEvent>.eventTransformed(
        stream,
        (sink) => _DecoderSink(sink, this),
      );
}

class _DecoderSink implements EventSink<List<int>> {
  _DecoderSink(this._out, this._decoder)
    : _id = _decoder.lastEventId,
      _shownId = _decoder.lastEventId {
    _text = utf8.decoder.startChunkedConversion(
      _LineSink((text) => _lines(text)),
    );
  }

  final EventSink<SseEvent> _out;
  final SseDecoder _decoder;
  late final ByteConversionSink _text;

  String? _id;
  // the last event ID as last reported to onLastEventId
  String? _shownId;
  String? _type;
  final _data = StringBuffer();
  var _hasData = false;
  // characters of the event being read, for maxEventSize
  var _size = 0;
  var _failed = false;
  Duration? _retry;

  // the start of a line that has not ended yet
  var _pending = '';
  // the last chunk ended with \r: a \n starting the next one belongs to it
  var _afterCr = false;
  var _first = true;

  @override
  void add(List<int> bytes) {
    if (!_failed) _text.add(bytes);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _out.addError(error, stackTrace);

  @override
  void close() {
    if (_failed) return;
    _text.close();
    // an unfinished event at the end is dropped, as the standard says
    if (!_failed) _out.close();
  }

  void _lines(String text) {
    if (_first && text.isNotEmpty) {
      _first = false;
      if (text.codeUnitAt(0) == 0xFEFF) text = text.substring(1);
    }
    var start = 0;
    if (_afterCr && text.isNotEmpty && text.codeUnitAt(0) == 0x0A) start = 1;
    _afterCr = false;
    for (var i = start; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit != 0x0A && unit != 0x0D) continue;
      final line = _pending + text.substring(start, i);
      _pending = '';
      _line(line);
      if (unit == 0x0D) {
        if (i + 1 < text.length) {
          if (text.codeUnitAt(i + 1) == 0x0A) i++;
        } else {
          _afterCr = true;
        }
      }
      start = i + 1;
    }
    _pending += text.substring(start);
    _check(_pending.length);
  }

  // Ends the stream when the event being read is too large.
  bool _check(int more) {
    final limit = _decoder.maxEventSize;
    if (_failed || limit == null || _size + more <= limit) return _failed;
    _failed = true;
    _out.addError(SseException('An event is larger than $limit characters'));
    _out.close();
    return true;
  }

  void _line(String line) {
    if (_failed) return;
    _decoder.onLine?.call(line);
    if (line.isEmpty) {
      _size = 0;
      _dispatch();
      return;
    }
    if (line.codeUnitAt(0) == 0x3A) return; // a comment
    if (_check(line.length)) return;
    _size += line.length;
    final colon = line.indexOf(':');
    final String field;
    var value = '';
    if (colon < 0) {
      field = line;
    } else {
      field = line.substring(0, colon);
      value = line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);
    }
    switch (field) {
      case 'event':
        _type = value;
      case 'data':
        if (_hasData) _data.write('\n');
        _data.write(value);
        _hasData = true;
      case 'id':
        if (!value.contains('\u0000')) _id = value.isEmpty ? null : value;
      case 'retry':
        if (value.isNotEmpty && value.codeUnits.every(_isDigit)) {
          final retry = Duration(milliseconds: int.parse(value));
          _retry = retry;
          _decoder.onRetry?.call(retry);
        }
    }
  }

  static bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;

  void _dispatch() {
    final retry = _retry;
    _retry = null;
    if (_id != _shownId) {
      _shownId = _id;
      _decoder.onLastEventId?.call(_id);
    }
    if (!_hasData) {
      _type = null;
      return;
    }
    final type = _type;
    _out.add(
      SseEvent(
        _data.toString(),
        event: type == null || type.isEmpty ? 'message' : type,
        id: _id,
        retry: retry,
      ),
    );
    _data.clear();
    _hasData = false;
    _type = null;
  }
}

class _LineSink implements Sink<String> {
  _LineSink(this._onText);
  final void Function(String text) _onText;
  @override
  void add(String data) => _onText(data);
  @override
  void close() {}
}
