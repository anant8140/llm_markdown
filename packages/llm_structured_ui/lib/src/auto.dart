import 'package:flutter/widgets.dart';

import 'card.dart';
import 'fields.dart';
import 'indicators.dart';
import 'list.dart';
import 'style.dart';
import 'text.dart';
import 'value.dart';

/// Draws any JSON value without configuration, for quick starts and for
/// looking at what a model sends.
///
/// * a string is text, with a cursor while it is written
/// * a number, bool or null is a chip
/// * an object whose values are all plain is a table of fields
/// * other objects show each nested value under its key, moved in
/// * a list of objects is a column of cards, a list of numbers or bools a
///   row of chips, and any other list a column of its items
/// * a value that has not arrived shows a placeholder line
class StructuredAuto extends StatelessWidget {
  /// Draws [value].
  const StructuredAuto(
    this.value, {
    super.key,
    this.labels = const {},
    this.style,
  });

  /// The value to draw.
  final StructuredValue value;

  /// The label for each key, at any depth; a key without one is its own
  /// label.
  final Map<String, String> labels;

  /// The look; defaults to [StructuredStyle.of] the context.
  final StructuredStyle? style;

  @override
  Widget build(BuildContext context) {
    final style = this.style ?? StructuredStyle.of(context);
    final placeholder = StructuredPlaceholder(color: style.placeholderColor);
    if (!value.exists) {
      return value.isAwaited ? placeholder : const SizedBox.shrink();
    }
    if (value.isMap) {
      if (value.length == 0) {
        return value.isPending ? placeholder : const SizedBox.shrink();
      }
      return _map(style);
    }
    if (value.isList) {
      if (value.length == 0) {
        return value.isPending ? placeholder : const SizedBox.shrink();
      }
      return _list(style);
    }
    if (value.raw is String) return StructuredText(value, style: style);
    return _Chip(value, style);
  }

  Widget _map(StructuredStyle style) {
    final entries = value.asMap;
    if (entries.values.every((entry) => entry.isScalar)) {
      return StructuredFields(value, labels: labels, style: style);
    }
    // plain values next to each other share a table; nested ones follow
    // their key, moved in
    final children = <Widget>[];
    var run = <FieldRow>[];
    void endRun() {
      if (run.isEmpty) return;
      children.add(FieldsTable(run, style: style));
      run = <FieldRow>[];
    }

    entries.forEach((key, entry) {
      final label = labels[key] ?? key;
      if (entry.isScalar) {
        run.add(FieldRow(label, entry));
        return;
      }
      endRun();
      children.add(
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: label,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: Text(label, style: style.labelStyle)),
              Padding(
                padding: EdgeInsetsDirectional.only(
                  start: style.indent,
                  top: style.spacing / 2,
                ),
                child: StructuredAuto(entry, labels: labels, style: style),
              ),
            ],
          ),
        ),
      );
    });
    endRun();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: style.spacing),
          children[i],
        ],
      ],
    );
  }

  Widget _list(StructuredStyle style) {
    final items = value.asList;
    if (items.every((item) => item.isScalar && item.raw is! String)) {
      return Wrap(
        spacing: style.spacing,
        runSpacing: style.spacing,
        children: [for (final item in items) _Chip(item, style)],
      );
    }
    return StructuredList(
      value,
      style: style,
      itemBuilder: (context, item, index) => item.isMap
          ? StructuredCard(
              item,
              style: style,
              bodyBuilder: (context, item) =>
                  StructuredAuto(item, labels: labels, style: style),
            )
          : StructuredAuto(item, labels: labels, style: style),
    );
  }
}

// A number, bool or null in a small rounded box.
class _Chip extends StatelessWidget {
  const _Chip(this.value, this.style);

  final StructuredValue value;
  final StructuredStyle style;

  @override
  Widget build(BuildContext context) {
    final size = style.textStyle.fontSize ?? 14;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.chipColor,
        borderRadius: BorderRadius.circular(size),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: size * 0.6, vertical: 2),
        child: Text('${value.raw}', style: style.textStyle),
      ),
    );
  }
}
