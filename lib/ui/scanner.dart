import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../data/android.dart';
import '../data/catalog.dart';
import '../data/frame.dart';
import '../data/language.dart';
import '../data/pictures.dart';
import '../model.dart';
import '../scan_cubit.dart';
import '../scan_decision.dart';
import 'batch_settings.dart';
import 'scan_frame.dart';
import 'scan_reviews.dart';
import 'sheets.dart';
import 'scan_strip.dart';
import 'style.dart';

class Scanner extends StatefulWidget {
  const Scanner({super.key});
  @override
  State<Scanner> createState() => _ScannerState();
}

class _ScannerState extends State<Scanner> with WidgetsBindingObserver {
  final scan = ScanCubit();
  final clock = Stopwatch()..start();
  CameraController? camera;
  String? error;
  bool reading = false, modal = false, torch = false, writing = false;
  int epoch = 0, nextFrame = 0, frameSession = 0;
  Future<void> cameraQueue = Future.value();
  AppModel get library => context.read<AppModel>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_restoreGuide());
    openCamera(true);
  }

  Future<void> _restoreGuide() async {
    final visible = await AndroidActions.scannerGuide();
    if (mounted && visible != null) scan.setGuide(visible);
  }

  void _toggleGuide() {
    final visible = !scan.state.showGuide;
    scan.setGuide(visible);
    unawaited(AndroidActions.scannerGuide(visible));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) openCamera(false);
    if (state == AppLifecycleState.resumed) openCamera(true);
  }

  void openCamera(bool open) {
    final token = ++epoch;
    frameSession++;
    scan.cancelFrame();
    cameraQueue = cameraQueue.then((_) => _open(open, token)).catchError((
      Object e,
    ) {
      if (mounted && token == epoch) {
        setState(() => error = 'Камера недоступна');
      }
    });
  }

  Future<void> _open(bool open, int token) async {
    final old = camera;
    camera = null;
    torch = false;
    if (mounted) setState(() {});
    await old?.dispose();
    if (!open || !mounted || token != epoch) return;
    await _connect(token);
  }

  Future<void> _connect(int token) async {
    final cameras = await availableCameras();
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final next = CameraController(
      back,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    try {
      await next.initialize();
      if (!mounted || token != epoch) {
        await next.dispose();
        return;
      }
      setState(() {
        camera = next;
        error = null;
      });
      await _syncStream();
    } on CameraException catch (e) {
      if (identical(camera, next)) camera = null;
      await next.dispose();
      if (mounted && token == epoch) {
        setState(
          () => error = e.code.contains('Access')
              ? 'Разрешите доступ к камере'
              : 'Камера недоступна',
        );
      }
    }
  }

  Future<void> _syncStream() async {
    final c = camera;
    if (c == null) return;
    final auto = scan.state.mode == ScanMode.automatic;
    if (auto == c.value.isStreamingImages) return;
    if (auto) {
      await c.startImageStream(_onFrame);
    } else {
      await c.stopImageStream();
    }
  }

  void _mode() {
    frameSession++;
    scan.toggle();
    cameraQueue = cameraQueue.then((_) => _syncStream()).catchError((Object e) {
      if (!mounted) return;
      if (scan.state.mode == ScanMode.automatic) scan.toggle();
      message('Не удалось включить поток камеры');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    openCamera(false);
    unawaited(scan.close());
    super.dispose();
  }

  void message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(value)));
    }
  }

  bool get active => mounted && ModalRoute.of(context)?.isCurrent == true;
  bool accepts(int token) =>
      active &&
      token == frameSession &&
      !modal &&
      scan.state.mode == ScanMode.automatic;
  int rotation(CameraController c) {
    final turns = switch (c.value.deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };
    final sensor = c.description.sensorOrientation;
    return (sensor +
            (c.description.lensDirection == CameraLensDirection.front
                ? turns
                : -turns) +
            360) %
        360;
  }

  void _onFrame(CameraImage image) {
    if (reading ||
        !accepts(frameSession) ||
        clock.elapsedMilliseconds < nextFrame) {
      return;
    }
    final c = camera;
    if (c == null || image.planes.length != 1) return;
    // Передаём весь кадр. Рамка служит визуальной подсказкой.
    final frame = (
      bytes: image.planes.single.bytes,
      width: image.width,
      height: image.height,
      rotation: rotation(c),
    );
    unawaited(_automatic(frame, frameSession));
  }

  Future<void> _automatic(PreviewFrame frame, int token) async {
    reading = true;
    try {
      final matches = await library.recognizeFrame(frame);
      if (!accepts(token)) return;
      final hit = scan.evaluate(matches);
      if (hit == null) return;
      await _store(matches, frame: frame, accept: () => accepts(token));
    } catch (e) {
      if (accepts(token)) {
        _mode();
        message('Автоскан остановлен. Попробуйте ещё раз.');
      }
    } finally {
      nextFrame = clock.elapsedMilliseconds + 220;
      reading = false;
    }
  }

  Future<void> _save(Edition card, List<Match> matches) async {
    setState(() => writing = true);
    try {
      final seq = await library.save(card);
      if (!mounted) return;
      scan.recorded(seq, card, matches);
      await AndroidActions.chime();
    } finally {
      if (mounted) setState(() => writing = false);
    }
  }

  Future<void> _recognize(XFile file) async {
    final matches = await library.recognize(file.path);
    if (!active) return;
    if (matches.isEmpty) {
      message('Карта не найдена');
      return;
    }
    await _store(matches, file: file.path, accept: () => active);
  }

  Future<void> _store(
    List<Match> matches, {
    String? file,
    PreviewFrame? frame,
    required bool Function() accept,
  }) async {
    final hit = matches.first;
    final evidence = await CardLanguage.readOptions(
      corners: hit.corners,
      file: file,
      frame: frame,
      options: hit.editions,
    );
    if (!accept()) return;
    final card = selectScannedEdition(evidence, scan.state.batch);
    try {
      final photo = await AndroidActions.scanPhoto(
        file: file,
        frame: frame,
        corners: hit.corners,
      );
      if (photo != null && accept()) {
        await Pictures.shared.saveScan(card.id, photo);
      }
    } on Exception {
      // Издание можно сохранить даже при недоступном кэше фотографий.
    }
    if (accept()) await _save(card, matches);
  }

  Future<void> _discard(XFile? file) async {
    if (file == null) return;
    try {
      await File(file.path).delete();
    } on FileSystemException {
      /* Временный файл уже удалён. */
    }
  }

  Future<void> _manual({bool gallery = false}) async {
    if (modal || writing) return;
    if (!gallery && scan.state.mode == ScanMode.automatic) {
      scan.shutter();
      nextFrame = 0;
      return;
    }
    frameSession++;
    setState(() => modal = true);
    XFile? file;
    try {
      file = gallery
          ? await ImagePicker().pickImage(
              source: ImageSource.gallery,
              maxWidth: 2000,
              maxHeight: 2000,
            )
          : await camera?.takePicture();
      if (file == null || !active) return;
      await _recognize(file);
    } catch (e) {
      message('Не удалось обработать снимок');
    } finally {
      if (!gallery) await _discard(file);
      if (mounted) setState(() => modal = false);
    }
  }

  Future<void> _edit(ScanEntry entry) => _paused(() async {
    if (library.state.reviews.containsKey(entry.sequence)) {
      await chooseReview(context, library, entry.sequence);
      return;
    }
    final variants = await library.catalog!.variants(entry.card);
    if (!mounted || !active || variants.isEmpty) return;
    final edition = await panel<Edition>(
      context,
      ResultSheet([Match(variants)], entry.card, action: 'Сохранить'),
    );
    if (edition != null && active) await library.replace(entry, edition);
  });

  Future<void> _paused(Future<void> Function() action) async {
    if (modal || writing) return;
    frameSession++;
    scan.cancelFrame();
    setState(() => modal = true);
    try {
      await action();
    } catch (_) {
      message('Не удалось выполнить действие. Попробуйте ещё раз.');
    } finally {
      if (mounted) setState(() => modal = false);
    }
  }

  Future<void> _settings() => _paused(() async {
    final catalog = library.catalog;
    if (catalog == null) return;
    final batch = await panel<BatchSettings>(
      context,
      BatchSheet(catalog, scan.state.batch),
    );
    if (batch != null && mounted) scan.configure(batch);
  });

  Future<void> _undo(int seq) => _paused(() async {
    await library.discardScan(seq);
    if (mounted) scan.undone();
  });

  Future<void> _torch() async {
    final c = camera;
    if (c == null) return;
    try {
      await c.setFlashMode(torch ? FlashMode.off : FlashMode.torch);
      if (mounted && identical(c, camera)) setState(() => torch = !torch);
    } catch (_) {
      message('Фонарь недоступен');
    }
  }

  Widget _header(String title) => Row(
    children: [
      RoundAction(
        Icons.arrow_back,
        'К коллекции',
        () => Navigator.maybePop(context),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: paper,
                fontFamily: headingFont,
                fontWeight: FontWeight.w900,
                fontSize: 21,
              ),
            ),
            if (scan.state.batch.active)
              Text(
                scan.state.batch.label,
                style: const TextStyle(
                  color: butter,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
      ),
      Frost(
        child: PopupMenuButton<String>(
          tooltip: 'Меню сканера',
          enabled: !modal && !writing,
          icon: Icon(
            Icons.tune,
            color: scan.state.batch.active ? butter : paper,
          ),
          onSelected: (action) {
            switch (action) {
              case 'batch':
                _settings();
              case 'guide':
                _toggleGuide();
              case 'torch':
                _torch();
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'guide',
              child: Text(
                scan.state.showGuide
                    ? 'Скрыть рамку и стекло'
                    : 'Показать рамку и стекло',
              ),
            ),
            PopupMenuItem(
              value: 'batch',
              enabled: library.catalog != null,
              child: const Text('Настройки стопки'),
            ),
            PopupMenuItem(
              value: 'torch',
              enabled: camera != null,
              child: Text(torch ? 'Выключить фонарь' : 'Включить фонарь'),
            ),
          ],
        ),
      ),
    ],
  );
  Widget _controls(BuildContext context, ScanMode mode) => Frost(
    radius: 28,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _DockAction(
            Icons.photo_library_outlined,
            'Из фото',
            modal ? null : () => _manual(gallery: true),
          ),
          IconButton.filled(
            tooltip: 'Добавить карту',
            style: IconButton.styleFrom(
              backgroundColor: butter,
              foregroundColor: ink,
              fixedSize: const Size.square(60),
            ),
            onPressed: camera == null || modal ? null : () => _manual(),
            icon: modal
                ? const CircularProgressIndicator()
                : const Icon(Icons.center_focus_strong_rounded, size: 31),
          ),
          Semantics(
            toggled: mode == ScanMode.automatic,
            child: _DockAction(
              mode == ScanMode.automatic
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_outline,
              mode == ScanMode.automatic ? 'Остановить' : 'Автоскан',
              camera == null || modal ? null : _mode,
            ),
          ),
        ],
      ),
    ),
  );
  Widget _overlay(BuildContext context, BoxConstraints bounds) {
    final state = library.state;
    final insets = MediaQuery.paddingOf(context);
    final stripTop = insets.top + 70;
    final strip = math.min(84.0, bounds.maxHeight * .12);
    final sequence = scan.state.lastScan;
    final last = sequence == null
        ? null
        : state.recent.where((e) => e.sequence == sequence).firstOrNull;
    final top = stripTop + strip + 8;
    final bottom =
        bounds.maxHeight -
        insets.bottom -
        104 -
        (last == null ? 0 : 36) -
        (state.reviews.isEmpty ? 0 : 48);
    final width = math.min(
      bounds.maxWidth * .77,
      math.max(20.0, (bottom - top) * ScanFrame.aspectRatio),
    );
    final rect = Rect.fromCenter(
      center: Offset(bounds.maxWidth / 2, (top + bottom) / 2),
      width: width,
      height: width / ScanFrame.aspectRatio,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        if (scan.state.showGuide)
          ScanFrame(window: rect, hasPreview: camera != null),
        Positioned(
          left: 10,
          right: 10,
          top: insets.top + 4,
          child: _header(state.title),
        ),
        Positioned(
          top: stripTop,
          height: strip,
          left: 0,
          right: 0,
          child: Row(
            children: [
              Expanded(
                child: ScanStrip(
                  state.recent,
                  _edit,
                  pending: state.reviews.keys.toSet(),
                ),
              ),
              if (last != null)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: RoundAction(
                    Icons.undo_rounded,
                    'Отменить последнее добавление',
                    modal || writing ? null : () => _undo(last.sequence),
                  ),
                ),
            ],
          ),
        ),
        if (camera == null)
          Center(
            child: TextButton(
              onPressed: () => openCamera(true),
              child: Text(
                error ?? 'Открытие камеры…',
                style: const TextStyle(color: paper),
              ),
            ),
          ),
        Positioned(
          left: 12,
          right: 12,
          bottom: insets.bottom + 8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (last != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Frost(
                    radius: 12,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      child: Text(
                        'В коллекциях: ${state.owned(last.card.name)} · ${last.card.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: paper),
                      ),
                    ),
                  ),
                ),
              if (state.reviews.isNotEmpty)
                ReviewButton(
                  state.reviews.length,
                  modal || writing
                      ? null
                      : () => _paused(() => openReviews(context, library)),
                ),
              _controls(context, scan.state.mode),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<AppModel, LibraryState>(
    builder: (context, state) => Scaffold(
      backgroundColor: dark,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (camera case final c?) _CameraSurface(c),
          BlocBuilder<ScanCubit, ScanSession>(
            bloc: scan,
            builder: (_, _) => LayoutBuilder(builder: _overlay),
          ),
        ],
      ),
    ),
  );
}

class _CameraSurface extends StatelessWidget {
  const _CameraSurface(this.controller);
  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
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
