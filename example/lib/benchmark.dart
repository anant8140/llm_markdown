// Streams the same long reply twice, once into llm_markdown and once into a
// MarkdownBody that gets the whole text on every chunk (what most apps do),
// and reports frame times. Run it in profile mode:
//
//   flutter run --profile -t lib/benchmark.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/scheduler.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:material_ui/material_ui.dart';

void main() => runApp(
  const MaterialApp(debugShowCheckedModeBanner: false, home: BenchmarkPage()),
);

const _chunkSize = 12;
const _chunkEvery = Duration(milliseconds: 16);

String _section(int i) =>
    '''
## Step $i: set things up

This part explains **what happens** in step $i, with some *emphasis*, a bit of
`inline code` and a [link](https://pub.dev). Models write a lot of text like
this, so the paragraphs are long on purpose.

- First point for step $i
- Second point, a little longer than the first one
  - and a nested detail

```dart
Future<void> step$i() async {
  final result = await service.run($i);
  print(result);
}
```

| Option | Value |
| --- | --- |
| retries | $i |
| timeout | ${i * 10}s |

''';

final String _reply = [for (var i = 1; i <= 20; i++) _section(i)].join();

class BenchmarkPage extends StatefulWidget {
  const BenchmarkPage({super.key});

  @override
  State<BenchmarkPage> createState() => _BenchmarkPageState();
}

class _Result {
  _Result(this.name, List<FrameTiming> frames)
    : count = frames.length,
      build = frames.map((f) => f.buildDuration.inMicroseconds / 1000).toList()
        ..sort(),
      raster =
          frames.map((f) => f.rasterDuration.inMicroseconds / 1000).toList()
            ..sort();

  final String name;
  final int count;
  final List<double> build;
  final List<double> raster;

  double _avg(List<double> v) =>
      v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
  double _p(List<double> v, double q) =>
      v.isEmpty ? 0 : v[min(v.length - 1, (v.length * q).floor())];

  int get slowFrames => build.where((ms) => ms > 16.7).length;

  Map<String, Object> toJson() => {
    'name': name,
    'frames': count,
    'buildAvgMs': _avg(build).toStringAsFixed(2),
    'buildP90Ms': _p(build, 0.9).toStringAsFixed(2),
    'buildMaxMs': (build.isEmpty ? 0 : build.last).toStringAsFixed(2),
    'rasterAvgMs': _avg(raster).toStringAsFixed(2),
    'slowBuildFrames': slowFrames,
  };
}

class _BenchmarkPageState extends State<BenchmarkPage> {
  final _results = <_Result>[];
  String _status = 'Starting...';
  String _baselineText = '';
  StreamingMarkdownController? _controller;
  bool _showBaseline = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAll());
  }

  Future<void> _runAll() async {
    await Future<void>.delayed(const Duration(seconds: 1));
    _results
      ..add(await _run('llm_markdown', baseline: false))
      ..add(await _run('MarkdownBody, whole text per chunk', baseline: true));
    // ignore: avoid_print
    print('BENCH ${jsonEncode([for (final r in _results) r.toJson()])}');
    setState(() => _status = 'Done');
  }

  Future<_Result> _run(String name, {required bool baseline}) async {
    setState(() {
      _status = 'Running: $name';
      _showBaseline = baseline;
      _baselineText = '';
      _controller = baseline ? null : StreamingMarkdownController();
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final frames = <FrameTiming>[];
    void collect(List<FrameTiming> timings) => frames.addAll(timings);
    SchedulerBinding.instance.addTimingsCallback(collect);

    var sent = 0;
    final done = Completer<void>();
    Timer.periodic(_chunkEvery, (timer) {
      final end = min(_reply.length, sent + _chunkSize);
      final chunk = _reply.substring(sent, end);
      sent = end;
      if (baseline) {
        setState(() => _baselineText += chunk);
      } else {
        _controller!.append(chunk);
      }
      if (sent >= _reply.length) {
        timer.cancel();
        _controller?.complete();
        done.complete();
      }
    });
    await done.future;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    SchedulerBinding.instance.removeTimingsCallback(collect);
    return _Result(name, frames);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: Text(_status)),
      body: _status == 'Done'
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('${_reply.length} characters, $_chunkSize per chunk'),
                for (final r in _results)
                  Text(const JsonEncoder.withIndent('  ').convert(r.toJson())),
              ],
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _showBaseline
                  ? MarkdownBody(data: _baselineText)
                  : controller == null
                  ? const SizedBox()
                  : StreamingMarkdown(
                      controller: controller,
                      smoothing: const Smoothing.none(),
                    ),
            ),
    );
  }
}
