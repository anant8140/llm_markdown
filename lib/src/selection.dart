import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// An extra button in the menu of a [MarkdownSelectionArea], such as
/// "Ask about this" or "Quote".
@immutable
class MarkdownSelectionAction {
  /// Creates a menu button that is given the selected text.
  const MarkdownSelectionAction({
    required this.label,
    required this.onSelected,
  });

  /// The text of the button.
  final String label;

  /// Called with the selected text when the button is tapped.
  final ValueChanged<String> onSelected;
}

/// One button of the selection menu, for a custom [MarkdownSelectionArea.menuBuilder].
@immutable
class MarkdownSelectionMenuItem {
  /// Creates a menu item.
  const MarkdownSelectionMenuItem({
    required this.label,
    required this.onPressed,
  });

  /// The text of the button.
  final String label;

  /// What the button does; it also closes the menu where that is expected.
  final VoidCallback onPressed;
}

/// Builds the whole selection menu. [anchors] says where the selection is:
/// its `primaryAnchor` is above it, its `secondaryAnchor` below.
typedef MarkdownSelectionMenuBuilder =
    Widget Function(
      BuildContext context,
      List<MarkdownSelectionMenuItem> items,
      TextSelectionToolbarAnchors anchors,
    );

/// Makes the replies inside it selectable, with a menu for the selection:
/// Copy, Select all and your own [actions].
///
/// ```dart
/// MarkdownSelectionArea(
///   actions: [
///     MarkdownSelectionAction(
///       label: 'Ask about this',
///       onSelected: (text) => askAbout(text),
///     ),
///   ],
///   child: ListView(children: [for (final m in messages) reply(m)]),
/// )
/// ```
///
/// It needs nothing from a design library. If the app already has a
/// Material or Cupertino `SelectionArea` and its look is wanted, that works
/// with `StreamingMarkdown` too; this widget is for a menu with your own
/// buttons without writing a `contextMenuBuilder`.
class MarkdownSelectionArea extends StatefulWidget {
  /// Makes [child] selectable.
  const MarkdownSelectionArea({
    super.key,
    required this.child,
    this.actions = const [],
    this.onSelectionChanged,
    this.copyLabel = 'Copy',
    this.selectAllLabel = 'Select all',
    this.focusNode,
    this.menuColor = const Color(0xFF2B2D31),
    this.menuTextStyle,
    this.menuBorderRadius = const BorderRadius.all(Radius.circular(8)),
    this.handleColor,
    this.menuBuilder,
  });

  /// The chat, a reply, or anything else with text in it.
  final Widget child;

  /// Buttons added after Copy and Select all.
  final List<MarkdownSelectionAction> actions;

  /// Called with the selected text when it changes; empty when nothing is
  /// selected.
  final ValueChanged<String>? onSelectionChanged;

  /// The label of the copy button, for other languages.
  final String copyLabel;

  /// The label of the select all button, for other languages.
  final String selectAllLabel;

  /// The focus node of the selection; one is made when not given.
  final FocusNode? focusNode;

  /// The background of the menu.
  final Color menuColor;

  /// Merged onto the text of the menu's buttons, which is light by default.
  final TextStyle? menuTextStyle;

  /// The corners of the menu.
  final BorderRadius menuBorderRadius;

  /// The drag handles at the ends of the selection on touch screens;
  /// defaults to the cursor color of the surrounding
  /// [DefaultSelectionStyle].
  final Color? handleColor;

  /// Builds the menu yourself, for example with your design library's
  /// toolbar; the colors above are then not used.
  final MarkdownSelectionMenuBuilder? menuBuilder;

  @override
  State<MarkdownSelectionArea> createState() => _MarkdownSelectionAreaState();
}

class _MarkdownSelectionAreaState extends State<MarkdownSelectionArea> {
  FocusNode? _ownFocusNode;
  String _selected = '';

  FocusNode get _focusNode =>
      widget.focusNode ??
      (_ownFocusNode ??= FocusNode(debugLabel: 'MarkdownSelectionArea'));

  @override
  void dispose() {
    _ownFocusNode?.dispose();
    super.dispose();
  }

