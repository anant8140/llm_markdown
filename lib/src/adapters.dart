import 'dart:async';
import 'dart:convert';

import 'package:llm_markdown_parser/llm_markdown_parser.dart';

import 'controller.dart';

// Null for a line that isn't a JSON object: a keep-alive such as "ping",
// or an event cut short because the connection dropped. Neither is a reason
// to throw away the reply so far.
Map<String, dynamic>? _json(String data) {
  try {
    final json = jsonDecode(data);
    return json is Map<String, dynamic> ? json : null;
  } on FormatException {
    return null;
  }
}

/// Feeds the event streams of common model APIs into a controller.
extension ModelStreams on StreamingMarkdownController {
  /// Reads an OpenAI-style streaming response body and completes the reply.
  ///
  /// Handles Chat Completions chunks (`choices[0].delta.content`, and the
  /// `reasoning_content` / `reasoning` fields some providers add) and the
  /// Responses API events (`response.output_text.delta` and reasoning
  /// summaries). Reasoning goes to [appendThinking].
  ///
  /// Tool calls (`tool_calls` deltas, and function and web search calls of
  /// the Responses API) go to [toolCalls], and `url_citation` annotations to
  /// [sources].
  Future<void> addOpenAIStream(Stream<List<int>> bytes) {
    // Chat Completions names a tool call by its id once, then by its index
    final callIds = <Object?, String>{};
    return _feed(bytes, (event) {
      if (event.data == '[DONE]') return true;
      final json = _json(event.data);
      if (json == null) return false;
      final error = json['error'];
      if (error != null) throw ModelStreamError(_message(error));
      switch (json['type']) {
        case 'response.output_item.added':
          final item = json['item'];
          if (item is Map && item['type'] != 'message') {
            final type = '${item['type']}';
            if (type.endsWith('_call') && item['id'] != null) {
              startToolCall(
                '${item['id']}',
                item['name'] is String
                    ? item['name'] as String
                    : type.substring(0, type.length - 5),
              );
            }
          }
        case 'response.function_call_arguments.delta':
          final delta = json['delta'];
          if (delta is String) {
            addToolCallArguments('${json['item_id']}', delta);
          }
        case 'response.output_item.done':
          final item = json['item'];
          if (item is Map && item['id'] != null) {
            final id = '${item['id']}';
            // arguments that came only whole, without deltas
            final arguments = item['arguments'];
            final known = toolCalls.where((call) => call.id == id);
            if (arguments is String &&
                known.isNotEmpty &&
                known.first.arguments.isEmpty) {
              addToolCallArguments(id, arguments);
            }
            finishToolCall(id);
          }
        case 'response.output_text.annotation.added':
          _addUrlCitation(json['annotation']);
        case 'response.output_text.delta':
          _add(json['delta']);
        case 'response.reasoning_summary_text.delta' ||
            'response.reasoning_text.delta':
          _addThinking(json['delta']);
        case 'response.completed':
          return true;
        case 'response.failed' || 'error':
          throw ModelStreamError(_message(json['response'] ?? json));
      }
      final choices = json['choices'];
      if (choices is List && choices.isNotEmpty && choices.first is Map) {
        final choice = choices.first as Map;
        final delta = choice['delta'];
        if (delta is Map) {
          _addThinking(delta['reasoning_content'] ?? delta['reasoning']);
          _add(delta['content']);
          // a refusal comes in its own field, and is the whole answer
          _add(delta['refusal']);
          final calls = delta['tool_calls'];
          if (calls is List) {
            for (final call in calls.whereType<Map>()) {
              final key = call['index'] ?? call['id'];
              final id = call['id'] is String
                  ? callIds[key] = call['id'] as String
                  : callIds[key] ??= 'call_$key';
              final function = call['function'];
              if (function is! Map) continue;
              final name = function['name'];
              startToolCall(id, name is String ? name : '');
              final arguments = function['arguments'];
              if (arguments is String) addToolCallArguments(id, arguments);
            }
          }
          final notes = delta['annotations'];
          if (notes is List) notes.forEach(_addUrlCitation);
        }
        // the calls are all sent once the choice has finished
        if (choice['finish_reason'] != null) {
          callIds.values.forEach(finishToolCall);
        }
      }
      return false;
    });
  }

