import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:camera_view_mask/mask/camera_mask_base_with_backdrop_filter.dart';
import 'package:camera_view_mask/mask/mask.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import '../model.dart';
import 'sheets.dart';
import 'style.dart';

class Scanner extends StatefulWidget {
  const Scanner(this.model, {super.key});
  final AppModel model;
  @override
  State<Scanner> createState() => _ScannerState();
}

class _ScannerState extends State<Scanner> with WidgetsBindingObserver {
  CameraController? camera;
  String? cameraError;
  bool torch = false, taking = false;
  int generation = 0;
  Future<void> cameraQueue = Future.value();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleCamera(true);
  }

  void _scheduleCamera(bool open) {
    final token = ++generation;
    cameraQueue = cameraQueue
        .then((_) async {
          final old = camera;
          camera = null;
          torch = false;
          if (mounted) setState(() {});
          await old?.dispose();
          if (!open || token != generation || !mounted) return;
          CameraController? next;
          try {
            final cameras = await availableCameras();
            if (cameras.isEmpty) throw StateError('Камера недоступна');
            final back = cameras.firstWhere(
              (v) => v.lensDirection == CameraLensDirection.back,
              orElse: () => cameras.first,
            );
            next = CameraController(
              back,
              ResolutionPreset.high,
              enableAudio: false,
            );
            await next.initialize();
            if (token != generation || !mounted) {
              await next.dispose();
              return;
            }
            setState(() {
              camera = next;
              cameraError = null;
            });
          } catch (e) {
            await next?.dispose();
            if (mounted && token == generation) {
              setState(
                () => cameraError =
                    e is CameraException && e.code.contains('Access')
                    ? 'Разрешите доступ к камере'
                    : 'Камера недоступна',
              );
            }
          }
        })
        .catchError((Object e) {
          debugPrint('Камера: $e');
        });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.resumed) {
      _scheduleCamera(state == AppLifecycleState.resumed);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    generation++;
    final old = camera;
    camera = null;
    unawaited(old?.dispose());
    super.dispose();
  }

  void note(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> scan({bool gallery = false}) async {
    if (taking || widget.model.busy || widget.model.catalog == null) return;
    setState(() => taking = true);
    XFile? file;
    try {
      file = gallery
          ? await ImagePicker().pickImage(
              source: ImageSource.gallery,
              maxWidth: 1800,
              maxHeight: 1800,
            )
          : await camera?.takePicture();
      if (file == null || !mounted) return;
      final matches = await widget.model.recognize(file.path);
      if (!mounted) return;
      if (matches.isEmpty) {
        note('Карта не найдена. Попробуйте другой ракурс.');
        return;
      }
      final chosen = await panel<Edition>(
        context,
        ResultSheet(matches, file.path),
      );
      if (chosen != null) {
        await widget.model.save(chosen);
        note('В коллекции: ${chosen.name}');
      }
    } catch (e, stack) {
      debugPrint('Сканирование: $e\n$stack');
      note('Не удалось обработать снимок. Попробуйте ещё раз.');
    } finally {
      if (!gallery && file != null) {
        try {
          await File(file.path).delete();
        } on FileSystemException {
          /* Снимок уже удалён. */
        }
      }
      if (mounted) setState(() => taking = false);
    }
  }

  Future<void> toggle() async {
    final controller = camera;
    if (controller == null) return;
    try {
      await controller.setFlashMode(torch ? FlashMode.off : FlashMode.torch);
      if (mounted && identical(controller, camera)) {
        setState(() => torch = !torch);
      }
    } catch (_) {
      note('Фонарь недоступен');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.model,
    builder: (context, _) {
      final model = widget.model;
      final ready = !model.busy && !taking && model.catalog != null;
      return Scaffold(
        backgroundColor: dark,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (camera case final cam?) _CameraSurface(cam),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, box) {
                  final w = math.min(
                    box.maxWidth * .77,
                    math.max(48.0, (box.maxHeight - 210) * .716),
                  );
                  final h = w * 88 / 63;
                  final rect = Rect.fromCenter(
                    center: Offset(box.maxWidth / 2, (box.maxHeight - 60) / 2),
                    width: w,
                    height: h,
                  );
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      if (camera != null)
                        IgnorePointer(
                          child: CameraMaskBaseWithBackdropFilter(
                            key: ValueKey(rect),
                            mask: Mask(
                              offset: rect.topLeft,
                              size: rect.size,
                              borderRadius: 18,
                              border: Border.all(
                                color: paper.withValues(alpha: .55),
                              ),
                            ),
                          ),
                        ),
                      IgnorePointer(
                        child: CustomPaint(painter: _Corners(rect)),
                      ),
                      Positioned(
                        left: 18,
                        right: 18,
                        top: 8,
                        child: Row(
                          children: [
                            const Mark(size: 38),
                            const SizedBox(width: 7),
                            const Text(
                              'Картовед',
                              style: TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 26,
                                letterSpacing: -1.3,
                                fontWeight: FontWeight.w900,
                                color: paper,
                              ),
                            ),
                            const Spacer(),
                            RoundAction(
                              Icons.storage_rounded,
                              'База карт',
                              ready
                                  ? () => panel<void>(
                                      context,
                                      CatalogPanel(model),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                      if (camera == null ||
                          model.initialError != null ||
                          model.catalog == null)
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Mark(size: 64),
                              const SizedBox(height: 12),
                              Text(
                                model.initialError ??
                                    (model.catalog == null
                                        ? 'Подготовка базы…'
                                        : cameraError ?? 'Открытие камеры…'),
                                style: const TextStyle(
                                  color: paper,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (model.initialError != null ||
                                  cameraError != null)
                                TextButton(
                                  onPressed: model.busy
                                      ? null
                                      : () => model.initialError != null
                                            ? model.initialize()
                                            : _scheduleCamera(true),
                                  child: const Text(
                                    'Повторить',
                                    style: TextStyle(color: butter),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (camera != null)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: RoundAction(
                                    torch
                                        ? Icons.flashlight_on
                                        : Icons.flashlight_off,
                                    'Фонарь',
                                    ready ? toggle : null,
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Frost(
                                radius: 32,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                    horizontal: 6,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceAround,
                                    children: [
                                      _DockAction(
                                        Icons.photo_library_outlined,
                                        'Из фото',
                                        ready
                                            ? () => scan(gallery: true)
                                            : null,
                                      ),
                                      Semantics(
                                        button: true,
                                        label: 'Распознать карту',
                                        child: IconButton.filled(
                                          style: IconButton.styleFrom(
                                            backgroundColor: butter,
                                            disabledBackgroundColor: muted,
                                            foregroundColor: ink,
                                            fixedSize: const Size.square(64),
                                          ),
                                          onPressed: ready && camera != null
                                              ? () => scan()
                                              : null,
                                          icon: model.busy || taking
                                              ? const SizedBox.square(
                                                  dimension: 26,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 3,
                                                        color: paper,
                                                      ),
                                                )
                                              : const Icon(
                                                  Icons
                                                      .center_focus_strong_rounded,
                                                  size: 32,
                                                ),
                                        ),
                                      ),
                                      _DockAction(
                                        Icons.style_outlined,
                                        'Коллекция',
                                        ready
                                            ? () => Navigator.push(
                                                context,
                                                MaterialPageRoute<void>(
                                                  builder: (_) =>
                                                      CollectionPage(model),
                                                ),
                                              )
                                            : null,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _CameraSurface extends StatelessWidget {
  const _CameraSurface(this.controller);
  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final size = controller.value.previewSize!;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: landscape ? size.width : size.height,
          height: landscape ? size.height : size.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

class _DockAction extends StatelessWidget {
  const _DockAction(this.icon, this.text, this.tap);
  final IconData icon;
  final String text;
  final VoidCallback? tap;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: tap,
    style: TextButton.styleFrom(
      foregroundColor: paper,
      disabledForegroundColor: const Color(0xffa89984),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 23),
        const SizedBox(height: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _Corners extends CustomPainter {
  const _Corners(this.rect);
  final Rect rect;
  @override
  void paint(Canvas c, Size size) {
    final pen = Paint()
      ..color = butter
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;
    for (var i = 0; i < 4; i++) {
      final corner = [
        rect.topLeft,
        rect.topRight,
        rect.bottomRight,
        rect.bottomLeft,
      ][i];
      c.save();
      c.translate(corner.dx, corner.dy);
      c.rotate(i * math.pi / 2);
      c.drawPath(
        Path()
          ..moveTo(0, 29)
          ..lineTo(0, 16)
          ..quadraticBezierTo(0, 0, 16, 0)
          ..lineTo(29, 0),
        pen,
      );
      c.restore();
    }
  }

  @override
  bool shouldRepaint(_Corners old) => old.rect != rect;
}
