import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart'
    show encodeSvg;

/// Whether [bytes] are an SVG picture that can be drawn.
bool isDrawableSvg(Uint8List bytes) {
  try {
    encodeSvg(
      xml: utf8.decode(bytes),
      debugName: 'svg',
      // these need native libraries that apps don't have
      enableMaskingOptimizer: false,
      enableClippingOptimizer: false,
      enableOverdrawOptimizer: false,
    );
    return true;
  } catch (_) {
    return false;
  }
}

/// An SVG picture from the network or from memory.
///
/// The picture is fetched and checked here first, and only handed on when
/// it can be drawn: older versions of flutter_svg throw an error nobody can
/// catch for a failed download or broken file. Anything that goes wrong
/// shows [fallback].
class SvgImage extends StatefulWidget {
  const SvgImage({
    super.key,
    this.uri,
    this.bytes,
    this.alt,
    required this.fallback,
  }) : assert(uri != null || bytes != null, 'give a uri or bytes');

  final Uri? uri;
  final Uint8List? bytes;
  final String? alt;
  final WidgetBuilder fallback;

  // downloaded pictures, so a reply scrolled back into view doesn't fetch
  // them again
  static final Map<Uri, Future<Uint8List?>> _cache = {};
  static const int _cacheSize = 32;

  @override
  State<SvgImage> createState() => _SvgImageState();
}

class _SvgImageState extends State<SvgImage> {
  late Future<Uint8List?> _picture = _load();

  @override
  void didUpdateWidget(SvgImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri ||
        !identical(oldWidget.bytes, widget.bytes)) {
      _picture = _load();
    }
  }

  Future<Uint8List?> _load() {
    final bytes = widget.bytes;
    if (bytes != null) return _checked(Future.value(bytes));
    final uri = widget.uri!;
    final cached = SvgImage._cache.remove(uri);
    final loading = cached ?? _checked(http.readBytes(uri));
    // newest last; the oldest one goes when the cache is full
    SvgImage._cache[uri] = loading;
    if (SvgImage._cache.length > SvgImage._cacheSize) {
      SvgImage._cache.remove(SvgImage._cache.keys.first);
    }
    if (cached == null) {
      // a failed download is tried again next time
      loading.then((picture) {
        if (picture == null && identical(SvgImage._cache[uri], loading)) {
          SvgImage._cache.remove(uri);
        }
      });
    }
    return loading;
  }

  static Future<Uint8List?> _checked(Future<Uint8List> source) async {
    try {
      final bytes = await source;
      // a big file is checked off the UI thread
      final drawable = bytes.length > 100 * 1024
          ? await compute(isDrawableSvg, bytes)
          : isDrawableSvg(bytes);
      return drawable ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _picture,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const SizedBox.shrink();
      }
      final bytes = snapshot.data;
      if (bytes == null) return widget.fallback(context);
      return SvgPicture.memory(bytes, semanticsLabel: widget.alt);
    },
  );
}
