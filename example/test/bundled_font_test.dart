import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// An app that depends on llm_markdown gets its code font without doing
// anything.
void main() {
  testWidgets('the package\'s code font is in the app bundle', (tester) async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    final family = manifest.cast<Map<String, dynamic>>().firstWhere(
      (entry) => entry['family'] == 'packages/llm_markdown/JetBrainsMono',
    );
    final asset = ((family['fonts'] as List).first as Map)['asset'] as String;
    final bytes = await rootBundle.load(asset);
    expect(bytes.lengthInBytes, greaterThan(100000));
  });
}
