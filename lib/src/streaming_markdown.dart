import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';

import 'controller.dart';
import 'incremental_parser.dart';
import 'renderer.dart';
import 'smoothing.dart';
import 'style.dart';
import 'thinking.dart';

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
    this.mathBuilder,
    this.showThinking = true,
    this.thinkingInitiallyExpanded = false,
    this.thinkingLabel,
    this.autoScrollController,
  }) : stream = null,
       text = null,
       isComplete = false;

  /// Shows the chunks of [stream] as they arrive. The reply is complete when
  /// [stream] is done.
  ///
  /// A stream can only be read once. Inside a `ListView`, where items are
  /// disposed and rebuilt while scrolling, keep a [StreamingMarkdownController]
  /// with the message instead (see [StreamingMarkdownController.addStream]).
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
    this.mathBuilder,
    this.showThinking = true,
    this.thinkingInitiallyExpanded = false,
    this.thinkingLabel,
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
    this.mathBuilder,
    this.showThinking = true,
    this.thinkingInitiallyExpanded = false,
    this.thinkingLabel,
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
  ///
  /// Blocks that are already built keep what the builder returned, so a new
  /// function on each rebuild costs nothing.
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

  /// Builds LaTeX formulas. Without it the formula source is shown.
  ///
  /// ```dart
  /// // with package:flutter_math_fork
  /// mathBuilder: (context, tex, display) => Math.tex(
  ///   tex,
  ///   mathStyle: display ? MathStyle.display : MathStyle.text,
  /// ),
  /// ```
  final MarkdownMathBuilder? mathBuilder;

  /// Whether to show the model's reasoning, from `<think>...</think>` at the
  /// start of the reply or from [StreamingMarkdownController.appendThinking],
  /// in a section the user can open. When false it is left out.
  final bool showThinking;

  /// Whether the thinking section starts open.
  final bool thinkingInitiallyExpanded;

  /// The thinking section's title; defaults to "Thinking" and
  /// "Thought for 12s". Use it to translate the title.
  final ThinkingLabelBuilder? thinkingLabel;

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
  final IncrementalMarkdownParser _thinkingParser = IncrementalMarkdownParser();
  final Map<int, Widget> _thinkingWidgets = {};
  DateTime? _thinkingStarted;
  Duration? _thinkingTook;

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
        _subscription = _listen(stream);
      }
    }
    _controller.addListener(_onControllerChanged);
    _generation = _controller.generation;
    _showAll();
  }

  StreamSubscription<String> _listen(Stream<String> stream) {
    try {
      return stream.listen(
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
    } on StateError {
      throw FlutterError.fromParts([
        ErrorSummary(
          'StreamingMarkdown.stream got a stream that was read before.',
        ),
        ErrorDescription(
          'A single-subscription stream can only be read once. This happens '
          'when the widget is created again, for example after it scrolled '
          'out of a ListView and back.',
        ),
        ErrorHint(
          'Keep a StreamingMarkdownController with the message, feed it with '
          'controller.addStream(stream), and use StreamingMarkdown(controller: '
          'controller) instead.',
        ),
      ]);
    }
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
    _thinkingParser.reset();
    _thinkingWidgets.clear();
    _thinkingStarted = null;
    _thinkingTook = null;
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
        widget.newlinesAsBreaks != _settings.newlinesAsBreaks;
    _settings
      ..style = style
      ..onLinkTap = widget.onLinkTap
      ..imageBuilder = widget.imageBuilder
      ..codeBlockBuilder = widget.codeBlockBuilder
      ..highlightCode = widget.highlightCode
      ..newlinesAsBreaks = widget.newlinesAsBreaks
      ..mathBuilder = widget.mathBuilder
      ..showCursor = widget.showCursor
      ..fadeLength = widget.smoothing.fadeLength;
    if (changed) {
      _blockWidgets.clear();
      _thinkingWidgets.clear();
    }
  }

  // Times the thinking phase, but only when it was seen starting; a reply
  // loaded from history shows "Thoughts" instead of a made-up duration.
  void _trackThinking(ThinkingSplit split) {
    if (split.thinking == null) return;
    if (!split.done) {
      _thinkingStarted ??= DateTime.now();
    } else if (_thinkingTook == null && _thinkingStarted != null) {
      _thinkingTook = DateTime.now().difference(_thinkingStarted!);
    }
  }

  ({List<Widget> widgets, bool hasTarget}) _blocks(
    IncrementalMarkdownParser parser,
    Map<int, Widget> cache, {
    required bool streaming,
    required bool countBuilds,
  }) {
    final frozen = parser.frozenBlocks;
    if (cache.length > frozen.length) {
      final ids = {for (final block in frozen) block.id};
      cache.removeWhere((id, _) => !ids.contains(id));
    }
    final widgets = <Widget>[
      for (final block in frozen)
        cache.putIfAbsent(
          block.id,
          () => RepaintBoundary(
            key: ValueKey<int>(block.id),
            child: MarkdownBlockView(
              nodes: block.nodes,
              settings: _settings,
              isComplete: true,
              debugId: countBuilds ? block.id : null,
            ),
          ),
        ),
    ];
    final open = parser.openNodes;
    final target = streaming ? findCursorTarget(open) : null;
    if (open.isNotEmpty) {
      widgets.add(
        MarkdownBlockView(
          key: const ValueKey<String>('open'),
          nodes: open,
          settings: _settings,
          isComplete: false,
          cursorTarget: target,
        ),
      );
    }
    return (widgets: widgets, hasTarget: target != null);
  }

  Widget _spaced(List<Widget> children, double spacing) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) SizedBox(height: spacing),
        children[i],
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? StreamingMarkdownStyle.of(context);
    _updateSettings(style);

    final text = _controller.text;
    final visible = _shown >= text.length ? text : text.substring(0, _shown);
    final complete = _controller.isComplete && _shown >= text.length;

    var split = splitThinking(visible, complete: complete);
    if (_controller.thinking.isNotEmpty) {
      split = ThinkingSplit(
        _controller.thinking,
        visible,
        done: visible.isNotEmpty || complete,
      );
    }
    _trackThinking(split);
    final thinking = widget.showThinking ? split.thinking : null;

    var changed = _parser.update(split.answer, complete: complete);
    if (thinking != null) {
      changed |= _thinkingParser.update(thinking, complete: split.done);
    }
    if (changed) _followEnd();

    final streaming = !complete;
    final answer = _blocks(
      _parser,
      _blockWidgets,
      streaming: streaming,
      countBuilds: true,
    );
    final children = answer.widgets;
    // While the model thinks, the thinking header shows the activity.
    final answering = split.done || thinking == null;
    if (streaming && answering && widget.showCursor && !answer.hasTarget) {
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

    if (thinking != null) {
      final thought = _blocks(
        _thinkingParser,
        _thinkingWidgets,
        streaming: !split.done,
        countBuilds: false,
      );
      children.insert(
        0,
        ThinkingSection(
          label: (widget.thinkingLabel ?? defaultThinkingLabel)(
            split.done,
            split.done ? _thinkingTook : null,
          ),
          done: split.done,
          color: style.codeBlockHeaderStyle.color ?? style.accentColor,
          textStyle: style.textStyle,
          initiallyExpanded: widget.thinkingInitiallyExpanded,
          child: _spaced(thought.widgets, style.blockSpacing),
        ),
      );
    }

    return _spaced(children, style.blockSpacing);
  }
}
