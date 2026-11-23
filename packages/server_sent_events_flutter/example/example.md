# Example

```dart
import 'package:flutter/material.dart';
import 'package:server_sent_events_flutter/server_sent_events_flutter.dart';

class Ticker extends StatelessWidget {
  const Ticker({super.key});

  @override
  Widget build(BuildContext context) => SseBuilder<List<String>>(
    connect: (onStatus) => connectSse(
      Uri.parse('http://localhost:8080/'),
      reconnect: SseReconnect.always,
      onStatus: onStatus,
    ),
    initialValue: const [],
    reduce: (ticks, event) => [...?ticks, event.data],
    builder: (context, snapshot) => ListView(
      children: [
        ListTile(title: Text('Connection: ${snapshot.status.name}')),
        for (final tick in snapshot.value!) ListTile(title: Text(tick)),
      ],
    ),
  );
}
```