  /// Reads an Anthropic Messages API streaming response body and completes
  /// the reply. Text deltas are appended, thinking deltas go to
  /// [appendThinking].
  ///
  /// Tool use (your tools and server tools such as web search) goes to
  /// [toolCalls]. Citations go to [sources], and `[n]` is put after the
  /// text they support.
  Future<void> addAnthropicStream(Stream<List<int>> bytes) {
    // by content block index: the tool call it is, or the citations to put
    // after its text
    final tools = <Object?, String>{};
    final cited = <Object?, List<int>>{};
    // the blocks that wrote text: a citation on a block without text has
    // no words of its own to mark
    final wrote = <Object?>{};
    // White space at the end of the text so far is held back, so a `[n]`
    // that follows can still go before it, next to the cited words.
    var held = '';
    void addText(Object? text) {
      if (text is! String || text.isEmpty) return;
      final all = held + text;
      final end = all.trimRight().length;
      held = all.substring(end);
      _add(all.substring(0, end));
    }

    void release() {
      _add(held);
      held = '';
    }

    return _feed(bytes, (event) {
      final json = _json(event.data);
      if (json == null) return false;
      final index = json['index'];
      switch (json['type']) {
        case 'content_block_start':
          final block = json['content_block'];
          if (block is Map &&
              (block['type'] == 'tool_use' ||
                  block['type'] == 'server_tool_use' ||
                  block['type'] == 'mcp_tool_use')) {
            final id = '${block['id'] ?? 'tool_$index'}';
            tools[index] = id;
            startToolCall(id, '${block['name'] ?? ''}');
          }
        case 'content_block_delta':
          final delta = json['delta'];
          if (delta is Map) {
            switch (delta['type']) {
              case 'text_delta':
                final words = delta['text'];
                if (words is String && words.trim().isNotEmpty) {
                  wrote.add(index);
                }
                addText(words);
              case 'thinking_delta':
                _addThinking(delta['thinking']);
              case 'input_json_delta':
                final id = tools[index];
                final part = delta['partial_json'];
                if (id != null && part is String) {
                  addToolCallArguments(id, part);
                }
              case 'citations_delta':
                final citation = delta['citation'];
                if (citation is Map) {
                  final number = addSource(
                    MarkdownSource(
                      // search results name their origin "source"
                      url: _string(citation['url'] ?? citation['source']),
                      title: _string(
                        citation['title'] ?? citation['document_title'],
                      ),
                      citedText: _string(citation['cited_text']),
                    ),
                  );
                  final numbers = cited.putIfAbsent(index, () => []);
                  if (!numbers.contains(number)) numbers.add(number);
                }
            }
          }
        case 'content_block_stop':
          final id = tools.remove(index);
          if (id != null) finishToolCall(id);
          final numbers = cited.remove(index);
          if (numbers != null &&
              wrote.remove(index) &&
              !isComplete &&
              _canCite(text)) {
            append(' ${numbers.map((n) => '[$n]').join()}');
          }
        case 'message_stop':
          release();
          return true;
        case 'error':
          throw ModelStreamError(_message(json['error'] ?? json));
      }
      return false;
    });
  }

  /// Reads a Gemini API streaming response body and completes the reply.
  ///
  /// Both forms of `streamGenerateContent` are read: with `?alt=sse`, as the
  /// Gemini docs use for streaming, and without it, where the body is one
  /// JSON array that arrives piece by piece. Parts marked `thought: true` go
  /// to [appendThinking], the other text parts are appended.
  ///
  /// Function calls go to [toolCalls], and the pages of Google Search
  /// grounding to [sources].
  Future<void> addGeminiStream(Stream<List<int>> bytes) {
    var calls = 0;
    return _feedEvents(bytes, _geminiEvents, (data) {
      final json = _json(data);
      if (json == null) return false;
      final error = json['error'];
      if (error != null) throw ModelStreamError(_message(error));
      final feedback = json['promptFeedback'];
      if (feedback is Map && feedback['blockReason'] != null) {
        throw ModelStreamError('Blocked: ${feedback['blockReason']}');
      }
      final candidates = json['candidates'];
      if (candidates is! List || candidates.isEmpty) return false;
      final candidate = candidates.first;
      if (candidate is! Map) return false;
      final grounding = candidate['groundingMetadata'];
      final chunks = grounding is Map ? grounding['groundingChunks'] : null;
      if (chunks is List) {
        for (final chunk in chunks.whereType<Map>()) {
          final page = chunk['web'] ?? chunk['retrievedContext'];
          if (page is Map) {
            addSource(
              MarkdownSource(
                url: _string(page['uri']),
                title: _string(page['title']),
              ),
            );
          }
        }
      }
      final content = candidate['content'];
      final parts = content is Map ? content['parts'] : null;
      if (parts is List) {
        for (final part in parts) {
          if (part is! Map) continue;
          final call = part['functionCall'];
          if (call is Map) {
            final id = '${call['id'] ?? 'call_${calls++}'}';
            startToolCall(id, '${call['name'] ?? ''}');
            if (call['args'] != null) {
              addToolCallArguments(id, jsonEncode(call['args']));
            }
            finishToolCall(id);
          } else if (part['thought'] == true) {
            _addThinking(part['text']);
          } else {
            _add(part['text']);
          }
        }
      }
      return false;
    });
  }

