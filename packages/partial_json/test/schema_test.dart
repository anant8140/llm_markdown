import 'package:partial_json/partial_json.dart';
import 'package:test/test.dart';

const recipe = <String, Object?>{
  'type': 'object',
  'required': ['title', 'minutes', 'steps'],
  'additionalProperties': false,
  'properties': {
    'title': {'type': 'string', 'minLength': 3, 'maxLength': 20},
    'minutes': {'type': 'integer', 'minimum': 1, 'maximum': 600},
    'level': {
      'type': 'string',
      'enum': ['easy', 'hard'],
    },
    'steps': {
      'type': 'array',
      'minItems': 2,
      'maxItems': 3,
      'items': {'type': 'string'},
    },
    'note': {
      'type': ['string', 'null'],
    },
  },
};

List<String> issues(String text, {Map<String, Object?> schema = recipe}) =>
    checkPartialJson(
      PartialJsonParser()..add(text),
      schema,
    ).map((i) => '$i').toList();

void main() {
  test('a complete value that fits has no issues', () {
    expect(
      issues(
        '{"title": "Soup", "minutes": 25, "level": "easy", '
        '"steps": ["a", "b"], "note": null}',
      ),
      isEmpty,
    );
  });

  test('a complete value: every kind of issue, with its path', () {
    expect(
      issues(
        '{"title": "So", "minutes": 0, "level": "medium", '
        '"steps": ["a", 2, "c", "d"], "extra": true}',
      ),
      [
        'title: is shorter than 3 characters',
        'minutes: is less than 1',
        'level: is not one of easy, hard',
        'steps: has more than 3 items',
        'steps.1: is integer, expected string',
        'extra: is not a property of the schema',
      ],
    );
    expect(issues('{"title": "Soup"}'), [
      'minutes: is required',
      'steps: is required',
    ]);
    final missing = checkJsonSchema({'title': 'Soup'}, recipe);
    expect(missing.every((i) => i.isMissing), isTrue);
    expect(missing.first.path, ['minutes']);
    expect(issues('[1]'), ['the document: is array, expected object']);
  });

  test('while it is written, only what cannot change is reported', () {
    // nothing is missing yet, a short title may still grow, 0 may become 30,
    // "eas" may become "easy", one step may become two
    expect(issues('{"title": "So'), isEmpty);
    expect(issues('{"title": "Soup", "minutes": 0'), isEmpty);
    expect(issues('{"title": "Soup", "minutes": 30, "level": "eas'), isEmpty);
    expect(issues('{"title": "Soup", "minutes": 30, "steps": ["a"'), isEmpty);
    // a title that is finished and too short is wrong for good
    expect(issues('{"title": "So", "min'), [
      'title: is shorter than 3 characters',
    ]);
    // too long, a wrong type and an unknown property can't get better
    expect(issues('{"title": "A very long title that goes on'), [
      'title: is longer than 20 characters',
    ]);
    expect(issues('{"title": ["x'), ['title: is array, expected string']);
    expect(issues('{"title": "Soup", "extra": "x'), [
      'extra: is not a property of the schema',
    ]);
    expect(issues('{"title": "Soup", "steps": ["a", "b", "c", "d'), [
      'steps: has more than 3 items',
    ]);
    // a finished inner object is checked in full while the outer one grows
    expect(
      issues(
        '{"list": [{"a": 1}, {"b": 2}, {"a"',
        schema: const {
          'type': 'object',
          'properties': {
            'list': {
              'type': 'array',
              'items': {
                'type': 'object',
                'required': ['a'],
              },
            },
          },
        },
      ),
      ['list.1.a: is required'],
    );
  });

  test('numbers: a pending 2 may become 2.5; 2.0 fits integer', () {
    const schema = <String, Object?>{
      'type': 'array',
      'items': {'type': 'string'},
    };
    expect(issues('[2', schema: schema), isEmpty);
    expect(issues('[2,', schema: schema), ['0: is integer, expected string']);
    expect(checkJsonSchema(2.0, const {'type': 'integer'}), isEmpty);
    expect(checkJsonSchema(2.5, const {'type': 'integer'}), hasLength(1));
    expect(checkJsonSchema(2, const {'type': 'number'}), isEmpty);
    expect(checkJsonSchema(5, const {'exclusiveMinimum': 5}), hasLength(1));
    expect(checkJsonSchema(5, const {'exclusiveMaximum': 5}), hasLength(1));
    expect(checkJsonSchema(7, const {'maximum': 6}), hasLength(1));
  });

  test('nullable, const, anyOf, oneOf, allOf', () {
    expect(
      checkJsonSchema(null, const {'type': 'string', 'nullable': true}),
      isEmpty,
    );
    expect(checkJsonSchema(null, const {'type': 'string'}), hasLength(1));
    expect(checkJsonSchema('a', const {'const': 'b'}), hasLength(1));
    expect(
      checkJsonSchema(
        {
          'x': [1, 2.0],
        },
        const {
          'const': {
            'x': [1, 2],
          },
        },
      ),
      isEmpty,
    );
    const either = <String, Object?>{
      'anyOf': [
        {'type': 'string'},
        {'type': 'integer', 'minimum': 10},
      ],
    };
    expect(checkJsonSchema('a', either), isEmpty);
    expect(checkJsonSchema(12, either), isEmpty);
    expect(
      checkJsonSchema(3, either).single.message,
      'fits none of the anyOf options',
    );
    const one = <String, Object?>{
      'oneOf': [
        {'type': 'number'},
        {'type': 'integer'},
      ],
    };
    expect(checkJsonSchema(1.5, one), isEmpty);
    expect(checkJsonSchema(1, one).single.message, contains('more than one'));
    expect(
      checkJsonSchema('abcdef', const {
        'allOf': [
          {'minLength': 2},
          {'maxLength': 4},
        ],
      }).single.message,
      'is longer than 4 characters',
    );
  });

  test('additionalProperties as a schema; unknown keywords are ignored', () {
    expect(
      checkJsonSchema(
        {'a': 1, 'b': 'x'},
        const {
          'type': 'object',
          'additionalProperties': {'type': 'integer'},
          'pattern': '^x',
          r'$ref': '#/nope',
        },
      ).map((i) => '$i'),
      ['b: is string, expected integer'],
    );
  });

  test('no value yet gives no issues', () {
    expect(
      checkPartialJson(PartialJsonParser()..add('Sure: '), recipe),
      isEmpty,
    );
  });
}
