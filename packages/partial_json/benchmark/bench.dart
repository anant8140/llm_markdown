// How long it takes to follow a JSON document that streams in:
//   dart run benchmark/bench.dart
import 'dart:convert';

import 'package:partial_json/partial_json.dart';

String document(int items) => jsonEncode({
  'items': [
    for (var i = 0; i < items; i++)
      {
        'id': i,
        'title': 'Item number $i with some text',
        'tags': ['a', 'b'],
        'ok': i.isEven,
      },
  ],
});

int median(List<int> values) => (values..sort())[values.length ~/ 2];

void main() {
  const piece = 8;
  // warm up
  for (var i = 0; i < 3; i++) {
    final parser = PartialJsonParser();
    final doc = document(500);
    for (var at = 0; at < doc.length; at += piece) {
      parser.add(doc.substring(at, (at + piece).clamp(0, doc.length)));
      parser.value;
    }
    parsePartialJson(doc);
    jsonDecode(doc);
  }
  print(
    '| document | pieces | PartialJsonParser, value after every piece | '
    'parsing the text so far again after every piece | jsonDecode, once at the end |',
  );
  print('| --- | --- | --- | --- | --- |');
  for (final items in [250, 1000, 4000]) {
    final doc = document(items);
    final pieces = (doc.length / piece).ceil();
    final incremental = <int>[];
    final again = <int>[];
    final whole = <int>[];
    for (var run = 0; run < 5; run++) {
      final clock = Stopwatch()..start();
      final parser = PartialJsonParser();
      for (var at = 0; at < doc.length; at += piece) {
        parser.add(doc.substring(at, (at + piece).clamp(0, doc.length)));
        parser.value;
      }
      incremental.add(clock.elapsedMicroseconds);

      // every piece, all of it: measured in full for the small document,
      // every 20th piece (times 20) for the larger ones
      final step = items <= 250 ? 1 : 20;
      clock
        ..reset()
        ..start();
      for (var at = piece; at <= doc.length; at += piece * step) {
        parsePartialJson(doc.substring(0, at));
      }
      again.add(clock.elapsedMicroseconds * step);

      clock
        ..reset()
        ..start();
      jsonDecode(doc);
      whole.add(clock.elapsedMicroseconds);
    }
    String ms(List<int> micros) => (median(micros) / 1000).toStringAsFixed(1);
    print(
      '| ${(doc.length / 1024).round()} KB | $pieces | ${ms(incremental)} ms | '
      '${items <= 250 ? '' : 'about '}${ms(again)} ms | ${ms(whole)} ms |',
    );
  }
}