  /// Reads an Ollama `/api/chat` or `/api/generate` streaming response body
  /// (one JSON object per line) and completes the reply. `thinking` goes to
  /// [appendThinking], and tool calls to [toolCalls].
  ///
  /// Ollama's OpenAI-compatible `/v1/chat/completions` endpoint is read with
  /// [addOpenAIStream] instead.
  Future<void> addOllamaStream(Stream<List<int>> bytes) {
    var calls = 0;
    return _feedEvents(bytes, _jsonLines, (data) {
      final json = _json(data);
      if (json == null) return false;
      final error = json['error'];
      if (error != null) throw ModelStreamError(_message(error));
      final message = json['message'];
      if (message is Map) {
        _addThinking(message['thinking']);
        _add(message['content']);
        final toolCalls = message['tool_calls'];
        if (toolCalls is List) {
          for (final call in toolCalls.whereType<Map>()) {
            final function = call['function'];
            if (function is! Map) continue;
            final id = '${call['id'] ?? 'call_${calls++}'}';
            startToolCall(id, '${function['name'] ?? ''}');
            final arguments = function['arguments'];
            if (arguments != null) {
              addToolCallArguments(
                id,
                arguments is String ? arguments : jsonEncode(arguments),
              );
            }
            finishToolCall(id);
          }
        }
      } else {
        _addThinking(json['thinking']);
        _add(json['response']);
      }
      return json['done'] == true;
    });
  }

  void _addUrlCitation(Object? annotation) {
    if (annotation is! Map) return;
    // Chat Completions nests it, the Responses API doesn't
    final citation = annotation['url_citation'] ?? annotation;
    if (citation is! Map || annotation['type'] != 'url_citation') return;
    addSource(
      MarkdownSource(
        url: _string(citation['url']),
        title: _string(citation['title']),
      ),
    );
  }

  // Whether `[n]` can go at the end of [text]: not inside a code block,
  // where it would show as code, nor in a table row or on an empty line.
  static bool _canCite(String text) {
    if (text.trim().isEmpty || text.endsWith('\n')) return false;
    final fences = RegExp(r'^ {0,3}(```|~~~)', multiLine: true);
    if (fences.allMatches(text).length.isOdd) return false;
    final lastLine = text.substring(text.lastIndexOf('\n') + 1).trimLeft();
    // a closing fence with words after it no longer closes the block
    return !lastLine.startsWith('|') &&
        !lastLine.startsWith('```') &&
        !lastLine.startsWith('~~~');
  }

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  void _add(Object? text) {
    if (text is String && text.isNotEmpty) append(text);
  }

  void _addThinking(Object? text) {
    if (text is String && text.isNotEmpty) appendThinking(text);
  }

  static String _message(Object? error) {
    if (error is Map) {
      final message = error['message'] ?? error['error'];
      if (message != null) return _message(message);
    }
    return '$error';
  }

  // Calls [onEvent] for each event until it returns true or the stream ends,
  // then completes. Errors end the reply with completeWithError and are
  // rethrown. Stops quietly if the controller is reset meanwhile.
  Future<void> _feed(
    Stream<List<int>> bytes,
    bool Function(ServerSentEvent event) onEvent,
  ) => _feedEvents(bytes, serverSentEvents, onEvent);

