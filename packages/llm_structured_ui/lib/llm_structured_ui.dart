/// Widgets that show an AI model's structured (JSON) output while it is
/// still being written.
///
/// A [StructuredStreamController] takes the pieces of the JSON document, a
/// [StructuredBuilder] rebuilds as they arrive and hands out a
/// [StructuredValue] that is safe to read while fields are missing, and
/// [StructuredText], [StructuredList], [StructuredFields], [StructuredCard]
/// and [StructuredAuto] draw the usual shapes.
library;

export 'src/auto.dart' show StructuredAuto;
export 'src/builder.dart'
    show StructuredBuilder, StructuredErrorBuilder, StructuredWidgetBuilder;
export 'src/card.dart' show StructuredCard;
export 'src/controller.dart' show StructuredStreamController;
export 'src/fields.dart' show StructuredFields;
export 'src/indicators.dart' show StructuredCursor, StructuredPlaceholder;
export 'src/list.dart' show StructuredItemBuilder, StructuredList;
export 'src/style.dart' show StructuredStyle, StructuredTheme;
export 'src/text.dart' show StructuredText;
export 'src/value.dart' show StructuredValue;
