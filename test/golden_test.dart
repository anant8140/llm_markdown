@Tags(['golden'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';

// Text is drawn with the test font (boxes), so the pictures are the same on
// every machine except for edge smoothing; allow a little of that.
class _Tolerant extends LocalFileComparator {
  _Tolerant(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= 0.005) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}

const _reply = '''
# Getting started

Install it, then **wrap** your reply in `StreamingMarkdown`.

1. Add the package
2. Stream the reply
   - with a controller
   - or a `Stream<String>`

> [!TIP]
> Keep one controller per message.

| Option | Default |
| --- | --- |
| smoothing | adaptive |
| cursor | block |

```dart
final controller = StreamingMarkdownController();
controller.append('Hello');
```

- [x] tests
- [ ] docs
''';

const _styledDiagrams = '''
```mermaid
flowchart LR
  classDef ok fill:#d4edda,stroke:#28a745,stroke-width:2px
  classDef bad fill:#8b0000,stroke:#400
  A[Request] --> B{Valid?}
  B -->|yes| C[Save]:::ok
  B -->|no| D[Reject]:::bad
  C --> E[Done]
  style E fill:gold,stroke:#333,stroke-dasharray:5 5
  linkStyle 1 stroke:#28a745,stroke-width:3px
  linkStyle 2 stroke:#c00,stroke-width:3px
```

```mermaid
stateDiagram-v2
  classDef active fill:#cfe2ff,stroke:#0d6efd
  [*] --> Idle
  Idle --> Running
  Running --> Idle
  class Running active
```
''';

const _newKinds = '''
```mermaid
gitGraph
  commit id: "init"
  branch feature
  commit id: "add"
  commit id: "test"
  checkout main
  commit id: "fix" tag: "v1.0"
  merge feature
  commit id: "ship" type: HIGHLIGHT
```

```mermaid
journey
  title A reply reaches the screen
  section Ask
    Type a question: 5: User
    Send it: 4: User, App
  section Answer
    Wait for the model: 2: User
    Read the reply: 5: User
```

```mermaid
quadrantChart
  title Packages
  x-axis Low effort --> High effort
  y-axis Low value --> High value
  quadrant-1 Plan
  quadrant-2 Do first
  quadrant-3 Skip
  quadrant-4 Later
  Benchmarks: [0.25, 0.8]
  Chat list: [0.7, 0.75]
  Colors: [0.3, 0.3]
  Schema: [0.8, 0.35]
```

```mermaid
sankey-beta
Prompt,Model,100
Model,Text,60
Model,Tool calls,25
Model,Thinking,15
Tool calls,Search,20
Tool calls,Weather,5
```

```mermaid
xychart-beta
  title Downloads
  x-axis [Jul, Aug, Sep, Oct, Nov]
  y-axis "per month" 0 --> 500
  bar [40, 90, 160, 280, 430]
  line [30, 100, 150, 300, 420]
```
''';

const _diagrams = '''
```mermaid
flowchart TD
  A[Question] --> B{Cached?}
  B -->|yes| C(Answer)
  B -->|no| D([Ask the model])
  D --> E((Save))
  E -.-> C
```

```mermaid
sequenceDiagram
  participant U as User
  participant A as App
  U->>A: Send
  A-->>U: Stream
  Note right of A: heal and parse
  A->>A: cache
```

```mermaid
pie title Tokens
"Prompt" : 30
"Reply" : 55
"Thinking" : 15
```
''';

const _moreDiagrams = '''
```mermaid
stateDiagram-v2
  [*] --> Idle
  Idle --> Streaming : send
  Streaming --> Idle : done
  Streaming --> Failed : error
  state retry <<choice>>
  Failed --> retry
  retry --> Streaming : again
  retry --> [*] : give up
```

```mermaid
classDiagram
  class Reply {
    <<abstract>>
    +String text
    +bool complete
    +append(chunk) void
  }
  Reply <|-- ChatReply
  Chat "1" *-- "many" Reply
  Chat o-- User
  ChatReply ..> Parser : uses
```
''';

const _otherKinds = '''
```mermaid
flowchart TD
  subgraph api [API]
    G[Gateway] --> A[Auth]
    G --> O[Orders]
  end
  subgraph data [Data kept for years]
    DB[(Postgres)]
  end
  U[User] --> G
  U --> CDN[CDN]
  A --> DB
  O --> DB
```

```mermaid
stateDiagram-v2
  [*] --> Idle
  Idle --> Busy : start
  state Busy {
    [*] --> Fetching
    Fetching --> Parsing
    Parsing --> [*]
  }
  Busy --> Idle : done
  note right of Idle : waiting
  note right of Busy : working
```

```mermaid
classDiagram
  Chat "1" *-- "many" Message : holds
  Chat "1" o-- "1..*" User
  note for Chat "one per thread"
```

```mermaid
erDiagram
  "Customer Account" only one to zero or many ORDER : places
  ORDER ||--|{ ITEM : contains
  "Customer Account" {
    string name PK
    int age
  }
```

```mermaid
gantt
  title Release
  dateFormat YYYY-MM-DD
  section Build
  Design :done, a1, 2024-01-01, 3d
  Code :active, a2, after a1, 1w
  section Ship
  Test :crit, 2024-01-08, 2024-01-12
  Launch :milestone, m1, 2024-01-15, 2d
```

```mermaid
mindmap
  root((Plan))
    Goals
      Speed
      id1[Cost]
    Risks
      r)Scope(
      b))Delay((
```

```mermaid
stateDiagram-v2
  direction LR
  A --> B
  B --> C
  A --> C
  note right of B : hi
  note left of A : lo
  state D {
    Wait
    Run --> Wait
  }
  C --> D
  note right of D : boxed
```

```mermaid
gantt
  dateFormat D MMM YYYY
  axisFormat %a %e
  excludes weekends
  A :a, 4 Jan 2024, 2d
  B :b, after a, until c
  C :c, 12 Jan 2024, 1d
```

```mermaid
timeline
  title History
  section Early
    2002 : LinkedIn
    2004 : Facebook : Google
    10:30 : Talk: part one
  section Later
    2010 : Instagram
```
''';

Widget _scene({
  required String text,
  bool dark = false,
  TextDirection direction = TextDirection.ltr,
  bool complete = true,
}) {
  final background = dark ? const Color(0xFF1E1F22) : const Color(0xFFFFFFFF);
  final color = dark ? const Color(0xFFE6E6E6) : const Color(0xFF202124);
  return WidgetsApp(
    color: const Color(0xFF2196F3),
    debugShowCheckedModeBanner: false,
    builder: (context, _) => Directionality(
      textDirection: direction,
      child: ColoredBox(
        color: background,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DefaultTextStyle(
            style: TextStyle(fontSize: 14, color: color),
            child: StreamingMarkdown.text(
              text,
              isComplete: complete,
              smoothing: const Smoothing.none(),
              detectTextDirection: false,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    final local = goldenFileComparator as LocalFileComparator;
    goldenFileComparator = _Tolerant(local.basedir.resolve('golden_test.dart'));
  });

  Future<void> shoot(
    WidgetTester tester,
    Widget scene,
    String name, {
    double height = 900,
  }) async {
    tester.view
      ..physicalSize = Size(420, height)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(scene);
    await tester.pump();
    await expectLater(
      find.byType(WidgetsApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('a full reply, light', (tester) async {
    await shoot(tester, _scene(text: _reply), 'reply_light');
  });

  testWidgets('a full reply, dark', (tester) async {
    await shoot(tester, _scene(text: _reply, dark: true), 'reply_dark');
  });

  testWidgets('right to left', (tester) async {
    await shoot(
      tester,
      _scene(text: _reply, direction: TextDirection.rtl),
      'reply_rtl',
    );
  });

  testWidgets('diagrams', (tester) async {
    await shoot(tester, _scene(text: _diagrams), 'diagrams', height: 1100);
  });

  testWidgets('state and class diagrams', (tester) async {
    await shoot(
      tester,
      _scene(text: _moreDiagrams),
      'state_class_diagrams',
      height: 1080,
    );
  });

  testWidgets('more diagram kinds', (tester) async {
    await shoot(
      tester,
      _scene(text: _otherKinds),
      'more_diagram_kinds',
      height: 2900,
    );
  });

  testWidgets('diagrams in their own colors', (tester) async {
    await shoot(
      tester,
      _scene(text: _styledDiagrams),
      'styled_diagrams',
      height: 430,
    );
  });

  testWidgets('git, journey, quadrant, sankey and xy charts', (tester) async {
    await shoot(
      tester,
      _scene(text: _newKinds),
      'new_diagram_kinds',
      height: 1400,
    );
  });

  testWidgets('git, journey, quadrant, sankey and xy charts, dark', (
    tester,
  ) async {
    await shoot(
      tester,
      _scene(text: _newKinds, dark: true),
      'new_diagram_kinds_dark',
      height: 1400,
    );
  });

  testWidgets('the selection menu', (tester) async {
    tester.view
      ..physicalSize = const Size(420, 240)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF2196F3),
        debugShowCheckedModeBanner: false,
        pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
          pageBuilder: (context, _, _) => builder(context),
        ),
        home: ColoredBox(
          color: const Color(0xFFFFFFFF),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 110, 16, 16),
            child: DefaultTextStyle(
              style: const TextStyle(fontSize: 14, color: Color(0xFF202124)),
              child: MarkdownSelectionArea(
                actions: [
                  MarkdownSelectionAction(label: 'Ask', onSelected: (_) {}),
                  MarkdownSelectionAction(label: 'Quote', onSelected: (_) {}),
                ],
                child: const StreamingMarkdown.text(
                  'Select a few of these words to see the menu.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.longPressAt(const Offset(120, 118));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(WidgetsApp),
      matchesGoldenFile('goldens/selection_menu.png'),
    );
  });

  testWidgets('half way through a stream', (tester) async {
    await shoot(
      tester,
      _scene(text: _reply.substring(0, 260), complete: false),
      'reply_streaming',
    );
  });
}
