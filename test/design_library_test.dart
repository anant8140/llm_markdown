// The package uses only package:flutter/widgets.dart, so it must work the
// same in apps built with the Material library that ships with Flutter
// (deprecated since Flutter 3.47) and with package:material_ui.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart' as flutter_material;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:material_ui/material_ui.dart' as material_ui;

const String _reply =
    '## Title\n\nRead the [docs](https://dart.dev).\n\n'
    '- [x] done\n\n```dart\nvoid main() {}\n```\n';

/// The style of the paragraph span this package builds.
TextStyle? _paragraphStyle(WidgetTester tester, String text) {
  final rich = tester.widget<RichText>(
    find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().startsWith(text),
    ),
  );
  return ((rich.text as TextSpan).children!.first as TextSpan).style;
}

Color? _linkColor(WidgetTester tester) {
  Color? found;
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    // The link style sits on a span without text of its own, around the
    // link text, so walk every span rather than use visitChildren.
    void walk(InlineSpan span) {
      if (span is! TextSpan) return;
      if (span.toPlainText() == 'docs' &&
          span.style?.decoration == TextDecoration.underline) {
        found ??= span.style?.color;
      }
      span.children?.forEach(walk);
    }

    walk(rich.text);
  }
  return found;
}

void main() {
  testWidgets('works in an app built with the Flutter Material library', (
    tester,
  ) async {
    final theme = flutter_material.ThemeData(
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xFF3F51B5),
    );
    await tester.pumpWidget(
      flutter_material.MaterialApp(
        theme: theme,
        home: const flutter_material.Scaffold(
          body: flutter_material.SelectionArea(
            child: StreamingMarkdown.text(_reply),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      _paragraphStyle(tester, 'Read the')?.color,
      theme.colorScheme.onSurface,
    );
    expect(_linkColor(tester), theme.colorScheme.primary);
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('works in an app built with package:material_ui', (tester) async {
    final theme = material_ui.ThemeData(
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xFF3F51B5),
    );
    await tester.pumpWidget(
      material_ui.MaterialApp(
        theme: theme,
        home: const material_ui.Scaffold(
          body: material_ui.SelectionArea(
            child: StreamingMarkdown.text(_reply),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      _paragraphStyle(tester, 'Read the')?.color,
      theme.colorScheme.onSurface,
    );
    expect(_linkColor(tester), theme.colorScheme.primary);
    expect(find.text('Copy'), findsOneWidget);
  });
}
