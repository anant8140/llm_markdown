import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';

void main() {
  test('toCsv quotes what needs it and guards formulas', () {
    const data = MarkdownTableData([
      ['Name', 'Note'],
      ['a, b', 'say "hi"'],
      ['two\nlines', '=SUM(A1)'],
      ['-5', '+1.5'],
      ['-cmd', '@x'],
    ]);
    expect(
      data.toCsv(),
      'Name,Note\n'
      '"a, b","say ""hi"""\n'
      '"two\nlines",\'=SUM(A1)\n'
      '-5,+1.5\n'
      "'-cmd,'@x",
    );
    expect(data.toCsv(guardFormulas: false), contains(',=SUM(A1)\n'));
    expect(
      data.toTsv(),
      'Name\tNote\na, b\tsay "hi"\ntwo lines\t\'=SUM(A1)\n-5\t+1.5\n\'-cmd\t\'@x',
    );
  });

  testWidgets('tableBuilder gets the built table and its cells as text', (
    tester,
  ) async {
    MarkdownTableData? seen;
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF2196F3),
        builder: (context, _) => StreamingMarkdown.text(
          '| City | Temp |\n|---|--:|\n| **Paris** | 18 |\n| Rome, IT | `24` |\n| half',
          tableBuilder: (context, table, data) {
            seen = data;
            return Column(children: [const Text('COPY'), table]);
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.text('COPY'), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
    expect(seen!.hasHeader, isTrue);
    // formatting is left out; a short last row is filled up, as it is
    // in the table
    expect(seen!.rows, [
      ['City', 'Temp'],
      ['Paris', '18'],
      ['Rome, IT', '24'],
      ['half', ''],
    ]);
    expect(seen!.toCsv(), 'City,Temp\nParis,18\n"Rome, IT",24\nhalf,');
  });

  testWidgets('without a tableBuilder the table is as before', (tester) async {
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF2196F3),
        builder: (context, _) =>
            const StreamingMarkdown.text('| A |\n|---|\n| 1 |'),
      ),
    );
    await tester.pump();
    expect(find.byType(Table), findsOneWidget);
  });
}
