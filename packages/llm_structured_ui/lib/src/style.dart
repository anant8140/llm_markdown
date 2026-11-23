import 'package:flutter/widgets.dart';

/// The look of the structured widgets.
///
/// [StructuredStyle.of] gives the style of the nearest [StructuredTheme],
/// or one made from the surrounding text style, so the widgets fit light
/// and dark screens in Material and Cupertino apps without setup.
@immutable
class StructuredStyle {
  /// A style with every part given.
  const StructuredStyle({
    required this.textStyle,
    required this.labelStyle,
    required this.titleStyle,
    required this.subtitleStyle,
    required this.cursorColor,
    required this.placeholderColor,
    required this.chipColor,
    required this.cardColor,
    required this.cardBorderColor,
    this.cardRadius = 12,
    this.cardPadding = const EdgeInsets.all(12),
    this.spacing = 8,
    this.indent = 16,
    this.pendingOpacity = 0.5,
  });

  /// A style whose colors all come from one [textStyle]: labels and
  /// subtitles are the text color made lighter, and placeholders, chips
  /// and card borders are faint tints of it.
  factory StructuredStyle.fromTextStyle(TextStyle textStyle) {
    final color = textStyle.color ?? const Color(0xFF1F1F1F);
    final size = textStyle.fontSize ?? 14;
    return StructuredStyle(
      textStyle: textStyle,
      labelStyle: textStyle.copyWith(color: color.withValues(alpha: 0.62)),
      titleStyle: textStyle.copyWith(
        fontSize: size * 1.2,
        fontWeight: FontWeight.w600,
      ),
      subtitleStyle: textStyle.copyWith(color: color.withValues(alpha: 0.62)),
      cursorColor: color,
      placeholderColor: color.withValues(alpha: 0.14),
      chipColor: color.withValues(alpha: 0.08),
      cardColor: color.withValues(alpha: 0.03),
      cardBorderColor: color.withValues(alpha: 0.16),
    );
  }

  /// The style of the nearest [StructuredTheme], or one made from the
  /// [DefaultTextStyle] around [context]. When that text style has no
  /// color, the text is dark on a light screen and light on a dark one.
  static StructuredStyle of(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<StructuredTheme>();
    if (theme != null) return theme.style;
    var textStyle = DefaultTextStyle.of(context).style;
    if (textStyle.color == null) {
      final dark =
          MediaQuery.maybePlatformBrightnessOf(context) == Brightness.dark;
      textStyle = textStyle.copyWith(
        color: dark ? const Color(0xFFECECEC) : const Color(0xFF1F1F1F),
      );
    }
    return StructuredStyle.fromTextStyle(textStyle);
  }

  /// Values and other plain text.
  final TextStyle textStyle;

  /// The labels of `StructuredFields` and of nested values in
  /// `StructuredAuto`.
  final TextStyle labelStyle;

  /// The title of a `StructuredCard`.
  final TextStyle titleStyle;

  /// The subtitle and footer of a `StructuredCard`.
  final TextStyle subtitleStyle;

  /// The blinking cursor after text that is still arriving.
  final Color cursorColor;

  /// The placeholder line shown for a value that has not arrived.
  final Color placeholderColor;

  /// The background of number and bool chips.
  final Color chipColor;

  /// The background of a card.
  final Color cardColor;

  /// The border of a card.
  final Color cardBorderColor;

  /// The corner radius of a card.
  final double cardRadius;

  /// The space inside a card around its content.
  final EdgeInsets cardPadding;

  /// The space between rows, list items and the parts of a card.
  final double spacing;

  /// How far nested values are moved in by `StructuredAuto`.
  final double indent;

  /// How see-through the list item still being written is, from 0 to 1.
  final double pendingOpacity;

  /// This style with some parts replaced.
  StructuredStyle copyWith({
    TextStyle? textStyle,
    TextStyle? labelStyle,
    TextStyle? titleStyle,
    TextStyle? subtitleStyle,
    Color? cursorColor,
    Color? placeholderColor,
    Color? chipColor,
    Color? cardColor,
    Color? cardBorderColor,
    double? cardRadius,
    EdgeInsets? cardPadding,
    double? spacing,
    double? indent,
    double? pendingOpacity,
  }) => StructuredStyle(
    textStyle: textStyle ?? this.textStyle,
    labelStyle: labelStyle ?? this.labelStyle,
    titleStyle: titleStyle ?? this.titleStyle,
    subtitleStyle: subtitleStyle ?? this.subtitleStyle,
    cursorColor: cursorColor ?? this.cursorColor,
    placeholderColor: placeholderColor ?? this.placeholderColor,
    chipColor: chipColor ?? this.chipColor,
    cardColor: cardColor ?? this.cardColor,
    cardBorderColor: cardBorderColor ?? this.cardBorderColor,
    cardRadius: cardRadius ?? this.cardRadius,
    cardPadding: cardPadding ?? this.cardPadding,
    spacing: spacing ?? this.spacing,
    indent: indent ?? this.indent,
    pendingOpacity: pendingOpacity ?? this.pendingOpacity,
  );

  @override
  bool operator ==(Object other) =>
      other is StructuredStyle &&
      other.textStyle == textStyle &&
      other.labelStyle == labelStyle &&
      other.titleStyle == titleStyle &&
      other.subtitleStyle == subtitleStyle &&
      other.cursorColor == cursorColor &&
      other.placeholderColor == placeholderColor &&
      other.chipColor == chipColor &&
      other.cardColor == cardColor &&
      other.cardBorderColor == cardBorderColor &&
      other.cardRadius == cardRadius &&
      other.cardPadding == cardPadding &&
      other.spacing == spacing &&
      other.indent == indent &&
      other.pendingOpacity == pendingOpacity;

  @override
  int get hashCode => Object.hash(
    textStyle,
    labelStyle,
    titleStyle,
    subtitleStyle,
    cursorColor,
    placeholderColor,
    chipColor,
    cardColor,
    cardBorderColor,
    cardRadius,
    cardPadding,
    spacing,
    indent,
    pendingOpacity,
  );
}

/// Gives a [StructuredStyle] to the structured widgets below it.
class StructuredTheme extends InheritedWidget {
  /// Styles the structured widgets in [child] with [style].
  const StructuredTheme({super.key, required this.style, required super.child});

  /// The style for the widgets below.
  final StructuredStyle style;

  @override
  bool updateShouldNotify(StructuredTheme oldWidget) =>
      style != oldWidget.style;
}
