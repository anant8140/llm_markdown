import 'parser.dart';

/// Something in a value that doesn't fit its JSON Schema.
class JsonSchemaIssue {
  /// An issue at [path] described by [message].
  const JsonSchemaIssue(this.path, this.message, {this.isMissing = false});

  /// Where it is, such as `['items', 2, 'price']`.
  final List<Object> path;

  /// What is wrong, in words.
  final String message;

  /// Whether a required property is missing, as opposed to a value that
  /// is there and wrong.
  final bool isMissing;

  @override
  String toString() =>
      '${path.isEmpty ? 'the document' : path.join('.')}: $message';
}

/// Checks [value] against [schema], a JSON Schema as a map, and gives what
/// doesn't fit; an empty list means it fits.
///
/// For a value that is still being written, give the parser's
/// [pendingPath] and [isComplete]: a value still being written is checked
/// only for what can't change any more. Its type is checked, but a missing
/// required property, a too short string or list, `enum` and `const` are
/// reported only once the value is finished. So an issue during streaming
/// is a real one, and the reply can be stopped early.
///
/// This reads the keywords models are given for structured output:
/// `type` (also a list of types), `properties`, `required`,
/// `additionalProperties` (false or a schema), `items`, `enum`, `const`,
/// `minimum`, `maximum`, `exclusiveMinimum`, `exclusiveMaximum`,
/// `minLength`, `maxLength`, `minItems`, `maxItems`, `anyOf`, `oneOf`,
/// `allOf` and `nullable`. Other keywords, `$ref` and `pattern` among
/// them, are ignored.
List<JsonSchemaIssue> checkJsonSchema(
  Object? value,
  Map<String, Object?> schema, {
  List<Object> pendingPath = const [],
  bool isComplete = true,
}) {
  final issues = <JsonSchemaIssue>[];
  _Check(pendingPath, isComplete, issues).check(value, schema, const []);
  return issues;
}

/// Checks the value a [parser] has so far against [schema]; see
/// [checkJsonSchema].
List<JsonSchemaIssue> checkPartialJson(
  PartialJsonParser parser,
  Map<String, Object?> schema,
) => parser.hasValue
    ? checkJsonSchema(
        parser.value,
        schema,
        pendingPath: parser.pendingPath,
        isComplete: parser.isComplete,
      )
    : const [];

class _Check {
  _Check(this.pending, this.complete, this.issues);

  final List<Object> pending;
  final bool complete;
  final List<JsonSchemaIssue> issues;

  // Whether the value at [path] can still change.
  bool _open(List<Object> path) {
    if (complete || path.length > pending.length) return false;
    for (var i = 0; i < path.length; i++) {
      if (path[i] != pending[i]) return false;
    }
    return true;
  }

  void _add(List<Object> path, String message, {bool missing = false}) =>
      issues.add(JsonSchemaIssue(path, message, isMissing: missing));

  static String _typeOf(Object? value) => switch (value) {
    null => 'null',
    bool() => 'boolean',
    int() || BigInt() => 'integer',
    num() => 'number',
    String() => 'string',
    List() => 'array',
    Map() => 'object',
    _ => 'unknown',
  };

  static bool _fits(String actual, Object? wanted) =>
      wanted == actual ||
      (wanted == 'number' && actual == 'integer') ||
      // 2.0 is an integer in JSON Schema
      false;

