import 'package:flutter/widgets.dart';
import 'package:re_highlight/styles/androidstudio.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';
import 'package:re_highlight/styles/github-dark-dimmed.dart';
import 'package:re_highlight/styles/github-dark.dart';
import 'package:re_highlight/styles/github.dart';
import 'package:re_highlight/styles/monokai-sublime.dart';
import 'package:re_highlight/styles/night-owl.dart';
import 'package:re_highlight/styles/nord.dart';
import 'package:re_highlight/styles/tokyo-night-dark.dart';
import 'package:re_highlight/styles/tokyo-night-light.dart';
import 'package:re_highlight/styles/vs2015.dart';
import 'package:re_highlight/styles/xcode.dart';

/// Builds the copy button of a code block. Call [copy] to copy the code;
/// [copied] is true for a moment after copying.
typedef CodeCopyButtonBuilder =
    Widget Function(BuildContext context, VoidCallback copy, bool copied);

/// Builds extra buttons for a code block's header, such as "Run".
typedef CodeActionsBuilder =
    List<Widget> Function(BuildContext context, String code, String? language);

/// How code blocks look and behave.
@immutable
class CodeBlockOptions {
  /// Creates code block options.
  const CodeBlockOptions({
    this.lineNumbers = false,
    this.wrapLines = false,
    this.collapseAfterLines,
    this.highlightWhileStreaming = false,
    this.copyButtonBuilder,
    this.actionsBuilder,
    this.toggleLabel,
  }) : assert(
         collapseAfterLines == null || collapseAfterLines > 0,
         'collapseAfterLines must be positive',
       );

  /// Whether lines are numbered.
  final bool lineNumbers;

  /// Whether long lines wrap instead of scrolling sideways.
  final bool wrapLines;

  /// Blocks with more lines than this show only that many until the user
  /// taps "Show all". Null keeps every block open.
  final int? collapseAfterLines;

  /// Whether a block is highlighted line by line while it streams, instead
  /// of once its closing fence arrives. The line being typed stays plain.
  final bool highlightWhileStreaming;

  /// Replaces the default copy button.
  final CodeCopyButtonBuilder? copyButtonBuilder;

  /// Adds buttons before the copy button.
  final CodeActionsBuilder? actionsBuilder;

  /// The label of the collapse toggle; defaults to "Show all N lines" and
  /// "Show less".
  final String Function(int lines, bool expanded)? toggleLabel;

  @override
  bool operator ==(Object other) =>
      other is CodeBlockOptions &&
      other.lineNumbers == lineNumbers &&
      other.wrapLines == wrapLines &&
      other.collapseAfterLines == collapseAfterLines &&
      other.highlightWhileStreaming == highlightWhileStreaming &&
      other.copyButtonBuilder == copyButtonBuilder &&
      other.actionsBuilder == actionsBuilder &&
      other.toggleLabel == toggleLabel;

  @override
  int get hashCode => Object.hash(
    lineNumbers,
    wrapLines,
    collapseAfterLines,
    highlightWhileStreaming,
    copyButtonBuilder,
    actionsBuilder,
    toggleLabel,
  );
}

/// Ready-made syntax highlighting themes, for
/// `StreamingMarkdownStyle.copyWith(codeTheme: ...)`.
abstract final class CodeThemes {
  /// GitHub, light.
  static const Map<String, TextStyle> github = githubTheme;

  /// GitHub, dark.
  static const Map<String, TextStyle> githubDark = githubDarkTheme;

  /// GitHub, dark dimmed.
  static const Map<String, TextStyle> githubDarkDimmed = githubDarkDimmedTheme;

  /// Atom One, light (the default for light themes).
  static const Map<String, TextStyle> atomOneLight = atomOneLightTheme;

  /// Atom One, dark (the default for dark themes).
  static const Map<String, TextStyle> atomOneDark = atomOneDarkTheme;

  /// Visual Studio 2015, dark.
  static const Map<String, TextStyle> vs2015 = vs2015Theme;

  /// Monokai Sublime, dark.
  static const Map<String, TextStyle> monokai = monokaiSublimeTheme;

  /// Tokyo Night, dark.
  static const Map<String, TextStyle> tokyoNightDark = tokyoNightDarkTheme;

  /// Tokyo Night, light.
  static const Map<String, TextStyle> tokyoNightLight = tokyoNightLightTheme;

  /// Nord, dark.
  static const Map<String, TextStyle> nord = nordTheme;

  /// Xcode, light.
  static const Map<String, TextStyle> xcode = xcodeTheme;

  /// Android Studio, dark.
  static const Map<String, TextStyle> androidStudio = androidstudioTheme;

  /// Night Owl, dark.
  static const Map<String, TextStyle> nightOwl = nightOwlTheme;
}

// Cuts a span tree into lines, keeping each piece's style.
List<List<InlineSpan>> splitSpanLines(InlineSpan root, TextStyle base) {
  final lines = <List<InlineSpan>>[[]];
  void walk(InlineSpan span, TextStyle style) {
    if (span is! TextSpan) {
      lines.last.add(span);
      return;
    }
    final merged = style.merge(span.style);
    final text = span.text;
    if (text != null) {
      final parts = text.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (i > 0) lines.add([]);
        if (parts[i].isNotEmpty) {
          lines.last.add(TextSpan(text: parts[i], style: merged));
        }
      }
    }
    span.children?.forEach((child) => walk(child, merged));
  }

  walk(root, base);
  return lines;
}
