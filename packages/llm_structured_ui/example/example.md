# Example

A screen that asks a model for a recipe as JSON and shows it while it is
written. `fakeModel` stands in for the model's stream of text.

```dart
import 'package:flutter/widgets.dart';
import 'package:llm_structured_ui/llm_structured_ui.dart';

const _reply =
    '{"title": "Pancakes", "servings": 4, "minutes": 20, '
    '"summary": "Thin and **quick**.", '
    '"steps": [{"text": "Mix flour, milk and eggs."}, '
    '{"text": "Fry in a hot pan."}]}';

/// Sends the reply a few characters at a time, like a model does.
Stream<String> fakeModel() async* {
  for (var i = 0; i < _reply.length; i += 6) {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    yield _reply.substring(i, (i + 6).clamp(0, _reply.length));
  }
}

class RecipeView extends StatefulWidget {
  const RecipeView({super.key});

  @override
  State<RecipeView> createState() => _RecipeViewState();
}

class _RecipeViewState extends State<RecipeView> {
  final _controller = StructuredStreamController();

  @override
  void initState() {
    super.initState();
    _controller.addStream(fakeModel());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StructuredBuilder(
      controller: _controller,
      errorBuilder: (context, error, recipe) =>
          Text('Could not read the recipe: $error'),
      builder: (context, recipe) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StructuredText(recipe['title']),
          StructuredFields(
            recipe,
            order: const ['servings', 'minutes'],
            labels: const {'servings': 'Serves', 'minutes': 'Time (min)'},
            hide: const {'title', 'summary', 'steps'},
          ),
          StructuredText(recipe['summary'], markdown: true),
          StructuredList(
            recipe['steps'],
            itemBuilder: (context, step, index) =>
                Text('${index + 1}. ${step['text'].asString ?? ''}'),
          ),
        ],
      ),
    );
  }
}
```

To see any JSON without writing a layout:

```dart
StructuredBuilder.stream(
  modelTextStream,
  builder: (context, data) => StructuredAuto(data),
)
```
