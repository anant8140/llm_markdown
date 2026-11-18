import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';

import 'controller.dart';
import 'incremental_parser.dart';
import 'renderer.dart';
import 'smoothing.dart';
import 'style.dart';

/// Shows Markdown that arrives in pieces, such as an AI chat reply, without
/// flicker or broken syntax.
///
/// Finished blocks are parsed and built once and then kept; only the last,
/// unfinished block is parsed again as text arrives. Its unfinished end is
/// tidied first, so an unclosed code block, `**bold` or half-typed link
/// shows as it will look, not as raw symbols.
///
/// Give the text in one of three ways:
///
/// * [StreamingMarkdown.new] with a [StreamingMarkdownController] that you
///   [StreamingMarkdownController.append] to;
/// * [StreamingMarkdown.stream] with a `Stream<String>` of chunks;
/// * [StreamingMarkdown.text] with the text so far, for example from your
///   own state that you rebuild as chunks arrive.
///
/// ```dart
/// StreamingMarkdown.stream(
///   replyStream,
///   onLinkTap: (url) => launchUrl(Uri.parse(url)),
/// )
/// ```
class StreamingMarkdown extends StatefulWidget {
  /// Shows the text of [controller].
  const StreamingMarkdown({
    super.key,
    required StreamingMarkdownController this.controller,
    this.smoothing = const Smoothing.adaptive(),
    this.style,
    this.onLinkTap,
    this.imageBuilder,
    this.codeBlockBuilder,
    this.highlightCode = true,
    this.showCursor = true,
    this.newlinesAsBreaks = false,
    this.autoScrollController,
  }) : stream = null,
       text = null,
       isComplete = false;

  /// Shows the chunks of [stream] as they arrive. The reply is complete when
  /// [stream] is done.
  const StreamingMarkdown.stream(
    Stream<String> this.stream, {
    super.key,
    this.smoothing = const Smoothing.adaptive(),
    this.style,
    this.onLinkTap,
    this.imageBuilder,
    this.codeBlockBuilder,
    this.highlightCode = true,
    this.showCursor = true,
    this.newlinesAsBreaks = false,
    this.autoScrollController,
  }) : controller = null,
       text = null,
       isComplete = false;

  /// Shows [text].
  ///
  /// While [isComplete] is false, rebuilding with a longer [text] that
  /// starts with the previous one adds the new part as streamed text. Any
  /// other change replaces the text.
  const StreamingMarkdown.text(
    String this.text, {
    super.key,
    this.isComplete = true,
    this.smoothing = const Smoothing.adaptive(),
    this.style,
    this.onLinkTap,
    this.imageBuilder,
    this.codeBlockBuilder,
    this.highlightCode = true,
    this.showCursor = true,
    this.newlinesAsBreaks = false,
    this.autoScrollController,
  }) : controller = null,
       stream = null;

  /// The controller whose text is shown, when created with the default
  /// constructor.
  final StreamingMarkdownController? controller;

  /// The stream whose chunks are shown, when created with
  /// [StreamingMarkdown.stream].
  final Stream<String>? stream;

  /// The text shown, when created with [StreamingMarkdown.text].
  final String? text;

  /// Whether [text] is the whole reply. Used with [StreamingMarkdown.text].
  final bool isComplete;

  /// How fast arriving text is revealed. Text that is already there when
  /// the widget first builds is shown at once.
  final Smoothing smoothing;

  /// The look; defaults to [StreamingMarkdownStyle.of] the context, which
  /// follows the app's text style and accent color.
  final StreamingMarkdownStyle? style;

  /// Called with the address of a tapped link.
  final ValueChanged<String>? onLinkTap;

  /// Builds images; the default loads them with [Image.network].
  final MarkdownImageBuilder? imageBuilder;

  /// Builds code blocks, for example to show diagrams; return null to use
  /// the default code block.
  final MarkdownCodeBlockBuilder? codeBlockBuilder;

  /// Whether finished code blocks are syntax highlighted.
  final bool highlightCode;

  /// Whether a blinking cursor follows the text while it arrives.
  final bool showCursor;

  /// Whether a single newline inside a paragraph starts a new line.
  ///
  /// Markdown treats it as a space; many chat apps show it as a line break.
  final bool newlinesAsBreaks;

  /// The scroll controller of the list that holds this widget.
  ///
  /// When given, the list keeps following the end of the text as it grows,
  /// as long as the user is at the bottom. Scrolling up stops following;
  /// scrolling back to the bottom resumes it. Not needed for a list with
  /// `reverse: true`, which stays at its end by itself.
  final ScrollController? autoScrollController;

  @override
  State<StreamingMarkdown> createState() => _StreamingMarkdownState();
}

