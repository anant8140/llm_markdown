import 'package:flutter/widgets.dart';

import 'auto.dart';
import 'indicators.dart';
import 'style.dart';
import 'text.dart';
import 'value.dart';

/// Shows a flat object as a table of labels and values that fill in as
/// they arrive.
///
/// A value that has not arrived (for a key named in [order]) or has no
/// text yet shows a placeholder line; a value being written shows its text
/// so far with a cursor. A nested map or list is drawn by
/// [StructuredAuto].
class StructuredFields extends StatelessWidget {
  /// Shows the entries of [value].
  const StructuredFields(
    this.value, {
    super.key,
    this.labels = const {},
    this.order = const [],
    this.hide = const {},
    this.valueBuilder,
    this.style,
  });

  /// The object to show. Anything that is not a map shows only the
  /// placeholder rows for [order], while it can still arrive.
  final StructuredValue value;

  /// The label for each key; a key without one is its own label.
  final Map<String, String> labels;

  /// The keys shown first, in this order. While the object is being
  /// written they have a row before they arrive. Other keys follow in the
  /// order they arrive.
  final List<String> order;

  /// Keys that are not shown.
  final Set<String> hide;

  /// Builds the value of a row; return null for the usual look.
  final Widget? Function(
    BuildContext context,
    String key,
    StructuredValue value,
  )?
  valueBuilder;

  /// The look; defaults to [StructuredStyle.of] the context.
  final StructuredStyle? style;

  @override
  Widget build(BuildContext context) {
    final style = this.style ?? StructuredStyle.of(context);
    final keys = <String>[
      for (final key in order)
        if (!hide.contains(key)) key,
      for (final key in value.asMap.keys)
        if (!hide.contains(key) && !order.contains(key)) key,
    ];
    final rows = <FieldRow>[];
    for (final key in keys) {
      final field = value[key];
      // a key that never arrived has no row once nothing more can come
      final awaited = field.isAwaited;
      if (!field.exists && !awaited) continue;
      rows.add(
        FieldRow(
          labels[key] ?? key,
          field,
          awaited: awaited,
          custom: field.exists ? valueBuilder?.call(context, key, field) : null,
        ),
      );
    }
    return FieldsTable(rows, style: style);
  }
}

/// One row of a [FieldsTable].
class FieldRow {
  /// A row with [label] and [value]; [custom] replaces the usual value
  /// widget, and [awaited] says the value can still arrive.
  const FieldRow(this.label, this.value, {this.awaited = false, this.custom});

  /// The text of the label.
  final String label;

  /// The value.
  final StructuredValue value;

  /// Whether a missing value can still arrive.
  final bool awaited;

  /// A widget shown in place of the usual one.
  final Widget? custom;
}

/// The table behind [StructuredFields]; also used by [StructuredAuto].
class FieldsTable extends StatelessWidget {
  /// A table of [rows].
  const FieldsTable(this.rows, {super.key, required this.style});

  /// The rows, top to bottom.
  final List<FieldRow> rows;

  /// The look.
  final StructuredStyle style;

  Widget _value(FieldRow row) {
    final custom = row.custom;
    if (custom != null) return custom;
    final value = row.value;
    final fontSize = style.textStyle.fontSize ?? 14;
    if (!value.exists) return _placeholder(fontSize);
    if (value.isMap || value.isList) {
      return StructuredAuto(value, style: style);
    }
    if (value.isNull) return Text('–', style: style.textStyle);
    if (value.isPending && StructuredText.textOf(value).isEmpty) {
      return _placeholder(fontSize);
    }
    return StructuredText(value, style: style);
  }

  // as tall as a line of text, so rows do not jump when the value arrives
  Widget _placeholder(double fontSize) => Padding(
    padding: EdgeInsets.symmetric(vertical: fontSize * 0.2),
    child: StructuredPlaceholder(
      height: fontSize * 0.8,
      color: style.placeholderColor,
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Table(
      columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
      children: [
        for (var i = 0; i < rows.length; i++)
          TableRow(
            children: [
              Padding(
                padding: EdgeInsetsDirectional.only(
                  end: 12,
                  bottom: i == rows.length - 1 ? 0 : style.spacing,
                ),
                // the label is read with the value, below
                child: ExcludeSemantics(
                  child: Text(rows[i].label, style: style.labelStyle),
                ),
              ),
              Semantics(label: rows[i].label, child: _value(rows[i])),
            ],
          ),
      ],
    );
  }
}
