# Streaming benchmark

How much memory and time it takes to stream one long reply into the
screen: `llm_markdown` against `flutter_markdown_plus`, the usual choice.

## What it does

A reply of about 20,000 characters (60 sections, each with a heading, a
paragraph with bold, code and a link, a list, a code block and a table) is
streamed in 2,472 chunks of 2 to 15 characters, the same chunks for both.
After every chunk one frame is pumped.

- **llm_markdown:** one `StreamingMarkdownController`, `append` per chunk,
  smoothing off so both show the same text at the same time.
- **flutter_markdown_plus:** the usual way, `MarkdownBody(data: textSoFar)`
  rebuilt with the whole text after every chunk.

Each package runs in its own test process. Memory is the growth of the
process's resident memory (RSS) over the run, sampled every 25 chunks;
time is the wall time of each chunk's frame.

## Results

Three runs each, on an Apple Silicon Mac, Flutter 3.50, `flutter test`
(debug mode, so absolute times are higher than in a release build; compare
the two rows, not the numbers with a phone):

| | memory peak | memory at the end | total time | 95% of chunks under |
| --- | --- | --- | --- | --- |
| llm_markdown | +123 to +131 MB | +94 to +96 MB | 11.1 to 12.3 s | 7.6 to 8.6 ms |
| flutter_markdown_plus | +282 to +294 MB | +270 to +279 MB | 144.7 to 147.9 s | 135 to 140 ms |

So for this reply `llm_markdown` used about 2.3 times less memory at its
peak and about 12 times less time, and a typical chunk took about 8 ms
instead of about 138 ms, which is the difference between smooth and a
visible stutter.

Why: `flutter_markdown_plus` parses and builds the whole reply again on
every chunk, so the work per chunk grows with the reply. `llm_markdown`
parses only the last, unfinished block again and keeps the widgets of the
finished blocks.

## Limits of this measurement

- RSS is the whole process, including Flutter's own caches and memory the
  allocator keeps after Dart frees it; it shows the difference between the
  two, not the exact size of either one's objects.
- Debug mode is slower than release, and more for some code than other.
- One kind of reply; replies with many diagrams or formulas behave
  differently.

## Running it

```bash
cd benchmark
flutter pub get
flutter test test/llm_markdown_test.dart
flutter test test/flutter_markdown_plus_test.dart
```

Each prints a `RESULT` line. Run them one at a time, so each has the
process to itself.