class _StreamingMarkdownState extends State<StreamingMarkdown>
    with SingleTickerProviderStateMixin {
  final IncrementalMarkdownParser _parser = IncrementalMarkdownParser();
  final RenderSettings _settings = RenderSettings();
  final Map<int, Widget> _blockWidgets = {};

  late final Ticker _ticker = createTicker(_onTick);
  late StreamingMarkdownController _controller;
  StreamingMarkdownController? _ownedController;
  StreamSubscription<String>? _subscription;

  int _generation = 0;
  int _shown = 0;
  double _carry = 0;
  Duration _lastTick = Duration.zero;
  bool _followScheduled = false;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    final controller = widget.controller;
    if (controller != null) {
      _controller = controller;
    } else {
      _controller = _ownedController = StreamingMarkdownController(
        text: widget.text ?? '',
        isComplete: widget.text != null && widget.isComplete,
      );
      final stream = widget.stream;
      if (stream != null) {
        _subscription = stream.listen(
          _controller.append,
          onDone: _controller.complete,
          onError: (Object error, StackTrace stack) {
            _controller.complete();
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stack,
                library: 'llm_markdown',
                context: ErrorDescription('while reading the Markdown stream'),
              ),
            );
          },
          cancelOnError: true,
        );
      }
    }
    _controller.addListener(_onControllerChanged);
    _generation = _controller.generation;
    _showAll();
  }

  void _detach() {
    _controller.removeListener(_onControllerChanged);
    unawaited(_subscription?.cancel());
    _subscription = null;
    _ownedController?.dispose();
    _ownedController = null;
  }

  void _showAll() {
    _ticker.stop();
    _carry = 0;
    _shown = _controller.text.length;
    _parser.reset();
    _blockWidgets.clear();
  }

  @override
  void didUpdateWidget(StreamingMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged =
        widget.controller != oldWidget.controller ||
        widget.stream != oldWidget.stream ||
        (widget.text == null) != (oldWidget.text == null);
    if (sourceChanged) {
      _detach();
      _attach();
      if (widget.stream != null) {
        // A new stream starts a new reply, revealed as it arrives.
        _shown = 0;
      }
      return;
    }
    final text = widget.text;
    final owned = _ownedController;
    if (text == null || owned == null) return;
    if (text == owned.text && widget.isComplete == owned.isComplete) return;
    if (!owned.isComplete && text.startsWith(owned.text)) {
      owned.append(text.substring(owned.text.length));
      if (widget.isComplete) owned.complete();
    } else {
      owned.reset(text, widget.isComplete);
    }
  }

  void _onControllerChanged() {
    final text = _controller.text;
    if (_controller.generation != _generation) {
      _generation = _controller.generation;
      _showAll();
    } else if (!widget.smoothing.enabled) {
      _shown = text.length;
    } else if (_shown > text.length) {
      _shown = text.length;
    } else if (_shown < text.length && !_ticker.isActive) {
      _lastTick = Duration.zero;
      unawaited(_ticker.start());
    }
    setState(() {});
  }

  void _onTick(Duration elapsed) {
    final text = _controller.text;
    final waiting = text.length - _shown;
    if (waiting <= 0) {
      _ticker.stop();
      return;
    }
    final seconds =
        (elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = elapsed;
    _carry += widget.smoothing.speedFor(waiting) * seconds;
    final step = _carry.isFinite ? _carry.floor() : waiting;
    if (step <= 0) return;
    _carry = _carry.isFinite ? _carry - step : 0;
    setState(() {
      _shown = graphemeBoundaryAtOrAfter(
        text,
        math.min(text.length, _shown + step),
      );
    });
    if (_shown >= text.length) {
      _ticker.stop();
      _carry = 0;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _detach();
    super.dispose();
  }

  void _followEnd() {
    final scroll = widget.autoScrollController;
    if (scroll == null || !scroll.hasClients || _followScheduled) return;
    final position = scroll.position;
    if (!position.hasContentDimensions) return;
    if (position.isScrollingNotifier.value) return;
    if (position.pixels < position.maxScrollExtent - 48) return;
    _followScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followScheduled = false;
      if (!mounted || !scroll.hasClients) return;
      final position = scroll.position;
      if (position.hasContentDimensions &&
          position.pixels < position.maxScrollExtent) {
        scroll.jumpTo(position.maxScrollExtent);
      }
    });
  }

  void _updateSettings(StreamingMarkdownStyle style) {
    final changed =
        style != _settings.style ||
        widget.highlightCode != _settings.highlightCode ||
        widget.newlinesAsBreaks != _settings.newlinesAsBreaks ||
        widget.imageBuilder != _settings.imageBuilder ||
        widget.codeBlockBuilder != _settings.codeBlockBuilder;
    _settings
      ..style = style
      ..onLinkTap = widget.onLinkTap
      ..imageBuilder = widget.imageBuilder
      ..codeBlockBuilder = widget.codeBlockBuilder
      ..highlightCode = widget.highlightCode
      ..newlinesAsBreaks = widget.newlinesAsBreaks;
    if (changed) _blockWidgets.clear();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? StreamingMarkdownStyle.of(context);
    _updateSettings(style);

    final text = _controller.text;
    final visible = _shown >= text.length ? text : text.substring(0, _shown);
    final complete = _controller.isComplete && _shown >= text.length;
    if (_parser.update(visible, complete: complete)) _followEnd();

    final frozen = _parser.frozenBlocks;
    if (_blockWidgets.length > frozen.length) {
      final ids = {for (final block in frozen) block.id};
      _blockWidgets.removeWhere((id, _) => !ids.contains(id));
    }

    final children = <Widget>[
      for (final block in frozen)
        _blockWidgets.putIfAbsent(
          block.id,
          () => RepaintBoundary(
            key: ValueKey<int>(block.id),
            child: MarkdownBlockView(
              nodes: block.nodes,
              settings: _settings,
              isComplete: true,
              debugId: block.id,
            ),
          ),
        ),
    ];

    final streaming = !complete;
    final open = _parser.openNodes;
    final cursorTarget = streaming && widget.showCursor
        ? findCursorTarget(open)
        : null;
    if (open.isNotEmpty) {
      children.add(
        MarkdownBlockView(
          key: const ValueKey<String>('open'),
          nodes: open,
          settings: _settings,
          isComplete: false,
          cursorTarget: cursorTarget,
        ),
      );
    }
    if (streaming && widget.showCursor && cursorTarget == null) {
      children.add(
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: StreamingCursor(
            color: style.accentColor,
            fontSize: style.textStyle.fontSize ?? 14,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: style.blockSpacing),
          children[i],
        ],
      ],
    );
  }
}
