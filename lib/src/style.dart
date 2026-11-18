import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

const List<String> _monospaceFallback = [
  'Menlo',
  'SF Mono',
  'Consolas',
  'Roboto Mono',
  'Courier New',
  'Courier',
];

const Color _lightAccent = Color(0xFF1A73E8);

// GitHub's alert colors
const Map<String, Color> _lightAlerts = {
  'note': Color(0xFF0969DA),
  'tip': Color(0xFF1A7F37),
  'important': Color(0xFF8250DF),
  'warning': Color(0xFF9A6700),
  'caution': Color(0xFFCF222E),
};
const Map<String, Color> _darkAlerts = {
  'note': Color(0xFF4493F8),
  'tip': Color(0xFF3FB950),
  'important': Color(0xFFAB7DF8),
  'warning': Color(0xFFD29922),
  'caution': Color(0xFFF85149),
};
const Color _darkAccent = Color(0xFF8AB4F8);

/// The look of a `StreamingMarkdown` widget.
///
/// By default the widget uses [StreamingMarkdownStyle.of], which follows the
/// surrounding [DefaultTextStyle] and [DefaultSelectionStyle]. Material and
/// Cupertino apps set both from their theme, so the text matches the app
/// without depending on any design library.
///
/// To pick the colors yourself, for example from a Material color scheme:
///
/// ```dart
/// StreamingMarkdownStyle.fromColors(
///   textStyle: theme.textTheme.bodyMedium!,
///   accentColor: theme.colorScheme.primary,
/// )
/// ```
@immutable
class StreamingMarkdownStyle {
  /// Creates a style from all of its parts.
  const StreamingMarkdownStyle({
    required this.textStyle,
    required this.headingStyles,
    required this.inlineCodeStyle,
    required this.codeBlockTextStyle,
    required this.codeBlockDecoration,
    required this.codeBlockHeaderStyle,
    required this.codeTheme,
    required this.blockquoteDecoration,
    required this.linkStyle,
    required this.dividerColor,
    required this.tableHeaderColor,
    required this.accentColor,
    this.alertColors = _lightAlerts,
    this.blockSpacing = 12,
    this.listIndent = 24,
  }) : assert(headingStyles.length == 6, 'headingStyles needs 6 styles');

