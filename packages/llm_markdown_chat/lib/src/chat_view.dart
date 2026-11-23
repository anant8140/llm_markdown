import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:llm_markdown/llm_markdown.dart';

import 'chat_controller.dart';
import 'plain_button.dart';
import 'sse_backend.dart';

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
    this.like = 'Good reply',
    this.dislike = 'Bad reply',
    this.edit = 'Edit',
    this.editing = 'Editing message',
    this.cancel = 'Cancel',
    this.attach = 'Attach',
    this.removeAttachment = 'Remove',
    this.voice = 'Voice input',
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

  /// The thumbs-up button under a reply, for screen readers.
  final String like;

  /// The thumbs-down button under a reply, for screen readers.
  final String dislike;

  /// The button under a user's message that puts it back in the input box.
  final String edit;

  /// Shown above the input box while a message is edited.
  final String editing;

  /// The button that ends editing without sending.
  final String cancel;

  /// The button that picks attachments.
  final String attach;

  /// The button that takes a picked attachment out again; screen readers
  /// hear it followed by the attachment's name.
  final String removeAttachment;

  /// The microphone button.
  final String voice;
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
    this.errorColor = const Color(0xFFB3261E),
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

  /// The text of a reply's error.
  final Color errorColor;

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
    this.welcome,
    this.emptyBuilder,
    this.userMessageBuilder,
    this.replyBuilder,
    this.errorBuilder,
    this.onLinkTap,
    this.showCopy = true,
    this.copyPlainText = false,
    this.showRegenerate = true,
    this.onFeedback,
    this.messageActionsBuilder,
    this.showEdit = true,
    this.onPickAttachment,
    this.attachmentBuilder,
    this.onVoiceInput,
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

  /// Shown while the chat is empty, above the [suggestions], for example
  /// a greeting.
  final Widget? welcome;

  /// Builds what is shown while the chat is empty, above the
  /// [suggestions]; used instead of [welcome] when both are given.
  final WidgetBuilder? emptyBuilder;

  /// Builds a message of the user, instead of the default bubble.
  final Widget Function(BuildContext context, ChatMessage message)?
  userMessageBuilder;

  /// Builds a reply of the model, instead of the default
  /// `StreamingMarkdown(controller: message.reply!)`, for example to pass
  /// more options to it.
  final Widget Function(BuildContext context, ChatMessage message)?
  replyBuilder;

  /// Builds what is shown under a reply that ended with an error, instead
  /// of the error's text ([chatErrorText]). With a [replyBuilder] the
  /// error is only shown when this is given, as the builder may show it
  /// itself.
  final Widget Function(BuildContext context, ChatMessage message)?
  errorBuilder;

  /// Called with the address of a tapped link in a reply.
  final ValueChanged<String>? onLinkTap;

  /// Whether a finished reply has a copy button.
  final bool showCopy;

  /// Whether the copy button copies the reply as plain text, without the
  /// Markdown marks, instead of the Markdown as the model wrote it.
  final bool copyPlainText;

  /// Whether the last reply has a button that asks for it again.
  final bool showRegenerate;

  /// Called when the thumbs-up (`isPositive` true) or thumbs-down button
  /// under a reply is tapped. The buttons are shown only when this is
  /// given.
  final void Function(ChatMessage message, bool isPositive)? onFeedback;

  /// Builds what is shown under a finished reply, instead of the copy,
  /// try again and feedback buttons.
  final Widget Function(BuildContext context, ChatMessage message)?
  messageActionsBuilder;

  /// Whether a user's message has an edit button. It puts the text back
  /// in the input box; sending then replaces that message and everything
  /// after it, and asks again.
  final bool showEdit;

  /// Picks attachments, for example with a file or image picker plugin.
  /// When given, the input box has an attach button; what this returns is
  /// listed above the input, can be removed there, and goes out with the
  /// next message as its [ChatMessage.attachments].
  final Future<List<ChatAttachment>> Function()? onPickAttachment;

  /// Builds one attachment, above the input and in the user's message,
  /// instead of a chip with its name.
  final Widget Function(BuildContext context, ChatAttachment attachment)?
  attachmentBuilder;

  /// Listens to the user and gives the words, for example with a speech
  /// plugin; `null` when nothing was heard. When given, the input box has
  /// a microphone button, and the words are put in the input.
  final Future<String?> Function()? onVoiceInput;

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
  // the thumbs chosen for each reply, by message id
  final _feedback = <String, bool>{};
  // picked, not sent yet
  List<ChatAttachment> _attachments = [];
  // the user's message that the next send replaces
  ChatMessage? _editing;
  bool _picking = false;
  bool _listening = false;

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
      // another chat: what was typed for the old one stays behind
      _editing = null;
      _attachments = [];
      _feedback.clear();
      _input.clear();
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

  void _changed() => setState(() {
    final editing = _editing;
    // the edited message is gone, for example after clear()
    if (editing != null && !widget.controller.messages.contains(editing)) {
      _editing = null;
    }
  });

  // Sends [text] (a suggestion), or what is in the input box.
  void _send([String? text]) {
    final chat = widget.controller;
    if (chat.isReplying) return;
    if (text != null) {
      if (text.trim().isEmpty) return;
      unawaited(chat.send(text));
      _focus.requestFocus();
      return;
    }
    final prompt = _input.text.trim();
    final attachments = _attachments;
    if (prompt.isEmpty && attachments.isEmpty) return;
    final editing = _editing;
    _editing = null;
    _attachments = [];
    _input.clear();
    if (editing != null && chat.canEdit(editing)) {
      unawaited(chat.edit(editing, prompt, attachments: attachments));
    } else {
      unawaited(chat.send(prompt, attachments: attachments));
    }
    _focus.requestFocus();
  }

  void _startEdit(ChatMessage message) {
    setState(() {
      _editing = message;
      _attachments = List.of(message.attachments);
      _input.value = TextEditingValue(
        text: message.text,
        selection: TextSelection.collapsed(offset: message.text.length),
      );
    });
    _focus.requestFocus();
  }

  void _cancelEdit() {
    setState(() {
      _editing = null;
      _attachments = [];
      _input.clear();
    });
  }

  Future<void> _pick() async {
    final pick = widget.onPickAttachment;
    if (pick == null || _picking) return;
    setState(() => _picking = true);
    try {
      final picked = await pick();
      if (mounted) setState(() => _attachments = [..._attachments, ...picked]);
    } catch (error, stackTrace) {
      _report(error, stackTrace);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _voice() async {
    final listen = widget.onVoiceInput;
    if (listen == null || _listening) return;
    setState(() => _listening = true);
    try {
      final heard = (await listen())?.trim() ?? '';
      if (mounted && heard.isNotEmpty) {
        final old = _input.text;
        final joined = old.isEmpty || old.endsWith(' ') || old.endsWith('\n')
            ? '$old$heard'
            : '$old $heard';
        _input.value = TextEditingValue(
          text: joined,
          selection: TextSelection.collapsed(offset: joined.length),
        );
        _focus.requestFocus();
      }
    } catch (error, stackTrace) {
      _report(error, stackTrace);
    } finally {
      if (mounted) setState(() => _listening = false);
    }
  }

  // An error of the app's picker or speech callback: told to Flutter, the
  // chat goes on.
  void _report(Object error, StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'llm_markdown_chat',
      ),
    );
  }

  void _rate(ChatMessage message, bool isPositive) {
    setState(() => _feedback[message.id] = isPositive);
    widget.onFeedback?.call(message, isPositive);
  }

  void _copy(ChatMessage message) {
    final text = widget.copyPlainText
        ? message.reply?.plainText ?? message.text
        : message.text;
    unawaited(Clipboard.setData(ClipboardData(text: text)));
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
    final header = widget.emptyBuilder?.call(context) ?? widget.welcome;
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
                  PlainButton(
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
    final bubble = custom != null
        ? custom(context, message)
        : _bubble(message, style);
    if (!widget.showEdit || !widget.controller.canEdit(message)) return bubble;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        bubble,
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: PlainButton(
              label: widget.labels.edit,
              onTap: () => _startEdit(message),
              child: Text(widget.labels.edit, style: _faint(style)),
            ),
          ),
        ),
      ],
    );
  }

  TextStyle _faint(LlmChatStyle style) => style.textStyle.copyWith(
    color: style.textStyle.color?.withValues(alpha: 0.6),
    fontSize: (style.textStyle.fontSize ?? 14) * 0.9,
  );

  Widget _bubble(ChatMessage message, LlmChatStyle style) {
    final attachments = message.attachments;
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
            child: attachments.isEmpty
                ? Text(message.text)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final attachment in attachments)
                            _attachment(context, attachment, style),
                        ],
                      ),
                      if (message.text.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(message.text),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  // One attachment: the app's widget, or a chip with its name.
  Widget _attachment(
    BuildContext context,
    ChatAttachment attachment,
    LlmChatStyle style,
  ) {
    final custom = widget.attachmentBuilder;
    if (custom != null) return custom(context, attachment);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: style.borderColor),
        borderRadius: BorderRadius.circular(style.radius),
      ),
      child: Text(
        attachment.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _faint(style),
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
        final error = reply.error;
        final errorBuilder = widget.errorBuilder;
        final showError =
            done &&
            error != null &&
            (errorBuilder != null || widget.replyBuilder == null);
        final actions = done ? _actions(context, message, style, last) : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            body,
            if (showError)
              Padding(
                padding: EdgeInsets.only(top: reply.text.isEmpty ? 0 : 6),
                child:
                    errorBuilder?.call(context, message) ??
                    Text(
                      chatErrorText(error),
                      style: style.textStyle.copyWith(color: style.errorColor),
                    ),
              ),
            if (actions != null)
              Padding(padding: const EdgeInsets.only(top: 6), child: actions),
          ],
        );
      },
    );
  }

  // What is under a finished reply, or null for nothing.
  Widget? _actions(
    BuildContext context,
    ChatMessage message,
    LlmChatStyle style,
    bool last,
  ) {
    final custom = widget.messageActionsBuilder;
    if (custom != null) return custom(context, message);
    final labels = widget.labels;
    final hasText = message.text.isNotEmpty;
    final copied = _copiedId == message.id;
    final faint = _faint(style);
    final rated = _feedback[message.id];
    final buttons = [
      if (widget.showCopy && hasText)
        PlainButton(
          label: copied ? labels.copied : labels.copy,
          onTap: () => _copy(message),
          child: Text(copied ? labels.copied : labels.copy, style: faint),
        ),
      if (widget.showRegenerate && last && widget.controller.canRetry)
        PlainButton(
          label: labels.retry,
          onTap: () => unawaited(widget.controller.retry()),
          child: Text(labels.retry, style: faint),
        ),
      if (widget.onFeedback != null && hasText && !message.hasError)
        for (final positive in const [true, false])
          PlainButton(
            label: positive ? labels.like : labels.dislike,
            selected: rated == positive,
            onTap: () => _rate(message, positive),
            child: Opacity(
              opacity: rated == positive ? 1 : 0.55,
              child: Text(
                positive ? '\u{1F44D}' : '\u{1F44E}',
                style: style.textStyle,
              ),
            ),
          ),
    ];
    if (buttons.isEmpty) return null;
    return Wrap(
      spacing: 16,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: buttons,
    );
  }

  Widget _inputBar(LlmChatStyle style) {
    final replying = widget.controller.isReplying;
    final canSend =
        !replying && (_input.text.trim().isNotEmpty || _attachments.isNotEmpty);
    final canAttach = widget.onPickAttachment != null;
    final iconColor =
        style.textStyle.color?.withValues(alpha: 0.7) ?? style.accentColor;
    final hint = style.textStyle.copyWith(
      color: style.textStyle.color?.withValues(alpha: 0.5),
    );
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (canAttach) ...[
          PlainButton(
            label: widget.labels.attach,
            onTap: _picking ? null : () => unawaited(_pick()),
            child: SizedBox(
              width: 36,
              height: 36,
              child: CustomPaint(
                painter: PlainIconPainter(
                  icon: PlainIcon.add,
                  color: iconColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Focus(
              // Enter sends, Shift+Enter starts a new line
              onKeyEvent: (node, event) {
                final enter =
                    event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.numpadEnter;
                if (!enter || event is KeyUpEvent) {
                  return KeyEventResult.ignored;
                }
                // Enter that picks a candidate of an input method
                // (Chinese, Japanese, ...) is the input method's
                final composing = _input.value.composing;
                if (composing.isValid && !composing.isCollapsed) {
                  return KeyEventResult.ignored;
                }
                if (HardwareKeyboard.instance.isShiftPressed) {
                  return KeyEventResult.ignored;
                }
                // a held Enter sends once and adds no new lines
                if (event is KeyDownEvent) _send();
                return KeyEventResult.handled;
              },
              // one node: the text field, named by the hint
              child: MergeSemantics(
                child: Semantics(
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
        ),
        const SizedBox(width: 8),
        if (widget.onVoiceInput != null) ...[
          PlainButton(
            label: widget.labels.voice,
            onTap: _listening ? null : () => unawaited(_voice()),
            child: SizedBox(
              width: 36,
              height: 36,
              child: CustomPaint(
                painter: PlainIconPainter(
                  icon: PlainIcon.mic,
                  color: _listening ? style.accentColor : iconColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
        PlainButton(
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
              painter: PlainIconPainter(
                icon: replying ? PlainIcon.stop : PlainIcon.send,
                color: style.onAccentColor,
              ),
            ),
          ),
        ),
      ],
    );
    return Padding(
      padding: style.padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_editing != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: 16,
                end: 16,
                bottom: 6,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.labels.editing, style: _faint(style)),
                  ),
                  PlainButton(
                    label: widget.labels.cancel,
                    onTap: _cancelEdit,
                    child: Text(widget.labels.cancel, style: _faint(style)),
                  ),
                ],
              ),
            ),
          Container(
            padding: EdgeInsetsDirectional.fromSTEB(
              canAttach ? 6 : 16,
              6,
              6,
              6,
            ),
            decoration: BoxDecoration(
              color: style.inputColor,
              border: Border.all(color: style.borderColor),
              borderRadius: BorderRadius.circular(style.radius + 6),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_attachments.isNotEmpty)
                  Padding(
                    padding: EdgeInsetsDirectional.only(
                      start: canAttach ? 10 : 0,
                      top: 4,
                      bottom: 4,
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (var i = 0; i < _attachments.length; i++)
                          _picked(i, style, iconColor),
                      ],
                    ),
                  ),
                row,
              ],
            ),
          ),
        ],
      ),
    );
  }

  // A picked attachment above the input, with a button that removes it.
  Widget _picked(int index, LlmChatStyle style, Color iconColor) {
    final attachment = _attachments[index];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: _attachment(context, attachment, style)),
        PlainButton(
          label: '${widget.labels.removeAttachment} ${attachment.name}',
          onTap: () => setState(
            () => _attachments = List.of(_attachments)..removeAt(index),
          ),
          child: SizedBox(
            width: 24,
            height: 24,
            child: CustomPaint(
              painter: PlainIconPainter(
                icon: PlainIcon.close,
                color: iconColor,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
