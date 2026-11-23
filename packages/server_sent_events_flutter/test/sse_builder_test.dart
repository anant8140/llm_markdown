import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:server_sent_events/testing.dart';
import 'package:server_sent_events_flutter/server_sent_events_flutter.dart';

final url = Uri.parse('https://api.test/stream');

Widget host(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);

Widget builder({
  required FakeSseClient fake,
  Object? restartKey,
  List<String>? log,
  SseReconnect reconnect = SseReconnect.none,
}) => host(
  SseBuilder<String>(
    restartKey: restartKey,
    connect: (onStatus) =>
        connectSse(url, client: fake, reconnect: reconnect, onStatus: onStatus),
    initialValue: '',
    reduce: (text, event) => '$text${event.data}',
    onEvent: (e) => log?.add('event ${e.data}'),
    onError: (e) => log?.add('error'),
    onDone: () => log?.add('done'),
    builder: (context, s) => Text(
      '${s.status.name}|${s.value}|${s.eventCount}|${s.hasError ? 'error' : 'ok'}',
    ),
  ),
);

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    // also lets timers made in the test's zone fire (a reconnect wait)
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets('builds as events arrive, then closed', (tester) async {
    final log = <String>[];
    final fake = FakeSseClient(
      (_) =>
          FakeSseResponse.events([const SseEvent('Hel'), const SseEvent('lo')]),
    );
    await tester.pumpWidget(builder(fake: fake, log: log));
    expect(find.text('connecting||0|ok'), findsOneWidget);
    await settle(tester);
    expect(find.text('closed|Hello|2|ok'), findsOneWidget);
    expect(log, ['event Hel', 'event lo', 'done']);
    expect(fake.requests, hasLength(1));
  });

  testWidgets('shows open while the stream is live', (tester) async {
    final fake = FakeSseClient(
      (_) => FakeSseResponse.events([const SseEvent('a')], keepOpen: true),
    );
    await tester.pumpWidget(builder(fake: fake));
    await settle(tester);
    expect(find.text('open|a|1|ok'), findsOneWidget);
    // rebuilding the parent does not open it again
    await tester.pumpWidget(builder(fake: fake));
    await settle(tester);
    expect(fake.requests, hasLength(1));
  });

  testWidgets('an error closes it and is reported, onDone is not called', (
    tester,
  ) async {
    final log = <String>[];
    final fake = FakeSseClient((_) => FakeSseResponse.error(401, '{"e":1}'));
    await tester.pumpWidget(builder(fake: fake, log: log));
    await settle(tester);
    expect(find.text('closed||0|error'), findsOneWidget);
    expect(log, ['error']);
  });

  testWidgets('removing the widget closes the connection', (tester) async {
    final fake = FakeSseClient(
      (_) => FakeSseResponse.events([const SseEvent('a')], keepOpen: true),
    );
    await tester.pumpWidget(builder(fake: fake));
    await settle(tester);
    expect(fake.aborted, 0);
    await tester.pumpWidget(host(const SizedBox()));
    await settle(tester);
    expect(fake.aborted, 1);
  });

  testWidgets('a new restartKey closes the old stream and starts over', (
    tester,
  ) async {
    var n = 0;
    final fake = FakeSseClient(
      (_) => FakeSseResponse.events([SseEvent('run${n++}')], keepOpen: true),
    );
    await tester.pumpWidget(builder(fake: fake, restartKey: 1));
    await settle(tester);
    expect(find.text('open|run0|1|ok'), findsOneWidget);
    await tester.pumpWidget(builder(fake: fake, restartKey: 2));
    await settle(tester);
    expect(find.text('open|run1|1|ok'), findsOneWidget);
    expect(fake.aborted, 1);
    expect(fake.requests, hasLength(2));
  });

  testWidgets('reconnecting is shown between two connections', (tester) async {
    var n = 0;
    final seen = <String>{};
    final fake = FakeSseClient(
      (_) => n++ == 0
          ? FakeSseResponse.error(503, 'busy', headers: const {})
          : FakeSseResponse.events([const SseEvent('a')], keepOpen: true),
    );
    await tester.pumpWidget(
      host(
        SseBuilder<String>(
          connect: (onStatus) => connectSse(
            url,
            client: fake,
            reconnect: const SseReconnect(
              delay: Duration(milliseconds: 30),
              jitter: 0,
            ),
            onStatus: onStatus,
          ),
          builder: (context, s) {
            seen.add(s.status.name);
            return const SizedBox();
          },
        ),
      ),
    );
    await settle(tester);
    expect(seen, containsAll(['connecting', 'reconnecting', 'open']));
  });

  test('SseStatusNotifier follows onStatus', () {
    final notifier = SseStatusNotifier();
    expect(notifier.value, isNull);
    notifier(SseStatus.reconnecting);
    expect(notifier.value, SseStatus.reconnecting);
  });
}