  void check(Object? value, Map<String, Object?> schema, List<Object> path) {
    final open = _open(path);
    var actual = _typeOf(value);
    if (actual == 'number' &&
        value is double &&
        value == value.truncateToDouble()) {
      // a whole number written as 2.0 counts as an integer too
      if (_wants(schema, 'integer') && !_wants(schema, 'number')) {
        actual = 'integer';
      }
    }

    final type = schema['type'];
    final types = type is List ? type : [?type];
    final nullable = schema['nullable'] == true;
    if (types.isNotEmpty &&
        !(nullable && value == null) &&
        !types.any((wanted) => _fits(actual, wanted))) {
      // a number being written may still become a fraction, and a started
      // literal is a guess: wait for them to finish
      if (!(open && (value is num || value is bool || value == null))) {
        _add(path, 'is $actual, expected ${types.join(' or ')}');
      }
      return;
    }

    for (final key in const ['allOf']) {
      final all = schema[key];
      if (all is List) {
        for (final part in all.whereType<Map<String, Object?>>()) {
          check(value, part, path);
        }
      }
    }
    for (final key in const ['anyOf', 'oneOf']) {
      final options = schema[key];
      if (options is! List || options.isEmpty) continue;
      // while it is written, one option fitting so far is enough
      final fits = options.whereType<Map<String, Object?>>().where((option) {
        final found = <JsonSchemaIssue>[];
        _Check(pending, complete, found).check(value, option, path);
        return found.isEmpty;
      }).length;
      if (fits == 0) {
        _add(path, 'fits none of the $key options');
      } else if (key == 'oneOf' && fits > 1 && !open) {
        _add(path, 'fits more than one of the oneOf options');
      }
    }

    if (!open) {
      final allowed = schema['enum'];
      if (allowed is List && !allowed.any((item) => _same(item, value))) {
        _add(path, 'is not one of ${allowed.join(', ')}');
      }
      if (schema.containsKey('const') && !_same(schema['const'], value)) {
        _add(path, 'is not ${schema['const']}');
      }
    }

    switch (value) {
      case String():
        final max = schema['maxLength'];
        if (max is int && value.runes.length > max) {
          _add(path, 'is longer than $max characters');
        }
        final min = schema['minLength'];
        if (!open && min is int && value.runes.length < min) {
          _add(path, 'is shorter than $min characters');
        }
      case num():
        if (open) break;
        final min = schema['minimum'];
        if (min is num && value < min) _add(path, 'is less than $min');
        final max = schema['maximum'];
        if (max is num && value > max) _add(path, 'is more than $max');
        final above = schema['exclusiveMinimum'];
        if (above is num && value <= above) {
          _add(path, 'is not more than $above');
        }
        final below = schema['exclusiveMaximum'];
        if (below is num && value >= below) {
          _add(path, 'is not less than $below');
        }
      case List():
        final max = schema['maxItems'];
        if (max is int && value.length > max) {
          _add(path, 'has more than $max items');
        }
        final min = schema['minItems'];
        if (!open && min is int && value.length < min) {
          _add(path, 'has fewer than $min items');
        }
        final items = schema['items'];
        if (items is Map<String, Object?>) {
          for (var i = 0; i < value.length; i++) {
            check(value[i], items, [...path, i]);
          }
        }
      case Map():
        final properties = schema['properties'];
        final known = properties is Map
            ? properties
            : const <String, Object?>{};
        final extra = schema['additionalProperties'];
        for (final entry in value.entries) {
          final key = entry.key as String;
          final property = known[key];
          if (property is Map<String, Object?>) {
            check(entry.value, property, [...path, key]);
          } else if (!known.containsKey(key)) {
            if (extra == false) {
              _add([...path, key], 'is not a property of the schema');
            } else if (extra is Map<String, Object?>) {
              check(entry.value, extra, [...path, key]);
            }
          }
        }
        final required = schema['required'];
        if (!open && required is List) {
          for (final key in required) {
            if (!value.containsKey(key)) {
              _add([...path, key as Object], 'is required', missing: true);
            }
          }
        }
    }
  }

  static bool _wants(Map<String, Object?> schema, String type) {
    final wanted = schema['type'];
    return wanted == type || (wanted is List && wanted.contains(type));
  }

  static bool _same(Object? a, Object? b) {
    if (a is num && b is num) return a == b;
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_same(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_same(a[key], b[key])) return false;
      }
      return true;
    }
    return a == b;
  }
}