  /// A style built from a body [textStyle] and an [accentColor] for links,
  /// checked boxes and the cursor.
  ///
  /// Surfaces and borders are tints of the text color, so the style suits
  /// any background. [brightness] chooses the code highlighting colors; it
  /// is worked out from the text color when not given.
  factory StreamingMarkdownStyle.fromColors({
    required TextStyle textStyle,
    required Color accentColor,
    Brightness? brightness,
  }) {
    final dark =
        (brightness ??
            ((textStyle.color?.computeLuminance() ?? 0) > 0.5
                ? Brightness.dark
                : Brightness.light)) ==
        Brightness.dark;
    final text =
        textStyle.color ??
        (dark ? const Color(0xFFE6E6E6) : const Color(0xFF1F1F1F));
    final body = textStyle.copyWith(color: text, height: 1.5);
    final fontSize = body.fontSize ?? 14;
    Color tint(double alpha) => text.withValues(alpha: alpha);
    final monospace = TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: _monospaceFallback,
      fontSize: fontSize * 0.9,
      color: text,
    );
    TextStyle heading(double scale, FontWeight weight) => body.copyWith(
      fontSize: fontSize * scale,
      fontWeight: weight,
      height: 1.3,
    );
    return StreamingMarkdownStyle(
      textStyle: body,
      headingStyles: [
        heading(1.75, FontWeight.w700),
        heading(1.45, FontWeight.w700),
        heading(1.25, FontWeight.w600),
        heading(1.1, FontWeight.w600),
        heading(1, FontWeight.w600),
        heading(0.9, FontWeight.w600),
      ],
      inlineCodeStyle: monospace.copyWith(backgroundColor: tint(0.08)),
      codeBlockTextStyle: monospace.copyWith(height: 1.45),
      codeBlockDecoration: BoxDecoration(
        color: tint(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tint(0.12)),
      ),
      codeBlockHeaderStyle: body.copyWith(
        fontSize: fontSize * 0.85,
        height: 1.2,
        color: tint(0.65),
      ),
      codeTheme: dark ? atomOneDarkTheme : atomOneLightTheme,
      blockquoteDecoration: BoxDecoration(
        border: BorderDirectional(
          start: BorderSide(color: tint(0.2), width: 4),
        ),
      ),
      linkStyle: TextStyle(
        color: accentColor,
        decoration: TextDecoration.underline,
        decorationColor: accentColor,
      ),
      dividerColor: tint(0.15),
      tableHeaderColor: tint(0.05),
      accentColor: accentColor,
      alertColors: dark ? _darkAlerts : _lightAlerts,
    );
  }

  /// The style for [context]: its [DefaultTextStyle] for text and its
  /// [DefaultSelectionStyle] cursor color as the accent.
  factory StreamingMarkdownStyle.of(BuildContext context) {
    final textStyle = DefaultTextStyle.of(context).style;
    final dark = (textStyle.color?.computeLuminance() ?? 0) > 0.5;
    final accent =
        DefaultSelectionStyle.of(context).cursorColor ??
        (dark ? _darkAccent : _lightAccent);
    return StreamingMarkdownStyle.fromColors(
      textStyle: textStyle,
      accentColor: accent,
    );
  }

  /// The style of paragraph text.
  final TextStyle textStyle;

  /// The styles of headings one to six.
  final List<TextStyle> headingStyles;

  /// The style of `inline code`, merged onto the surrounding text.
  final TextStyle inlineCodeStyle;

  /// The base style of code inside code blocks.
  final TextStyle codeBlockTextStyle;

  /// The box around a code block.
  final BoxDecoration codeBlockDecoration;

  /// The style of the language name and copy label above a code block.
  final TextStyle codeBlockHeaderStyle;

  /// The syntax highlighting colors, by highlight.js class name.
  ///
  /// Any theme from `package:re_highlight/styles/` can be used.
  final Map<String, TextStyle> codeTheme;

  /// The box around a block quote.
  final BoxDecoration blockquoteDecoration;

  /// The style of links, merged onto the surrounding text.
  final TextStyle linkStyle;

  /// The color of horizontal rules and table borders.
  final Color dividerColor;

  /// The background of table header rows.
  final Color tableHeaderColor;

  /// The color of checked boxes and of the cursor shown while text arrives.
  final Color accentColor;

  /// The colors of GitHub alerts, by type: `note`, `tip`, `important`,
  /// `warning` and `caution`.
  final Map<String, Color> alertColors;

  /// The space between blocks, such as paragraphs and lists.
  final double blockSpacing;

  /// The width reserved for list bullets and numbers.
  final double listIndent;

  /// Returns a copy with the given parts replaced.
  StreamingMarkdownStyle copyWith({
    TextStyle? textStyle,
    List<TextStyle>? headingStyles,
    TextStyle? inlineCodeStyle,
    TextStyle? codeBlockTextStyle,
    BoxDecoration? codeBlockDecoration,
    TextStyle? codeBlockHeaderStyle,
    Map<String, TextStyle>? codeTheme,
    BoxDecoration? blockquoteDecoration,
    TextStyle? linkStyle,
    Color? dividerColor,
    Color? tableHeaderColor,
    Color? accentColor,
    Map<String, Color>? alertColors,
    double? blockSpacing,
    double? listIndent,
  }) => StreamingMarkdownStyle(
    textStyle: textStyle ?? this.textStyle,
    headingStyles: headingStyles ?? this.headingStyles,
    inlineCodeStyle: inlineCodeStyle ?? this.inlineCodeStyle,
    codeBlockTextStyle: codeBlockTextStyle ?? this.codeBlockTextStyle,
    codeBlockDecoration: codeBlockDecoration ?? this.codeBlockDecoration,
    codeBlockHeaderStyle: codeBlockHeaderStyle ?? this.codeBlockHeaderStyle,
    codeTheme: codeTheme ?? this.codeTheme,
    blockquoteDecoration: blockquoteDecoration ?? this.blockquoteDecoration,
    linkStyle: linkStyle ?? this.linkStyle,
    dividerColor: dividerColor ?? this.dividerColor,
    tableHeaderColor: tableHeaderColor ?? this.tableHeaderColor,
    accentColor: accentColor ?? this.accentColor,
    alertColors: alertColors ?? this.alertColors,
    blockSpacing: blockSpacing ?? this.blockSpacing,
    listIndent: listIndent ?? this.listIndent,
  );

  @override
  bool operator ==(Object other) =>
      other is StreamingMarkdownStyle &&
      other.textStyle == textStyle &&
      listEquals(other.headingStyles, headingStyles) &&
      other.inlineCodeStyle == inlineCodeStyle &&
      other.codeBlockTextStyle == codeBlockTextStyle &&
      other.codeBlockDecoration == codeBlockDecoration &&
      other.codeBlockHeaderStyle == codeBlockHeaderStyle &&
      identical(other.codeTheme, codeTheme) &&
      other.blockquoteDecoration == blockquoteDecoration &&
      other.linkStyle == linkStyle &&
      other.dividerColor == dividerColor &&
      other.tableHeaderColor == tableHeaderColor &&
      other.accentColor == accentColor &&
      mapEquals(other.alertColors, alertColors) &&
      other.blockSpacing == blockSpacing &&
      other.listIndent == listIndent;

  @override
  int get hashCode => Object.hash(
    textStyle,
    Object.hashAll(headingStyles),
    inlineCodeStyle,
    codeBlockTextStyle,
    codeBlockDecoration,
    codeBlockHeaderStyle,
    identityHashCode(codeTheme),
    blockquoteDecoration,
    linkStyle,
    dividerColor,
    tableHeaderColor,
    accentColor,
    Object.hashAllUnordered(alertColors.entries.map((e) => (e.key, e.value))),
    blockSpacing,
    listIndent,
  );
}