  Widget _menu(BuildContext context, SelectableRegionState region) {
    MarkdownSelectionMenuItem button(String label, VoidCallback onPressed) =>
        MarkdownSelectionMenuItem(label: label, onPressed: onPressed);
    final items = [
      for (final item in region.contextMenuButtonItems)
        if (item.onPressed != null)
          if (item.type == ContextMenuButtonType.copy)
            button(widget.copyLabel, item.onPressed!)
          else if (item.type == ContextMenuButtonType.selectAll)
            button(widget.selectAllLabel, item.onPressed!)
          else if (item.label != null)
            button(item.label!, item.onPressed!),
      if (_selected.isNotEmpty)
        for (final action in widget.actions)
          button(action.label, () {
            final text = _selected;
            region.hideToolbar();
            action.onSelected(text);
          }),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    final anchors = region.contextMenuAnchors;
    final custom = widget.menuBuilder;
    if (custom != null) return custom(context, items, anchors);
    return SelectionMenu(
      anchors: anchors,
      items: items,
      color: widget.menuColor,
      textStyle: widget.menuTextStyle,
      borderRadius: widget.menuBorderRadius,
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent =
        widget.handleColor ??
        DefaultSelectionStyle.of(context).cursorColor ??
        const Color(0xFF1A73E8);
    return SelectableRegion(
      focusNode: _focusNode,
      selectionControls: _HandleControls(accent),
      contextMenuBuilder: _menu,
      onSelectionChanged: (content) {
        _selected = content?.plainText ?? '';
        widget.onSelectionChanged?.call(_selected);
      },
      child: widget.child,
    );
  }
}

/// The floating row of buttons above (or below) the selection.
class SelectionMenu extends StatelessWidget {
  const SelectionMenu({
    super.key,
    required this.anchors,
    required this.items,
    required this.color,
    required this.borderRadius,
    this.textStyle,
  });

  final TextSelectionToolbarAnchors anchors;
  final List<MarkdownSelectionMenuItem> items;
  final Color color;
  final BorderRadius borderRadius;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final top = (media?.padding.top ?? 0) + 8;
    final above = anchors.primaryAnchor - const Offset(0, 10);
    final below =
        (anchors.secondaryAnchor ?? anchors.primaryAnchor) +
        const Offset(0, 26);
    final text = const TextStyle(
      color: Color(0xFFF2F2F2),
      fontSize: 14,
      height: 1.2,
      fontWeight: FontWeight.w500,
      decoration: TextDecoration.none,
    ).merge(textStyle);
    return Padding(
      padding: EdgeInsets.fromLTRB(8, top, 8, 8),
      child: CustomSingleChildLayout(
        delegate: TextSelectionToolbarLayoutDelegate(
          anchorAbove: above - Offset(8, top),
          anchorBelow: below - Offset(8, top),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: borderRadius,
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: borderRadius,
            // many buttons on a narrow screen scroll sideways
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0)
                      SizedBox(
                        width: 1,
                        height: 20,
                        child: ColoredBox(
                          color: (text.color ?? const Color(0xFFFFFFFF))
                              .withValues(alpha: 0.2),
                        ),
                      ),
                    Semantics(
                      button: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: items[i].onPressed,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Text(items[i].label, style: text),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const double _handleSize = 18;

// Round drag handles under the ends of the selection, for touch screens.
class _HandleControls extends TextSelectionControls
    with TextSelectionHandleControls {
  _HandleControls(this.color);

  final Color color;

  @override
  Size getHandleSize(double textLineHeight) =>
      const Size(_handleSize, _handleSize);

  @override
  Offset getHandleAnchor(TextSelectionHandleType type, double textLineHeight) =>
      switch (type) {
        TextSelectionHandleType.left => const Offset(_handleSize, 0),
        TextSelectionHandleType.right => Offset.zero,
        TextSelectionHandleType.collapsed => const Offset(_handleSize / 2, 0),
      };

  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textLineHeight, [
    VoidCallback? onTap,
  ]) {
    // a drop whose point touches the end of the selection
    const round = Radius.circular(_handleSize / 2);
    final shape = switch (type) {
      TextSelectionHandleType.left => const BorderRadius.only(
        topLeft: round,
        bottomLeft: round,
        bottomRight: round,
      ),
      TextSelectionHandleType.right => const BorderRadius.only(
        topRight: round,
        bottomLeft: round,
        bottomRight: round,
      ),
      TextSelectionHandleType.collapsed => const BorderRadius.all(round),
    };
    final handle = SizedBox.square(
      dimension: _handleSize,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, borderRadius: shape),
      ),
    );
    if (type != TextSelectionHandleType.collapsed) return handle;
    return Transform.rotate(angle: math.pi / 4, child: handle);
  }
}
