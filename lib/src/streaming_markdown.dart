import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'code_options.dart';
import 'controller.dart';
import 'direction.dart';
import 'headings.dart';
import 'labels.dart';
import 'line_clip.dart';
import 'package:llm_markdown_parser/llm_markdown_parser.dart';
import 'renderer.dart';
import 'safety.dart';
import 'smoothing.dart';
import 'style.dart';
import 'thinking.dart';
import 'tool_calls.dart';

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
    this.tableBuilder,
    this.codeBlockBuilder,
    this.highlightCode = true,
    this.showCursor = true,
    this.newlinesAsBreaks = false,
    this.mathBuilder,
    this.showThinking = true,
    this.thinkingInitiallyExpanded = false,
    this.thinkingLabel,
    this.announceWhenDone = true,
    this.detectTextDirection = true,
    this.allowedLinkSchemes = defaultLinkSchemes,
    this.allowedImageSchemes = defaultImageSchemes,
    this.tapToSkip = false,
    this.placeholder,
    this.errorBuilder,
    this.onComplete,
    this.onTextChanged,
    this.cursorStyle = StreamingCursorStyle.block,
    this.fadeBottomEdge = false,
    this.updateInterval = Duration.zero,
    this.syntax = const MarkdownSyntax(),
    this.onCitationTap,
    this.codeBlocks = const CodeBlockOptions(),
    this.headings,
    this.searchQuery,
    this.searchHighlightColor,
    this.onImageTap,
    this.zoomImages = true,
    this.maxLines,
    this.fadeOverflow = true,
    this.sliver = false,
    this.elementBuilders = const {},
    this.diagrams = true,
    this.labels,
    this.thinkingBuilder,
    this.showToolCalls = true,
    this.showToolCallArguments = true,
    this.toolCallBuilder,
    this.cursorBuilder,
    this.autoScrollController,
  }) : assert(maxLines == null || maxLines > 0, 'maxLines must be positive'),
       assert(!sliver || maxLines == null, 'a sliver has no maxLines'),
       stream = null,
       text = null,
       isComplete = false,
       completeAfter = null;

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
    this.tableBuilder,
    this.codeBlockBuilder,
    this.highlightCode = true,
    this.showCursor = true,
    this.newlinesAsBreaks = false,
    this.mathBuilder,
    this.showThinking = true,
    this.thinkingInitiallyExpanded = false,
    this.thinkingLabel,
    this.announceWhenDone = true,
    this.detectTextDirection = true,
    this.allowedLinkSchemes = defaultLinkSchemes,
    this.allowedImageSchemes = defaultImageSchemes,
    this.tapToSkip = false,
    this.placeholder,
    this.errorBuilder,
    this.onComplete,
    this.onTextChanged,
    this.cursorStyle = StreamingCursorStyle.block,
    this.fadeBottomEdge = false,
    this.updateInterval = Duration.zero,
    this.syntax = const MarkdownSyntax(),
    this.onCitationTap,
    this.codeBlocks = const CodeBlockOptions(),
    this.headings,
    this.searchQuery,
    this.searchHighlightColor,
    this.onImageTap,
    this.zoomImages = true,
    this.maxLines,
    this.fadeOverflow = true,
    this.sliver = false,
    this.elementBuilders = const {},
    this.diagrams = true,
    this.labels,
    this.thinkingBuilder,
    this.showToolCalls = true,
    this.showToolCallArguments = true,
    this.toolCallBuilder,
    this.cursorBuilder,
    this.autoScrollController,
  }) : assert(maxLines == null || maxLines > 0, 'maxLines must be positive'),
       assert(!sliver || maxLines == null, 'a sliver has no maxLines'),
       controller = null,
       text = null,
       isComplete = false,
       completeAfter = null;

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
    this.tableBuilder,
    this.codeBlockBuilder,
    this.highlightCode = true,
    this.showCursor = true,
    this.newlinesAsBreaks = false,
    this.mathBuilder,
    this.showThinking = true,
    this.thinkingInitiallyExpanded = false,
    this.thinkingLabel,
    this.announceWhenDone = true,
    this.detectTextDirection = true,
    this.allowedLinkSchemes = defaultLinkSchemes,
    this.allowedImageSchemes = defaultImageSchemes,
    this.tapToSkip = false,
    this.placeholder,
    this.errorBuilder,
    this.onComplete,
    this.onTextChanged,
    this.cursorStyle = StreamingCursorStyle.block,
    this.fadeBottomEdge = false,
    this.updateInterval = Duration.zero,
    this.syntax = const MarkdownSyntax(),
    this.onCitationTap,
    this.codeBlocks = const CodeBlockOptions(),
    this.headings,
    this.searchQuery,
    this.searchHighlightColor,
    this.onImageTap,
    this.zoomImages = true,
    this.maxLines,
    this.fadeOverflow = true,
    this.sliver = false,
    this.elementBuilders = const {},
    this.diagrams = true,
    this.labels,
    this.thinkingBuilder,
    this.showToolCalls = true,
    this.showToolCallArguments = true,
    this.toolCallBuilder,
    this.cursorBuilder,
    this.autoScrollController,
    this.completeAfter,
  }) : assert(maxLines == null || maxLines > 0, 'maxLines must be positive'),
       assert(!sliver || maxLines == null, 'a sliver has no maxLines'),
       controller = null,
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
  ///
  /// Ignored when [completeAfter] is set.
  final bool isComplete;

  /// For a [text] that grows but never says when it is done, such as the
  /// `responseBuilder` of `LlmChatView` in `flutter_ai_toolkit`: the reply
  /// counts as complete once [text] has not grown for this long.
  ///
  /// The text given when the widget first builds counts as complete, so a
  /// reply from the history shows no cursor; when it grows, the new part is
  /// streamed. Used with [StreamingMarkdown.text]; [isComplete] is then
  /// ignored.
  final Duration? completeAfter;

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

  /// Wraps or replaces tables, with their cells as text: add a "Copy as
  /// CSV" button with [MarkdownTableData.toCsv].
  final MarkdownTableBuilder? tableBuilder;

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

  /// Whether screen readers read the reply out once it is complete.
  ///
  /// The part that is still arriving is hidden from screen readers, so they
  /// don't read half sentences; when the reply ends the whole text is
  /// announced. Replies that are already complete when shown aren't.
  final bool announceWhenDone;

  /// Whether each paragraph, list, quote and table takes its direction from
  /// its first letter, like `dir="auto"` on the web. An Arabic or Hebrew reply
  /// then reads right to left even in a left-to-right app. Code always reads
  /// left to right.
  final bool detectTextDirection;

  /// Link schemes that open on tap; others show as plain text. Models can
  /// produce `javascript:` or `file:` links, which are not allowed by
  /// default. Links without a scheme are passed on as they are.
  final Set<String> allowedLinkSchemes;

  /// Image schemes that are loaded; other images show their alt text.
  final Set<String> allowedImageSchemes;

  /// Whether tapping the reply while it is revealed shows the rest at once.
  final bool tapToSkip;

  /// Shown instead of the cursor until the first text arrives, for example
  /// `const MarkdownShimmer()`.
  final Widget? placeholder;

  /// Builds what is shown below the text when the reply ended with an error
  /// ([StreamingMarkdownController.completeWithError] or a stream error),
  /// for example a message and a retry button. When null, stream errors are
  /// reported to [FlutterError].
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  /// Called once the whole reply is shown, after it streamed in.
  final VoidCallback? onComplete;

  /// Called after the shown text changes, with the Markdown shown so far.
  final ValueChanged<String>? onTextChanged;

  /// The shape of the cursor shown while text arrives.
  final StreamingCursorStyle cursorStyle;

  /// Whether the bottom edge fades out while the reply streams, so new
  /// lines appear to come out of it.
  final bool fadeBottomEdge;

  /// The shortest time between two updates. Raise it, e.g. to 50 ms, to
  /// save work when a model sends many tiny chunks.
  final Duration updateInterval;

  /// Which Markdown extensions are recognized: math with `$`, alerts,
  /// citations, emoji, highlight and spoilers, a little HTML, `<details>`
  /// and autolinks. All are on by default.
  final MarkdownSyntax syntax;

  /// Called with the number of a tapped citation chip, e.g. 1 for `[1]`.
  final ValueChanged<int>? onCitationTap;

  /// Line numbers, wrapping, collapsing long blocks, highlighting while
  /// streaming, and custom header buttons for code blocks.
  final CodeBlockOptions codeBlocks;

  /// Collects the reply's headings for a table of contents, and scrolls to
  /// them. Headings also get ids, so `[Setup](#setup)` links scroll there.
  final MarkdownHeadings? headings;

  /// Marks every case-insensitive match of this text, for find-in-chat.
  /// Code blocks are not searched.
  final String? searchQuery;

  /// The background of [searchQuery] matches; defaults to the accent color,
  /// faded.
  final Color? searchHighlightColor;

  /// Called when an image is tapped. Without it, a tap opens the image full
  /// screen, where it can be zoomed, as long as [zoomImages] is true and
  /// there is a `Navigator`.
  final MarkdownImageTapCallback? onImageTap;

  /// Whether tapping an image opens it full screen with pinch-to-zoom.
  final bool zoomImages;

  /// Shows only about this many lines of body text, for previews such as a
  /// chat list. What doesn't fit is cut off, faded when [fadeOverflow] is
  /// true. Headings, code and images count by their height.
  final int? maxLines;

  /// Whether text cut off by [maxLines] fades out instead of ending sharply.
  final bool fadeOverflow;

  /// Whether this widget is a sliver, to put straight into a
  /// `CustomScrollView`. Blocks are then built only when scrolled into
  /// view, which keeps very long replies fast. [fadeBottomEdge] and
  /// [maxLines] don't apply to a sliver.
  final bool sliver;

  /// Your own widgets for Markdown elements, by tag, for example for the
  /// tags of `MarkdownSyntax.blockSyntaxes`, or `'blockquote'`. A builder
  /// that returns null keeps the default look.
  final Map<String, MarkdownElementBuilder> elementBuilders;

  /// Whether a finished ` ```mermaid ` block is drawn as a diagram
  /// (flowcharts, sequence diagrams and pie charts; see `MermaidDiagram`).
  /// Other kinds stay code blocks. A `codeBlockBuilder` is asked first.
  final bool diagrams;

  /// The text the widget shows or reads out by itself ("Copy", "Show
  /// code", alert titles, ...), for other languages. Defaults to the
  /// nearest `StreamingMarkdownTheme.labels`, or English.
  final MarkdownLabels? labels;

  /// Builds the thinking section yourself, in place of the built-in
  /// collapsible one.
  final MarkdownThinkingBuilder? thinkingBuilder;

  /// Whether the tools the model calls ([StreamingMarkdownController.toolCalls])
  /// are listed at the top of the reply, one line each.
  final bool showToolCalls;

  /// Whether a tool call's line also says what the call is about: the
  /// first text among its arguments, such as the query of a search, shown
  /// as it is written. See [MarkdownToolCall.summary].
  final bool showToolCallArguments;

  /// Builds the line for one tool call yourself, in place of the built-in
  /// "Using web search…" line.
  final MarkdownToolCallBuilder? toolCallBuilder;

  /// Builds the cursor shown while text arrives, in place of the built-in
  /// one ([cursorStyle] is then not used).
  final MarkdownCursorBuilder? cursorBuilder;

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
  late IncrementalMarkdownParser _parser = IncrementalMarkdownParser(
    syntax: widget.syntax,
  );
  final RenderSettings _settings = RenderSettings();
  final Map<int, Widget> _blockWidgets = {};
  late IncrementalMarkdownParser _thinkingParser = IncrementalMarkdownParser(
    syntax: widget.syntax,
  );
  final Map<int, Widget> _thinkingWidgets = {};
  DateTime? _thinkingStarted;
  Duration? _thinkingTook;
  bool _sawStreaming = false;
  bool _completePending = false;
  int _seenSkips = 0;
  int _seenReplays = 0;
  Duration _lastUpdate = Duration.zero;
  Timer? _throttle;
  String? _reportedText;

  late final Ticker _ticker = createTicker(_onTick);
  late StreamingMarkdownController _controller;
  StreamingMarkdownController? _ownedController;
  StreamSubscription<String>? _subscription;

  int _generation = 0;
  int _shown = 0;
  double _carry = 0;
  Duration _lastTick = Duration.zero;
  bool _followScheduled = false;

  // heading ids are given block by block; see _headingIds
  final List<int> _idBlocks = [];
  final Map<String, int> _idCounts = {};
  final List<MarkdownHeading> _frozenHeadings = [];

  @override
  void initState() {
    super.initState();
    widget.headings?.attach(_settings.anchors);
    _attach();
  }

  void _attach() {
    final controller = widget.controller;
    if (controller != null) {
      _controller = controller;
    } else {
      _controller = _ownedController = StreamingMarkdownController(
        text: widget.text ?? '',
        isComplete:
            widget.text != null &&
            (widget.completeAfter != null || widget.isComplete),
      );
      final stream = widget.stream;
      if (stream != null) {
        _subscription = _listen(stream);
      }
    }
    _controller.addListener(_onControllerChanged);
    _generation = _controller.generation;
    _seenSkips = _controller.skipCount;
    _seenReplays = _controller.replayCount;
    _showAll();
  }

  StreamSubscription<String> _listen(Stream<String> stream) {
    try {
      return stream.listen(
        _controller.append,
        onDone: _controller.complete,
        onError: (Object error, StackTrace stack) {
          _controller.completeWithError(error, stack);
          if (widget.errorBuilder != null) return;
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
    _idleTimer?.cancel();
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
    _sawStreaming = false;
    _completePending = false;
    _reportedText = null;
  }

  // With "reduce motion" on, text shows at once and nothing fades.
  Smoothing get _smoothing =>
      (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
      ? const Smoothing.none()
      : widget.smoothing;

  void _skip() {
    if (_shown >= _controller.text.length) return;
    setState(() {
      _ticker.stop();
      _carry = 0;
      _shown = _controller.text.length;
    });
  }

  void _notify(String visible, bool complete) {
    final onText = widget.onTextChanged;
    if (onText != null && visible != _reportedText) {
      _reportedText = visible;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) onText(visible);
      });
    }
    if (!complete) {
      _completePending = true;
    } else if (_completePending) {
      _completePending = false;
      final onComplete = widget.onComplete;
      if (onComplete != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) onComplete();
        });
      }
    }
  }

  @override
  void didUpdateWidget(StreamingMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.headings != oldWidget.headings) {
      oldWidget.headings?.detach(_settings.anchors);
      widget.headings?.attach(_settings.anchors);
    }
    if (widget.syntax != oldWidget.syntax) {
      _parser = IncrementalMarkdownParser(syntax: widget.syntax);
      _thinkingParser = IncrementalMarkdownParser(syntax: widget.syntax);
      _blockWidgets.clear();
      _thinkingWidgets.clear();
    }
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
    final idle = widget.completeAfter;
    if (idle != null) {
      _updateGrowing(owned, text, idle);
      return;
    }
    _idleTimer?.cancel();
    if (text == owned.text && widget.isComplete == owned.isComplete) return;
    if (!owned.isComplete && text.startsWith(owned.text)) {
      owned.append(text.substring(owned.text.length));
      if (widget.isComplete) owned.complete();
    } else {
      owned.reset(text, widget.isComplete);
    }
  }

  Timer? _idleTimer;

  /// Follows a [StreamingMarkdown.text] whose end is guessed from
  /// [StreamingMarkdown.completeAfter].
  void _updateGrowing(
    StreamingMarkdownController owned,
    String text,
    Duration idle,
  ) {
    if (text == owned.text) return;
    if (text.startsWith(owned.text)) {
      // Reopen a reply counted as complete, keeping what is shown.
      owned.reopen();
      owned.append(text.substring(owned.text.length));
      _idleTimer?.cancel();
      _idleTimer = Timer(idle, owned.complete);
    } else {
      _idleTimer?.cancel();
      owned.reset(text, true);
    }
  }

  void _onControllerChanged() {
    final text = _controller.text;
    if (_controller.generation != _generation) {
      _generation = _controller.generation;
      _showAll();
      setState(() {});
      return;
    }
    if (_controller.replayCount != _seenReplays) {
      _seenReplays = _controller.replayCount;
      _ticker.stop();
      _carry = 0;
      _shown = 0;
      _parser.reset();
      _blockWidgets.clear();
      _thinkingParser.reset();
      _thinkingWidgets.clear();
    }
    if (_controller.skipCount != _seenSkips) {
      _seenSkips = _controller.skipCount;
      _ticker.stop();
      _shown = text.length;
    } else if (_controller.isPaused) {
      _ticker.stop();
    } else if (!_smoothing.enabled) {
      if (widget.updateInterval > Duration.zero) {
        // coalesce bursts of small chunks into one update per interval
        _throttle ??= Timer(widget.updateInterval, () {
          _throttle = null;
          if (mounted) setState(() => _shown = _controller.text.length);
        });
        return;
      }
      _shown = text.length;
    } else if (_shown > text.length) {
      _shown = text.length;
    } else if (_shown < text.length && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _lastUpdate = Duration.zero;
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
    if (elapsed - _lastUpdate < widget.updateInterval) return;
    _lastUpdate = elapsed;
    final seconds =
        (elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = elapsed;
    _carry += _smoothing.speedFor(waiting) * seconds;
    final step = _carry.isFinite ? _carry.floor() : waiting;
    if (step <= 0) return;
    _carry = _carry.isFinite ? _carry - step : 0;
    var next = graphemeBoundaryAtOrAfter(
      text,
      math.min(text.length, _shown + step),
    );
    if (_smoothing.unit == RevealUnit.word) {
      next = wordBoundaryAtOrAfter(text, next, _shown, _controller.isComplete);
      if (next == _shown) return;
    }
    setState(() => _shown = next);
    if (_shown >= text.length) {
      _ticker.stop();
      _carry = 0;
    }
  }

  @override
  void dispose() {
    _throttle?.cancel();
    _idleTimer?.cancel();
    _ticker.dispose();
    _detach();
    widget.headings?.detach(_settings.anchors);
    super.dispose();
  }

  void _followEnd() {
    final scroll = widget.autoScrollController;
    if (scroll == null || !scroll.hasClients || _followScheduled) return;
    final position = scroll.position;
    if (!position.hasContentDimensions) return;
    // Only the user's own drag or fling stops the following. The list also
    // "scrolls" when it springs back after the reply got shorter for a
    // frame (a half-typed image is hidden, a formula's source becomes the
    // drawn formula); giving up then would lose the end for good.
    if (position.userScrollDirection != ScrollDirection.idle) return;
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

  void _updateSettings(StreamingMarkdownStyle style, MarkdownLabels labels) {
    final changed =
        labels != _settings.labels ||
        (widget.cursorBuilder == null) != (_settings.cursorBuilder == null) ||
        style != _settings.style ||
        widget.highlightCode != _settings.highlightCode ||
        widget.newlinesAsBreaks != _settings.newlinesAsBreaks ||
        widget.detectTextDirection != _settings.detectTextDirection ||
        // builders may be new closures on every build; only layout counts
        widget.codeBlocks.lineNumbers != _settings.codeBlocks.lineNumbers ||
        widget.codeBlocks.wrapLines != _settings.codeBlocks.wrapLines ||
        widget.codeBlocks.collapseAfterLines !=
            _settings.codeBlocks.collapseAfterLines ||
        widget.searchQuery != _settings.searchQuery ||
        widget.diagrams != _settings.diagrams ||
        !setEquals(
          widget.elementBuilders.keys.toSet(),
          _settings.elementBuilders.keys.toSet(),
        ) ||
        widget.searchHighlightColor != _settings.searchColor ||
        widget.zoomImages != _settings.zoomImages ||
        (widget.onImageTap == null) != (_settings.onImageTap == null) ||
        !setEquals(widget.allowedLinkSchemes, _settings.linkSchemes) ||
        !setEquals(widget.allowedImageSchemes, _settings.imageSchemes);
    _settings
      ..style = style
      ..onLinkTap = widget.onLinkTap
      ..imageBuilder = widget.imageBuilder
      ..tableBuilder = widget.tableBuilder
      ..codeBlockBuilder = widget.codeBlockBuilder
      ..highlightCode = widget.highlightCode
      ..newlinesAsBreaks = widget.newlinesAsBreaks
      ..mathBuilder = widget.mathBuilder
      ..showCursor = widget.showCursor
      ..fadeLength = _smoothing.fadeLength
      ..cursorStyle = widget.cursorStyle
      ..onCitationTap = widget.onCitationTap
      ..codeBlocks = widget.codeBlocks
      ..searchQuery = widget.searchQuery
      ..diagrams = widget.diagrams
      ..labels = labels
      ..cursorBuilder = widget.cursorBuilder
      ..elementBuilders = widget.elementBuilders
      ..searchColor = widget.searchHighlightColor
      ..zoomImages = widget.zoomImages
      ..onImageTap = widget.onImageTap
      ..linkSchemes = widget.allowedLinkSchemes
      ..imageSchemes = widget.allowedImageSchemes
      ..detectTextDirection = widget.detectTextDirection;
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

  void _announceWhenDone(bool complete) {
    if (!complete) {
      _sawStreaming = true;
      return;
    }
    if (!_sawStreaming) return;
    _sawStreaming = false;
    if (!widget.announceWhenDone) return;
    final text = [
      for (final block in _parser.frozenBlocks)
        for (final node in block.nodes) node.textContent,
    ].join('\n').trim();
    if (text.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // SemanticsService.announce is deprecated and its replacement,
      // sendAnnouncement, isn't in Flutter 3.35 yet, so the announce event
      // goes to the engine directly. Older engines ignore the view id.
      final direction = detectTextDirection(text) ?? Directionality.of(context);
      unawaited(
        SystemChannels.accessibility.send(<String, Object>{
          'type': 'announce',
          'data': <String, Object>{
            'viewId': View.of(context).viewId,
            'message': text,
            'textDirection': direction.index,
          },
        }),
      );
    });
  }

  // Ids for the headings of new frozen blocks, counted on from the blocks
  // before; the open block's ids are worked out again every time.
  List<MarkdownHeading> _headingIds() {
    final frozen = _parser.frozenBlocks;
    var same = _idBlocks.length <= frozen.length;
    for (var i = 0; same && i < _idBlocks.length; i++) {
      same = frozen[i].id == _idBlocks[i];
    }
    if (!same) {
      _idBlocks.clear();
      _idCounts.clear();
      _frozenHeadings.clear();
    }
    for (var i = _idBlocks.length; i < frozen.length; i++) {
      _frozenHeadings.addAll(assignHeadingIds(frozen[i].nodes, _idCounts));
      _idBlocks.add(frozen[i].id);
    }
    return [
      ..._frozenHeadings,
      ...assignHeadingIds(_parser.openNodes, Map.of(_idCounts)),
    ];
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
        // half sentences are not read out; see announceWhenDone
        ExcludeSemantics(
          excluding: streaming,
          child: MarkdownBlockView(
            key: const ValueKey<String>('open'),
            nodes: open,
            settings: _settings,
            isComplete: false,
            cursorTarget: target,
          ),
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
    _updateSettings(
      style,
      widget.labels ??
          StreamingMarkdownTheme.labelsOf(context) ??
          const MarkdownLabels(),
    );

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
    final headings = _headingIds();
    widget.headings?.update(headings);

    final streaming = !complete;
    _announceWhenDone(complete);
    _notify(visible, complete);
    final answer = _blocks(
      _parser,
      _blockWidgets,
      streaming: streaming,
      countBuilds: true,
    );
    final children = answer.widgets;
    // While the model thinks, the thinking header shows the activity.
    final answering = split.done || thinking == null;
    if (streaming && answering && !answer.hasTarget) {
      final placeholder = widget.placeholder;
      if (split.answer.isEmpty && placeholder != null) {
        children.add(placeholder);
      } else if (widget.showCursor) {
        children.add(
          Align(
            alignment: AlignmentDirectional.centerStart,
            child:
                widget.cursorBuilder?.call(context, style.textStyle) ??
                StreamingCursor(
                  color: style.accentColor,
                  fontSize: style.textStyle.fontSize ?? 14,
                  style: widget.cursorStyle,
                ),
          ),
        );
      }
    }
    final error = _controller.error;
    final errorBuilder = widget.errorBuilder;
    if (complete && error != null && errorBuilder != null) {
      children.add(errorBuilder(context, error));
    }

    final calls = widget.showToolCalls
        ? _controller.toolCalls
        : const <MarkdownToolCall>[];
    if (calls.isNotEmpty) {
      final toolCallBuilder = widget.toolCallBuilder;
      final label = _settings.labels.toolCall ?? defaultToolCallLabel;
      children.insertAll(0, [
        for (final call in calls)
          toolCallBuilder != null
              ? toolCallBuilder(context, call)
              : ToolCallLine(
                  key: ValueKey('tool ${call.id}'),
                  label: label(call.name, call.isDone),
                  detail: widget.showToolCallArguments ? call.summary : null,
                  done: call.isDone,
                  color: style.accentColor,
                  textStyle: style.textStyle,
                ),
      ]);
    }

    if (thinking != null) {
      final thought = _blocks(
        _thinkingParser,
        _thinkingWidgets,
        streaming: !split.done,
        countBuilds: false,
      );
      final label = (widget.thinkingLabel ?? defaultThinkingLabel)(
        split.done,
        split.done ? _thinkingTook : null,
      );
      final thoughts = _spaced(thought.widgets, style.blockSpacing);
      final thinkingBuilder = widget.thinkingBuilder;
      children.insert(
        0,
        thinkingBuilder != null
            ? thinkingBuilder(
                context,
                MarkdownThinking(
                  done: split.done,
                  duration: split.done ? _thinkingTook : null,
                  label: label,
                  content: thoughts,
                ),
              )
            : ThinkingSection(
                label: label,
                done: split.done,
                color:
                    style.thinkingStyle?.color ??
                    style.codeBlockHeaderStyle.color ??
                    style.accentColor,
                textStyle: style.textStyle.merge(style.thinkingStyle),
                initiallyExpanded: widget.thinkingInitiallyExpanded,
                child: thoughts,
              ),
      );
    }

    if (widget.sliver) {
      return SliverList.list(
        children: [
          for (var i = 0; i < children.length; i++)
            Padding(
              key: children[i].key,
              padding: EdgeInsets.only(top: i == 0 ? 0 : style.blockSpacing),
              child: widget.tapToSkip && streaming
                  ? GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _skip,
                      child: children[i],
                    )
                  : children[i],
            ),
        ],
      );
    }

    var column = _spaced(children, style.blockSpacing);
    final maxLines = widget.maxLines;
    if (maxLines != null) {
      final line = TextPainter(
        text: TextSpan(text: 'X', style: style.textStyle),
        textDirection: TextDirection.ltr,
        textScaler:
            MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling,
      )..layout();
      final lineHeight = line.height;
      line.dispose();
      column = HeightClip(
        maxHeight: lineHeight * maxLines,
        fadeHeight: lineHeight,
        fade: widget.fadeOverflow,
        child: column,
      );
    }
    if (widget.fadeBottomEdge) {
      column = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFFFFFFF),
            const Color(0xFFFFFFFF),
            Color(streaming ? 0x00FFFFFF : 0xFFFFFFFF),
          ],
          stops: [
            0,
            bounds.height <= 0
                ? 0
                : math.max(0, 1 - 32 / bounds.height).toDouble(),
            1,
          ],
        ).createShader(bounds),
        child: column,
      );
    }
    if (widget.autoScrollController != null) {
      // A picture that loads late makes the reply taller without any new
      // text; keep following then too.
      column = NotificationListener<SizeChangedLayoutNotification>(
        onNotification: (notification) {
          _followEnd();
          return true;
        },
        child: SizeChangedLayoutNotifier(child: column),
      );
    }
    if (!widget.tapToSkip) return column;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: streaming ? _skip : null,
      child: column,
    );
  }
}
