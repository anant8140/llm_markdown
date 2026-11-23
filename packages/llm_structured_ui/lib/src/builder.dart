import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'value.dart';

/// Builds a widget from the document so far.
typedef StructuredWidgetBuilder =
    Widget Function(BuildContext context, StructuredValue data);

/// Builds a widget for an error; [data] is what was read before it.
typedef StructuredErrorBuilder =
    Widget Function(BuildContext context, Object error, StructuredValue data);

/// Rebuilds as a JSON document arrives, from a
/// [StructuredStreamController] or straight from a stream of text.
///
/// ```dart
/// StructuredBuilder.stream(
///   modelTextStream,
///   builder: (context, data) => Text(data['title'].asString ?? ''),
/// )
/// ```
class StructuredBuilder extends StatefulWidget {
  /// Rebuilds whenever [controller] changes.
  const StructuredBuilder({
    super.key,
    required StructuredStreamController this.controller,
    required this.builder,
    this.errorBuilder,
  }) : stream = null,
       repair = false;

  /// Reads [stream] with a controller of its own. A new stream starts a
  /// new document.
  const StructuredBuilder.stream(
    Stream<String> this.stream, {
    super.key,
    required this.builder,
    this.errorBuilder,
    this.repair = false,
  }) : controller = null;

  /// The controller that is followed, when made with the default
  /// constructor.
  final StructuredStreamController? controller;

  /// The stream that is read, when made with [StructuredBuilder.stream].
  final Stream<String>? stream;

  /// Whether common mistakes in model JSON are read anyway; used with
  /// [StructuredBuilder.stream].
  final bool repair;

  /// Builds the widget from the document so far.
  final StructuredWidgetBuilder builder;

  /// Builds the widget once the controller has an error. Without it,
  /// [builder] keeps showing what was read before the error.
  final StructuredErrorBuilder? errorBuilder;

  @override
  State<StructuredBuilder> createState() => _StructuredBuilderState();
}

class _StructuredBuilderState extends State<StructuredBuilder> {
  StructuredStreamController? _own;

  StructuredStreamController get _controller => widget.controller ?? _own!;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(StructuredBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.stream != widget.stream ||
        oldWidget.repair != widget.repair) {
      _detach(oldWidget);
      _attach();
    }
  }

  void _attach() {
    final stream = widget.stream;
    if (stream != null) {
      _own = StructuredStreamController(repair: widget.repair)
        ..addStream(stream);
    }
    _controller.addListener(_changed);
  }

  void _detach(StructuredBuilder oldWidget) {
    (oldWidget.controller ?? _own)?.removeListener(_changed);
    _own?.dispose();
    _own = null;
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _detach(widget);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final data = controller.data;
    final error = controller.error;
    final errorBuilder = widget.errorBuilder;
    if (error != null && errorBuilder != null) {
      return errorBuilder(context, error, data);
    }
    return widget.builder(context, data);
  }
}
