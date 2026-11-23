import 'package:partial_json/partial_json.dart';

/// Shows how a recipe from an AI model looks while it streams in.
void main() {
  const reply =
      'Here is the recipe:\n```json\n'
      '{"title": "Tomato soup", "minutes": 25, '
      '"steps": ["Chop the onion", "Add the tomatoes", "Blend"]}\n```';
  final parser = PartialJsonParser();
  for (var i = 0; i < reply.length; i += 12) {
    parser.add(
      reply.substring(i, i + 12 > reply.length ? reply.length : i + 12),
    );
    if (parser.hasValue) {
      print('${parser.value}   still writing: ${parser.pendingPath}');
    }
  }
  print('done: ${parser.close()}');
}