  Future<void> _feedEvents<T>(
    Stream<List<int>> bytes,
    Stream<T> Function(Stream<List<int>> bytes) decode,
    bool Function(T event) onEvent,
  ) {
    // already stopped, for example while the request was being sent: close
    // the response without reading it
    if (isComplete) {
      unawaited(bytes.listen(null).cancel());
      return Future.value();
    }
    final started = generation;
    final done = Completer<void>();
    // The body is read here and handed on, so that stopping can cancel it
    // directly: a cancel doesn't get through the async* decoders while
    // they wait for bytes.
    late final StreamSubscription<List<int>> source;
    final input = StreamController<List<int>>(
      sync: true,
      onPause: () => source.pause(),
      onResume: () => source.resume(),
    );
    source = bytes.listen(
      input.add,
      onError: input.addError,
      onDone: input.close,
    );
    final events = decode(input.stream);
    late final StreamSubscription<T> subscription;
    late final void Function() watch;

    // Ends reading: cancels the subscription, which closes the connection
    // of an HTTP response, and settles [done].
    void finish([Object? error, StackTrace? stackTrace]) {
      if (done.isCompleted) return;
      removeListener(watch);
      unawaited(source.cancel());
      unawaited(subscription.cancel());
      unawaited(input.close());
      if (error == null) {
        done.complete();
      } else {
        done.completeError(error, stackTrace);
      }
    }

    // A reset, or the app ending the reply (a stop button), stops reading
    // right away, even while the server sends nothing.
    watch = () {
      if (generation != started || isComplete) finish();
    };

    void fail(Object error, StackTrace stackTrace) {
      if (done.isCompleted) return;
      // stop watching first: ending the reply here must not look like the
      // app ending it
      removeListener(watch);
      if (generation == started && !isComplete) {
        completeWithError(error, stackTrace);
      }
      finish(error, stackTrace);
    }

    subscription = events.listen(
      (event) {
        try {
          if (onEvent(event)) {
            removeListener(watch);
            if (generation == started) complete();
            finish();
          }
        } on Object catch (error, stackTrace) {
          fail(error, stackTrace);
        }
      },
      onError: fail,
      onDone: () {
        removeListener(watch);
        if (generation == started) complete();
        finish();
      },
      cancelOnError: true,
    );
    addListener(watch);
    return done.future;
  }
}

// The lines of a newline-delimited JSON body, decoded as UTF-8 even when a
// character is split between chunks.
Stream<String> _jsonLines(Stream<List<int>> bytes) => bytes
    .transform(const Utf8Decoder(allowMalformed: true))
    .transform(const LineSplitter());

// The JSON objects of a Gemini stream, from either form: server-sent events,
// or a JSON array whose items arrive one by one. The first byte that isn't
// white space tells which.
Stream<String> _geminiEvents(Stream<List<int>> bytes) async* {
  final chunks = StreamIterator(bytes);
  try {
    final seen = <List<int>>[];
    int? first;
    while (first == null && await chunks.moveNext()) {
      seen.add(chunks.current);
      for (final byte in chunks.current) {
        // space, tab, line feed, carriage return
        if (byte != 0x20 && byte != 0x09 && byte != 0x0A && byte != 0x0D) {
          first = byte;
          break;
        }
      }
    }
    Stream<List<int>> body() async* {
      yield* Stream.fromIterable(seen);
      while (await chunks.moveNext()) {
        yield chunks.current;
      }
    }

    // "[" starts an array, "{" a lone object
    if (first == 0x5B || first == 0x7B) {
      final items = _ArrayItems();
      await for (final text in body().transform(
        const Utf8Decoder(allowMalformed: true),
      )) {
        yield* Stream.fromIterable(items.add(text));
      }
      if (items.open) {
        throw const ModelStreamError('The response ended in the middle.');
      }
    } else {
      yield* serverSentEvents(body()).map((event) => event.data);
    }
  } finally {
    await chunks.cancel();
  }
}

// Cuts the top-level objects out of a JSON array as its text comes in.
class _ArrayItems {
  final StringBuffer _item = StringBuffer();
  int _depth = 0;
  bool _inString = false;
  bool _escaped = false;

  // inside an object that hasn't ended
  bool get open => _depth > 0;

  List<String> add(String chunk) {
    final done = <String>[];
    for (final unit in chunk.codeUnits) {
      final char = String.fromCharCode(unit);
      if (_depth > 0) _item.writeCharCode(unit);
      if (_inString) {
        if (_escaped) {
          _escaped = false;
        } else if (char == '\\') {
          _escaped = true;
        } else if (char == '"') {
          _inString = false;
        }
        continue;
      }
      switch (char) {
        case '"' when _depth > 0:
          _inString = true;
        case '{':
          if (_depth == 0) _item.writeCharCode(unit);
          _depth++;
        case '}' when _depth > 0:
          _depth--;
          if (_depth == 0) {
            done.add(_item.toString());
            _item.clear();
          }
      }
    }
    return done;
  }
}
