/// Link schemes allowed by default. Others, like `javascript:` or `file:`,
/// are shown as plain text.
const Set<String> defaultLinkSchemes = {'http', 'https', 'mailto', 'tel'};

/// Image schemes allowed by default. `data:` and `file:` images are not
/// loaded; their alt text is shown instead.
const Set<String> defaultImageSchemes = {'http', 'https'};

final RegExp _invisible = RegExp(r'[\u0000- \u007F-\u009F​-‏]');
final RegExp _scheme = RegExp(r'^([A-Za-z][A-Za-z0-9+.\-]*):');

// Model output can contain links nobody checked. Control characters and
// spaces are dropped first, so "java\tscript:" is caught too. Links without
// a scheme (relative ones) are left to the app.
bool isAllowedUrl(String? url, Set<String> schemes) {
  if (url == null) return false;
  final match = _scheme.firstMatch(url.replaceAll(_invisible, ''));
  return match == null || schemes.contains(match[1]!.toLowerCase());
}
