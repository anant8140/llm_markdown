import 'package:partial_json/partial_json.dart';

/// A model class as json_serializable or freezed would generate it: the
/// parser gives plain maps, so `fromJson` works as usual.
class Recipe {
  const Recipe({required this.name, required this.minutes});

  factory Recipe.fromJson(Map<String, dynamic> json) =>
      Recipe(name: json['name'] as String, minutes: json['minutes'] as int);

  final String name;
  final int minutes;

  @override
  String toString() => 'Recipe($name, $minutes min)';
}

Future<void> main() async {
  // the reply of a model, arriving in pieces
  final reply = Stream.fromIterable([
    '{"recipes": [{"name": "Tomato so',
    'up", "minutes": 25}, {"name": "Pan',
    'cakes", "minutes": 15}]}',
  ]);

  // each recipe as a typed object as soon as it is finished; an unfinished
  // one never reaches fromJson, so required fields are always there
  final recipes = reply.transform(
    PartialJsonItemDecoder(
      path: const ['recipes'],
      convert: (json) => Recipe.fromJson(json! as Map<String, dynamic>),
    ),
  );
  await for (final recipe in recipes) {
    print(recipe);
  }
}
