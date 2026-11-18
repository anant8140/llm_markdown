import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Shows at most [maxHeight] of its child; what is cut off fades out over
/// the last [fadeHeight] when [fade] is true.
class HeightClip extends SingleChildRenderObjectWidget {
  const HeightClip({
    super.key,
    required this.maxHeight,
    required this.fadeHeight,
    required this.fade,
    super.child,
  });

  final double maxHeight;
  final double fadeHeight;
  final bool fade;

  @override
  RenderHeightClip createRenderObject(BuildContext context) =>
      RenderHeightClip(maxHeight, fadeHeight, fade);

  @override
  void updateRenderObject(BuildContext context, RenderHeightClip renderObject) {
    renderObject
      ..maxHeight = maxHeight
      ..fadeHeight = fadeHeight
      ..fade = fade;
  }
}

class RenderHeightClip extends RenderProxyBox {
  RenderHeightClip(this._maxHeight, this._fadeHeight, this._fade);

  double _maxHeight;
  set maxHeight(double value) {
    if (value == _maxHeight) return;
    _maxHeight = value;
    markNeedsLayout();
  }

  double _fadeHeight;
  set fadeHeight(double value) {
    if (value == _fadeHeight) return;
    _fadeHeight = value;
    markNeedsPaint();
  }

  bool _fade;
  set fade(bool value) {
    if (value == _fade) return;
    _fade = value;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  /// Whether some of the child is cut off.
  bool get overflowing =>
      child != null && child!.size.height > size.height + 0.5;

  @override
  bool get alwaysNeedsCompositing => _fade && child != null;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(
      BoxConstraints(
        minWidth: constraints.minWidth,
        maxWidth: constraints.maxWidth,
      ),
      parentUsesSize: true,
    );
    size = constraints.constrain(
      Size(child.size.width, math.min(child.size.height, _maxHeight)),
    );
  }

  @override
  double computeMaxIntrinsicHeight(double width) =>
      math.min(super.computeMaxIntrinsicHeight(width), _maxHeight);

  @override
  double computeMinIntrinsicHeight(double width) =>
      math.min(super.computeMinIntrinsicHeight(width), _maxHeight);

  final LayerHandle<ClipRectLayer> _clip = LayerHandle<ClipRectLayer>();
  final LayerHandle<ShaderMaskLayer> _mask = LayerHandle<ShaderMaskLayer>();

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (!overflowing) {
      _clip.layer = null;
      _mask.layer = null;
      context.paintChild(child, offset);
      return;
    }
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      (context, offset) {
        if (!_fade) {
          _mask.layer = null;
          context.paintChild(child, offset);
          return;
        }
        final rect = Offset.zero & size;
        final start = size.height <= 0
            ? 0.0
            : math.max(0, 1 - _fadeHeight / size.height).toDouble();
        final layer = (_mask.layer ??= ShaderMaskLayer())
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [
              Color(0xFFFFFFFF),
              Color(0xFFFFFFFF),
              Color(0x00FFFFFF),
            ],
            stops: [0, start, 1],
          ).createShader(rect)
          ..maskRect = offset & size
          ..blendMode = BlendMode.dstIn;
        context.pushLayer(
          layer,
          (context, offset) => context.paintChild(child, offset),
          offset,
        );
      },
      oldLayer: _clip.layer,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      size.contains(position) &&
      super.hitTestChildren(result, position: position);

  @override
  void dispose() {
    _clip.layer = null;
    _mask.layer = null;
    super.dispose();
  }
}
