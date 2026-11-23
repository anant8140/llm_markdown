import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A long chat reply: headings, lists, code, a table, math-free text.
String sampleReply({int sections = 60}) {
  final out = StringBuffer();
  for (var i = 0; i < sections; i++) {
    out
      ..writeln('## Section $i')
      ..writeln()
      ..writeln(
        'Streaming **markdown** is parsed as it arrives, with `inline code`, '
        'a [link](https://example.com/$i) and *emphasis* in every paragraph. ',
      )
      ..writeln()
      ..writeln('- first point about item $i')
      ..writeln('- second point, a little longer than the first one')
      ..writeln('- third point')
      ..writeln()
      ..writeln('```dart')
      ..writeln('final value$i = compute($i);')
      ..writeln('print(value$i);')
      ..writeln('```')
      ..writeln()
      ..writeln('| Key | Value |')
      ..writeln('| --- | ----- |')
      ..writeln('| a$i | ${i * 2} |')
      ..writeln();
  }
  return out.toString();
}

/// What one run measured.
class Result {
  Result(
    this.name,
    this.chars,
    this.chunks,
    this.peakMb,
    this.endMb,
    this.totalMs,
    this.p95Ms,
  );
  final String name;
  final int chars, chunks;
  final double peakMb, endMb, totalMs, p95Ms;

  @override
  String toString() =>
      '$name: ${chars ~/ 1000}k chars in $chunks chunks | '
      'RSS peak +${peakMb.toStringAsFixed(1)} MB, end +${endMb.toStringAsFixed(1)} MB | '
      'total ${totalMs.toStringAsFixed(0)} ms, p95 ${p95Ms.toStringAsFixed(2)} ms/chunk';
}

double _rssMb() => ProcessInfo.currentRss / (1024 * 1024);

/// Streams [text] in chunks of 2–15 characters; [show] puts the text so far
/// on screen. Measures process memory and the time of each frame.
Future<Result> run(
  WidgetTester tester,
  String name,
  String text,
  Future<void> Function(String soFar, bool done) show,
) async {
  final random = Random(1);
  await show('', false);
  await tester.pump();
  final base = _rssMb();
  var peak = base;
  final frames = <double>[];
  final total = Stopwatch()..start();
  var i = 0;
  var chunks = 0;
  while (i < text.length) {
    i = min(text.length, i + 2 + random.nextInt(14));
    chunks++;
    final frame = Stopwatch()..start();
    await show(text.substring(0, i), i == text.length);
    await tester.pump(const Duration(milliseconds: 16));
    frames.add(frame.elapsedMicroseconds / 1000);
    if (chunks % 25 == 0) peak = max(peak, _rssMb());
  }
  total.stop();
  await tester.pump(const Duration(seconds: 1));
  final end = _rssMb();
  frames.sort();
  return Result(
    name,
    text.length,
    chunks,
    max(peak, end) - base,
    end - base,
    total.elapsedMicroseconds / 1000,
    frames[(frames.length * 0.95).floor()],
  );
}

Widget host(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: MediaQuery(
    data: const MediaQueryData(size: Size(400, 800)),
    child: DefaultTextStyle(
      style: const TextStyle(fontSize: 14, color: Color(0xFF000000)),
      child: SingleChildScrollView(child: child),
    ),
  ),
);
