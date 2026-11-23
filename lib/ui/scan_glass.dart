import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

class ScanGlass extends StatefulWidget {
  const ScanGlass({super.key, required this.child});
  final Widget child;

  @override
  State<ScanGlass> createState() => _ScanGlassState();
}

class _ScanGlassState extends State<ScanGlass> {
  ui.FragmentShader? shader;

  @override
  void initState() {
    super.initState();
    if (ui.ImageFilter.isShaderFilterSupported) _load();
  }

  Future<void> _load() async {
    try {
      final loaded = await ui.FragmentProgram.fromAsset(
        'shaders/scan_glass.frag',
      );
      if (mounted) setState(() => shader = loaded.fragmentShader());
    } catch (error) {
      debugPrint('Не удалось загрузить шейдер стекла: $error');
    }
  }

  @override
  void dispose() {
    shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lens = shader;
    return BackdropFilter(
      filterConfig: lens == null
          ? const ImageFilterConfig.blur(sigmaX: 6, sigmaY: 6)
          : _Lens(lens, MediaQuery.devicePixelRatioOf(context), () {
              final box = context.findRenderObject()! as RenderBox;
              return box.localToGlobal(box.size.center(Offset.zero));
            }),
      child: widget.child,
    );
  }
}

class _Lens implements ImageFilterConfig {
  const _Lens(this.shader, this.density, this.center);
  final ui.FragmentShader shader;
  final double density;
  final Offset Function() center;

  @override
  ui.ImageFilter resolve(ImageFilterContext context) {
    // Движок передаёт текстуру фона в физических координатах экрана.
    final point = center();
    shader
      ..setFloat(2, density)
      ..setFloat(3, point.dx)
      ..setFloat(4, point.dy)
      ..setFloat(5, context.bounds.width / 2)
      ..setFloat(6, context.bounds.height / 2);
    return ui.ImageFilter.shader(shader, filterQuality: ui.FilterQuality.low);
  }

  @override
  ui.ImageFilter? get filter => null;
  @override
  String get debugShortDescription => 'Стеклянная кромка';
}
