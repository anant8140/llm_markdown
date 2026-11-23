import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:llm_markdown/llm_markdown.dart';

import 'chat_controller.dart';

/// The words [LlmChatView] shows and reads to screen readers.
class LlmChatLabels {
  /// Labels in English, or the ones given.
  const LlmChatLabels({
    this.hint = 'Message',
    this.send = 'Send',
    this.stop = 'Stop',
    this.copy = 'Copy',
    this.copied = 'Copied',
    this.retry = 'Try again',
  });

  /// Shown in the empty input box.
  final String hint;

  /// The send button.
  final String send;

  /// The button that ends the reply being written.
  final String stop;

  /// The button that copies a reply.
  final String copy;

  /// Shown for a moment after copying.
  final String copied;

  /// The button under the last reply that asks for it again.
  final String retry;
}

/// The look of [LlmChatView]. [LlmChatStyle.of] follows the surrounding
/// text style and accent color, like `llm_markdown` does.
class LlmChatStyle {
  /// A style from these values.
  const LlmChatStyle({
    required this.textStyle,
    required this.accentColor,
    required this.userBubbleColor,
    required this.inputColor,
    required this.borderColor,
    this.onAccentColor = const Color(0xFFFFFFFF),
    this.radius = 18,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.spacing = 16,
    this.maxUserBubbleWidth = 0.8,
    this.markdownStyle,
  });

  /// The style for [context].
  factory LlmChatStyle.of(BuildContext context) {
    final markdown = StreamingMarkdownStyle.of(context);
    return LlmChatStyle(
      textStyle: markdown.textStyle,
      accentColor: markdown.accentColor,
      userBubbleColor: markdown.tableHeaderColor,
      inputColor: markdown.tableHeaderColor,
      borderColor: markdown.dividerColor,
      markdownStyle: markdown,
    );
  }

  /// The text of the user's messages and the input box.
  final TextStyle textStyle;

  /// The send button, the cursor and the suggestions' border.
  final Color accentColor;

  /// The icon on the send button.
  final Color onAccentColor;

  /// The background of the user's messages.
  final Color userBubbleColor;

  /// The background of the input box.
  final Color inputColor;

  /// The border of the input box and the suggestions.
  final Color borderColor;

  /// The corner radius of bubbles, the input box and buttons.
  final double radius;

  /// The space around the messages and the input box.
  final EdgeInsets padding;

  /// The space between messages.
  final double spacing;

  /// The widest a user's message gets, as a part of the width.
  final double maxUserBubbleWidth;

  /// The look of the replies.
  final StreamingMarkdownStyle? markdownStyle;
}

/// A whole chat screen: the messages, with the replies streaming in as
/// Markdown, and an input box with send and stop.
///
/// ```dart
/// LlmChatView(controller: chat, suggestions: ['What can you do?'])
/// ```
///
/// Made of plain widgets, so it fits a Material, Cupertino or any other
/// app; it needs a [Directionality] and a [MediaQuery] above it, which
/// every app widget gives.
class LlmChatView extends StatefulWidget {
  /// A chat screen for [controller].
  const LlmChatView({
    super.key,
    required this.controller,
    this.style,
    this.labels = const LlmChatLabels(),
    this.suggestions = const [],
    this.emptyBuilder,
    this.userMessageBuilder,
    this.replyBuilder,
    this.onLinkTap,
    this.autofocus = false,
    this.maxInputLines = 6,
  });

  /// The messages, and where new ones are sent.
  final LlmChatController controller;

  /// The look; defaults to [LlmChatStyle.of] the context.
  final LlmChatStyle? style;

  /// The words shown and read to screen readers.
  final LlmChatLabels labels;

  /// Prompts offered while the chat is empty; a tap sends one.
  final List<String> suggestions;

  /// Shown while the chat is empty, above the [suggestions].
  final WidgetBuilder? emptyBuilder;

  /// Builds a message of the user, instead of the default bubble.
  final Widget Function(BuildContext context, ChatMessage message)?
  userMessageBuilder;

  /// Builds a reply of the model, instead of the default
  /// `StreamingMarkdown(controller: message.reply!)`, for example to pass
  /// more options to it.
  final Widget Function(BuildContext context, ChatMessage message)?
  replyBuilder;

  /// Called with the address of a tapped link in a reply.
  final ValueChanged<String>? onLinkTap;

  /// Whether the input box takes the focus when the screen opens.
  final bool autofocus;

  /// The most lines the input box grows to before it scrolls.
  final int maxInputLines;

  @override
  State<LlmChatView> createState() => _LlmChatViewState();
}

