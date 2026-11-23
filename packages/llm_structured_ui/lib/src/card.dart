import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'auto.dart';
import 'builder.dart';
import 'fields.dart';
import 'indicators.dart';
import 'style.dart';
import 'text.dart';
import 'value.dart';

/// Shows an object as a card with a title, subtitle, body and footer.
///
/// Each part is either the name of a key of the object (shown as text) or
/// a builder. A part whose key has not arrived shows a placeholder line
/// while the object is being written, and nothing once it is finished.
/// Without [body] and [bodyBuilder], the body is a [StructuredFields] of
/// the keys that no other part uses.
///
/// ```dart
/// StructuredCard(data, title: 'name', subtitle: 'cuisine', body: 'summary')
/// ```
class StructuredCard extends StatelessWidget {
  /// A card for [value].
  const StructuredCard(
    this.value, {
    super.key,
    this.title,
    this.titleBuilder,
    this.subtitle,
    this.subtitleBuilder,
    this.body,
    this.bodyBuilder,
    this.bodyMarkdown = false,
    this.footer,
    this.footerBuilder,
    this.semanticLabel,
    this.style,
  });

  /// The object to show.
  final StructuredValue value;

  /// The key whose value is the title.
  final String? title;

  /// Builds the title from [value]; used instead of [title].
  final StructuredWidgetBuilder? titleBuilder;

  /// The key whose value is the subtitle.
  final String? subtitle;

  /// Builds the subtitle from [value]; used instead of [subtitle].
  final StructuredWidgetBuilder? subtitleBuilder;

  /// The key whose value is the body.
  final String? body;

  /// Builds the body from [value]; used instead of [body].
  final StructuredWidgetBuilder? bodyBuilder;

  /// Whether the text under the [body] key is Markdown.
  final bool bodyMarkdown;

  /// The key whose value is the footer.
  final String? footer;

  /// Builds the footer from [value]; used instead of [footer].
  final StructuredWidgetBuilder? footerBuilder;

  /// What a screen reader says for the card as a whole, if anything.
  final String? semanticLabel;

  /// The look; defaults to [StructuredStyle.of] the context.
  final StructuredStyle? style;

  Widget? _part(
    BuildContext context,
    StructuredStyle style,
    String? key,
    StructuredWidgetBuilder? builder,
    TextStyle textStyle, {
    bool markdown = false,
  }) {
    if (builder != null) return builder(context, value);
    if (key == null) return null;
    final part = value[key];
    final fontSize = textStyle.fontSize ?? 14;
    final placeholder = StructuredPlaceholder(
      height: fontSize * 0.8,
      color: style.placeholderColor,
    );
    if (!part.exists) {
      final awaited = part.isAwaited;
      return awaited ? placeholder : null;
    }
    if (part.isMap || part.isList) return StructuredAuto(part, style: style);
    if (part.isPending && StructuredText.textOf(part).isEmpty) {
      return placeholder;
    }
    return StructuredText(
      part,
      markdown: markdown,
      textStyle: textStyle,
      style: style,
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = this.style ?? StructuredStyle.of(context);
    final titleWidget = _part(
      context,
      style,
      title,
      titleBuilder,
      style.titleStyle,
    );
    final subtitleWidget = _part(
      context,
      style,
      subtitle,
      subtitleBuilder,
      style.subtitleStyle,
    );
    Widget? bodyWidget = _part(
      context,
      style,
      body,
      bodyBuilder,
      style.textStyle,
      markdown: bodyMarkdown,
    );
    if (body == null && bodyBuilder == null) {
      final used = {?title, ?subtitle, ?footer};
      if (value.asMap.keys.any((key) => !used.contains(key))) {
        bodyWidget = StructuredFields(value, hide: used, style: style);
      }
    }
    final footerWidget = _part(
      context,
      style,
      footer,
      footerBuilder,
      style.subtitleStyle,
    );
    final parts = <Widget>[
      if (titleWidget != null) Semantics(header: true, child: titleWidget),
      ?subtitleWidget,
      ?bodyWidget,
      ?footerWidget,
    ];
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: FillWidth(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: style.cardColor,
            border: Border.all(color: style.cardBorderColor),
            borderRadius: BorderRadius.circular(style.cardRadius),
          ),
          child: Padding(
            padding: style.cardPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < parts.length; i++) ...[
                  if (i > 0) SizedBox(height: style.spacing),
                  parts[i],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Makes its child as wide as the space there is, and leaves it alone
/// where the width has no limit (so it also works in a `Row` or a
/// sideways scroll view).
class FillWidth extends SingleChildRenderObjectWidget {
  /// Stretches [child] sideways.
  const FillWidth({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFillWidth();
}

class _RenderFillWidth extends RenderProxyBox {
  BoxConstraints _fill(BoxConstraints constraints) =>
      constraints.hasBoundedWidth
      ? constraints.tighten(width: constraints.maxWidth)
      : constraints;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      child?.getDryLayout(_fill(constraints)) ?? constraints.smallest;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_fill(constraints), parentUsesSize: true);
    size = child.size;
  }
}
