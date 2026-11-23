import 'package:flutter/widgets.dart';

import 'style.dart';
import 'value.dart';

/// Builds the widget for one item of a [StructuredList].
typedef StructuredItemBuilder =
    Widget Function(BuildContext context, StructuredValue item, int index);

/// Shows the items of a list one under another as they arrive.
///
/// The item still being written is drawn faded
/// ([StructuredStyle.pendingOpacity]), or left out until it is finished
/// with [showPendingItem] false. The items are laid out in a [Column]
/// that does not scroll; for a very long list, build a `ListView` from
/// `value.asList` instead.
class StructuredList extends StatelessWidget {
  /// Shows the items of [value] with [itemBuilder].
  const StructuredList(
    this.value, {
    super.key,
    required this.itemBuilder,
    this.showPendingItem = true,
    this.semanticLabel,
    this.style,
  });

  /// The list to show. Anything that is not a list shows nothing.
  final StructuredValue value;

  /// Builds each item.
  final StructuredItemBuilder itemBuilder;

  /// Whether the item still being written is shown (faded); when false it
  /// appears once it is finished.
  final bool showPendingItem;

  /// What a screen reader says for the list as a whole, if anything.
  final String? semanticLabel;

  /// The look; defaults to [StructuredStyle.of] the context.
  final StructuredStyle? style;

  @override
  Widget build(BuildContext context) {
    final style = this.style ?? StructuredStyle.of(context);
    final items = value.asList;
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final pending = item.isPending;
      if (pending && !showPendingItem) continue;
      // always an Opacity, so the item keeps its state when it finishes
      final child = Opacity(
        opacity: pending ? style.pendingOpacity : 1,
        child: itemBuilder(context, item, i),
      );
      if (children.isNotEmpty) children.add(SizedBox(height: style.spacing));
      children.add(KeyedSubtree(key: ValueKey<int>(i), child: child));
    }
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
    if (semanticLabel == null) return column;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: column,
    );
  }
}