class _LlmChatViewState extends State<LlmChatView> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  String? _copiedId;
  Timer? _copiedTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _input.addListener(_changed);
  }

  @override
  void didUpdateWidget(LlmChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _copiedTimer?.cancel();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  void _send([String? text]) {
    final prompt = (text ?? _input.text).trim();
    if (prompt.isEmpty || widget.controller.isReplying) return;
    if (text == null) _input.clear();
    unawaited(widget.controller.send(prompt));
    _focus.requestFocus();
  }

  void _copy(ChatMessage message) {
    unawaited(Clipboard.setData(ClipboardData(text: message.text)));
    _copiedTimer?.cancel();
    setState(() => _copiedId = message.id);
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiedId = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? LlmChatStyle.of(context);
    final messages = widget.controller.messages;
    return DefaultTextStyle.merge(
      style: style.textStyle,
      child: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? _empty(context, style)
                : ListView.builder(
                    // newest at the bottom, and the bottom stays in view
                    // while a reply grows
                    reverse: true,
                    padding: style.padding,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[messages.length - 1 - index];
                      return Padding(
                        key: ValueKey(message.id),
                        padding: EdgeInsets.only(
                          top: index == messages.length - 1 ? 0 : style.spacing,
                        ),
                        child: message.role == ChatRole.user
                            ? _user(context, message, style)
                            : _reply(context, message, style, index == 0),
                      );
                    },
                  ),
          ),
          _inputBar(style),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, LlmChatStyle style) {
    final header = widget.emptyBuilder?.call(context);
    return Center(
      child: SingleChildScrollView(
        padding: style.padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?header,
            if (header != null && widget.suggestions.isNotEmpty)
              SizedBox(height: style.spacing),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final suggestion in widget.suggestions)
                  _Button(
                    label: suggestion,
                    onTap: () => _send(suggestion),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: style.borderColor),
                        borderRadius: BorderRadius.circular(style.radius),
                      ),
                      child: Text(suggestion),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _user(BuildContext context, ChatMessage message, LlmChatStyle style) {
    final custom = widget.userMessageBuilder;
    if (custom != null) return custom(context, message);
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: AlignmentDirectional.centerEnd,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: constraints.maxWidth * style.maxUserBubbleWidth,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: style.userBubbleColor,
              borderRadius: BorderRadius.circular(style.radius),
            ),
            child: Text(message.text),
          ),
        ),
      ),
    );
  }

  Widget _reply(
    BuildContext context,
    ChatMessage message,
    LlmChatStyle style,
    bool last,
  ) {
    final reply = message.reply!;
    final body =
        widget.replyBuilder?.call(context, message) ??
        StreamingMarkdown(
          controller: reply,
          style: style.markdownStyle,
          onLinkTap: widget.onLinkTap,
        );
    return ListenableBuilder(
      listenable: reply,
      builder: (context, _) {
        final done = reply.isComplete;
        final canRetry = last && widget.controller.canRetry;
        final copied = _copiedId == message.id;
        final faint = style.textStyle.copyWith(
          color: style.textStyle.color?.withValues(alpha: 0.6),
          fontSize: (style.textStyle.fontSize ?? 14) * 0.9,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            body,
            if (done && (reply.text.isNotEmpty || canRetry))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 16,
                  children: [
                    if (reply.text.isNotEmpty)
                      _Button(
                        label: copied
                            ? widget.labels.copied
                            : widget.labels.copy,
                        onTap: () => _copy(message),
                        child: Text(
                          copied ? widget.labels.copied : widget.labels.copy,
                          style: faint,
                        ),
                      ),
                    if (canRetry)
                      _Button(
                        label: widget.labels.retry,
                        onTap: () => unawaited(widget.controller.retry()),
                        child: Text(widget.labels.retry, style: faint),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _inputBar(LlmChatStyle style) {
    final replying = widget.controller.isReplying;
    final canSend = !replying && _input.text.trim().isNotEmpty;
    final hint = style.textStyle.copyWith(
      color: style.textStyle.color?.withValues(alpha: 0.5),
    );
    return Padding(
      padding: style.padding,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 6, 6),
        decoration: BoxDecoration(
          color: style.inputColor,
          border: Border.all(color: style.borderColor),
          borderRadius: BorderRadius.circular(style.radius + 6),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Focus(
                  // Enter sends, Shift+Enter starts a new line
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent &&
                        (event.logicalKey == LogicalKeyboardKey.enter ||
                            event.logicalKey ==
                                LogicalKeyboardKey.numpadEnter) &&
                        !HardwareKeyboard.instance.isShiftPressed) {
                      _send();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Semantics(
                    container: true,
                    label: widget.labels.hint,
                    child: Stack(
                      children: [
                        if (_input.text.isEmpty)
                          ExcludeSemantics(
                            child: IgnorePointer(
                              child: Text(
                                widget.labels.hint,
                                style: hint,
                                maxLines: 1,
                              ),
                            ),
                          ),
                        EditableText(
                          controller: _input,
                          focusNode: _focus,
                          autofocus: widget.autofocus,
                          style: style.textStyle,
                          cursorColor: style.accentColor,
                          backgroundCursorColor: style.borderColor,
                          selectionColor: style.accentColor.withValues(
                            alpha: 0.3,
                          ),
                          minLines: 1,
                          maxLines: widget.maxInputLines,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _Button(
              label: replying ? widget.labels.stop : widget.labels.send,
              onTap: replying
                  ? widget.controller.stop
                  : canSend
                  ? _send
                  : null,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: replying || canSend
                      ? style.accentColor
                      : style.accentColor.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
                child: CustomPaint(
                  painter: _IconPainter(
                    stop: replying,
                    color: style.onAccentColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tappable, focusable button for screen readers and keyboards.
class _Button extends StatelessWidget {
  const _Button({
    required this.label,
    required this.onTap,
    required this.child,
  });

  final String label;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    return Semantics(
      container: true,
      button: true,
      enabled: tap != null,
      label: label,
      excludeSemantics: true,
      onTap: tap,
      child: FocusableActionDetector(
        enabled: tap != null,
        mouseCursor: tap != null
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              tap?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: tap,
          child: child,
        ),
      ),
    );
  }
}

/// An arrow pointing up (send) or a square (stop).
class _IconPainter extends CustomPainter {
  const _IconPainter({required this.stop, required this.color});

  final bool stop;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    if (stop) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: 12, height: 12),
          const Radius.circular(2),
        ),
        Paint()..color = color,
      );
      return;
    }
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas
      ..drawLine(center.translate(0, 7), center.translate(0, -7), paint)
      ..drawPath(
        Path()
          ..moveTo(center.dx - 6, center.dy - 1)
          ..lineTo(center.dx, center.dy - 7)
          ..lineTo(center.dx + 6, center.dy - 1),
        paint,
      );
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.stop != stop || old.color != color;
}
