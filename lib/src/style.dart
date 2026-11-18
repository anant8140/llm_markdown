import 'dart:ui' show lerpDouble;

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
    this.blockPadding = const {},
  }) : assert(headingStyles.length == 6, 'headingStyles needs 6 styles');

  /// A style built from a body [textStyle] and an [accentColor] for links,
  /// checked boxes and the cursor.
  ///
  /// Surfaces and borders are tints of the text color, so the style suits
  /// any background. [brightness] chooses the code highlighting colors; it
  /// is worked out from the text color when not given.
  ///
  /// [monospace] sets the font for code, e.g.
  /// `GoogleFonts.jetBrainsMono()`. On the web there is no built-in
  /// monospace font, so passing one there is a good idea.
  factory StreamingMarkdownStyle.fromColors({
    required TextStyle textStyle,
    required Color accentColor,
    Brightness? brightness,
    TextStyle? monospace,
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
    final mono =
        (monospace ??
                const TextStyle(
                  fontFamily: 'monospace',
                  fontFamilyFallback: _monospaceFallback,
                ))
            .copyWith(fontSize: fontSize * 0.9, color: text);
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
      inlineCodeStyle: mono.copyWith(backgroundColor: tint(0.08)),
      codeBlockTextStyle: mono.copyWith(height: 1.45),
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

  /// Tighter spacing, for small bubbles and side panels.
  factory StreamingMarkdownStyle.compact({
    required TextStyle textStyle,
    required Color accentColor,
    Brightness? brightness,
    TextStyle? monospace,
  }) => StreamingMarkdownStyle.fromColors(
    textStyle: textStyle,
    accentColor: accentColor,
    brightness: brightness,
    monospace: monospace,
  )._spaced(lineHeight: 1.35, blockSpacing: 8, listIndent: 20);

  /// Roomier spacing, for long answers read like a document.
  factory StreamingMarkdownStyle.spacious({
    required TextStyle textStyle,
    required Color accentColor,
    Brightness? brightness,
    TextStyle? monospace,
  }) => StreamingMarkdownStyle.fromColors(
    textStyle: textStyle,
    accentColor: accentColor,
    brightness: brightness,
    monospace: monospace,
  )._spaced(lineHeight: 1.7, blockSpacing: 18, listIndent: 28);

  /// Everything in a monospace font with square boxes, like a terminal.
  factory StreamingMarkdownStyle.terminal({
    required TextStyle textStyle,
    required Color accentColor,
    Brightness? brightness,
    TextStyle? monospace,
  }) {
    final mono =
        monospace ??
        const TextStyle(
          fontFamily: 'monospace',
          fontFamilyFallback: _monospaceFallback,
        );
    final base = StreamingMarkdownStyle.fromColors(
      textStyle: textStyle.merge(mono),
      accentColor: accentColor,
      brightness: brightness,
      monospace: mono,
    );
    return base.copyWith(
      headingStyles: [
        for (final heading in base.headingStyles)
          heading.copyWith(fontSize: base.textStyle.fontSize),
      ],
      codeBlockDecoration: base.codeBlockDecoration.copyWith(
        borderRadius: BorderRadius.zero,
      ),
    );
  }

  StreamingMarkdownStyle _spaced({
    required double lineHeight,
    required double blockSpacing,
    required double listIndent,
  }) => copyWith(
    textStyle: textStyle.copyWith(height: lineHeight),
    blockSpacing: blockSpacing,
    listIndent: listIndent,
  );

  /// The style for [context]: the nearest [StreamingMarkdownTheme], or else
  /// its [DefaultTextStyle] for text and its [DefaultSelectionStyle] cursor
  /// color as the accent.
  factory StreamingMarkdownStyle.of(BuildContext context) {
    final themed = StreamingMarkdownTheme.maybeOf(context);
    if (themed != null) return themed;
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

  /// Extra padding around blocks, by tag: `p`, `h1` to `h6`, `pre` (code),
  /// `blockquote`, `ul`, `ol`, `table`, `hr`, `math-block`, `details`, or
  /// the tag of a custom syntax. For example `{'h2': EdgeInsets.only(top: 8)}`.
  final Map<String, EdgeInsetsGeometry> blockPadding;

  /// Blends two styles, for animated theme changes, e.g. from a Material
  /// `ThemeExtension.lerp`. Highlighting colors, alert colors and padding
  /// switch halfway.
  static StreamingMarkdownStyle lerp(
    StreamingMarkdownStyle a,
    StreamingMarkdownStyle b,
    double t,
  ) {
    if (identical(a, b)) return a;
    final first = t < 0.5;
    TextStyle text(TextStyle x, TextStyle y) => TextStyle.lerp(x, y, t)!;
    return StreamingMarkdownStyle(
      textStyle: text(a.textStyle, b.textStyle),
      headingStyles: [
        for (var i = 0; i < 6; i++)
          text(a.headingStyles[i], b.headingStyles[i]),
      ],
      inlineCodeStyle: text(a.inlineCodeStyle, b.inlineCodeStyle),
      codeBlockTextStyle: text(a.codeBlockTextStyle, b.codeBlockTextStyle),
      codeBlockDecoration: BoxDecoration.lerp(
        a.codeBlockDecoration,
        b.codeBlockDecoration,
        t,
      )!,
      codeBlockHeaderStyle: text(
        a.codeBlockHeaderStyle,
        b.codeBlockHeaderStyle,
      ),
      codeTheme: first ? a.codeTheme : b.codeTheme,
      blockquoteDecoration: BoxDecoration.lerp(
        a.blockquoteDecoration,
        b.blockquoteDecoration,
        t,
      )!,
      linkStyle: text(a.linkStyle, b.linkStyle),
      dividerColor: Color.lerp(a.dividerColor, b.dividerColor, t)!,
      tableHeaderColor: Color.lerp(a.tableHeaderColor, b.tableHeaderColor, t)!,
      accentColor: Color.lerp(a.accentColor, b.accentColor, t)!,
      alertColors: first ? a.alertColors : b.alertColors,
      blockSpacing: lerpDouble(a.blockSpacing, b.blockSpacing, t)!,
      listIndent: lerpDouble(a.listIndent, b.listIndent, t)!,
      blockPadding: first ? a.blockPadding : b.blockPadding,
    );
  }

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
    Map<String, EdgeInsetsGeometry>? blockPadding,
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
    blockPadding: blockPadding ?? this.blockPadding,
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
      other.listIndent == listIndent &&
      mapEquals(other.blockPadding, blockPadding);

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
    Object.hashAllUnordered(blockPadding.entries.map((e) => (e.key, e.value))),
  );
}

/// Gives every `StreamingMarkdown` below it the same [style], unless the
/// widget has its own.
///
/// In a Material app the style can also live in a `ThemeExtension`; its
/// `lerp` can call [StreamingMarkdownStyle.lerp], and a
/// `StreamingMarkdownTheme` built from it near the top of the app passes it
/// on.
class StreamingMarkdownTheme extends InheritedWidget {
  /// Creates a theme for the widgets in [child].
  const StreamingMarkdownTheme({
    super.key,
    required this.style,
    required super.child,
  });

  /// The style of the `StreamingMarkdown` widgets below.
  final StreamingMarkdownStyle style;

  /// The style of the nearest theme, or null.
  static StreamingMarkdownStyle? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<StreamingMarkdownTheme>()
      ?.style;

  @override
  bool updateShouldNotify(StreamingMarkdownTheme oldWidget) =>
      style != oldWidget.style;
}
