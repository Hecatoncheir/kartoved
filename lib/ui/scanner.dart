import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../data/android.dart';
import '../data/browser.dart';
import '../data/card_reference.dart';
import '../data/catalog.dart';
import '../data/frame.dart';
import '../data/pictures.dart';
import '../data/recognition.dart';
import '../data/tray.dart';
import '../model.dart';
import '../scan_cubit.dart';
import '../scan_decision.dart';
import '../scan_processing.dart';
import 'auto_scan_controls.dart';
import 'batch_settings.dart';
import 'scan_frame.dart';
import 'scan_outline.dart';
import 'scan_reviews.dart';
import 'sheets.dart';
import 'scan_strip.dart';
import 'scan_target.dart';
import 'style.dart';
import 'tracked_scan_guide.dart';

class Scanner extends StatefulWidget {
  const Scanner({super.key});
  @override
  State<Scanner> createState() => _ScannerState();
}

class _ScannerState extends State<Scanner> with WidgetsBindingObserver {
  final scan = ScanCubit();
  final clock = Stopwatch()..start();
  final _pendingSounds = <int, Object>{};
  CameraController? camera;
  Future<XFile>? _webCapture;
  Timer? _webFrames;
  String? error;
  bool reading = false, modal = false, torch = false, writing = false;
  bool _modelSelected = false;
  bool _autoModeChosen = false;
  RecognitionModel? _warmingTray;
  ScanMode _autoMode = ScanMode.tray;
  TrayArea? _trayArea;
  ScanOutline? _outline;
  (ScanStage, ScanOutline)? _focus;
  Size _frameSize = Size.zero;
  int _missingOutlines = 0;
  bool _sweeping = false;
  int epoch = 0, nextFrame = 0, frameSession = 0;
  Future<void> cameraQueue = Future.value();
  AppModel get library => context.read<AppModel>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_restoreGuide());
    unawaited(_restoreModel());
    unawaited(_restoreAutoMode());
    unawaited(warmTitleRecognition());
    openCamera(true);
  }

  Future<void> _restoreGuide() async {
    final visible = await AndroidActions.scannerGuide();
    if (mounted && visible != null && visible != scan.state.showGuide) {
      scan.setGuide(visible);
      _syncCameraStream();
    }
  }

  Future<void> _restoreModel() async {
    final saved = await AndroidActions.scannerModel();
    if (!mounted || _modelSelected || saved == scan.state.model) return;
    frameSession++;
    _sweep(false);
    scan.setModel(saved);
  }

  Future<void> _restoreAutoMode() async {
    final tray = await AndroidActions.scannerTray();
    if (!mounted || _autoModeChosen) return;
    setState(() => _autoMode = tray ? ScanMode.tray : ScanMode.automatic);
  }

  void _toggleGuide() {
    final visible = !scan.state.showGuide;
    if (!scan.state.mode.isAutomatic) {
      frameSession++;
      nextFrame = 0;
      if (!visible) _outline = null;
    }
    if (!visible) _focus = null;
    scan.setGuide(visible);
    unawaited(AndroidActions.scannerGuide(visible));
    _syncCameraStream();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) openCamera(false);
    if (state == AppLifecycleState.resumed) openCamera(true);
  }

  void openCamera(bool open) {
    final token = ++epoch;
    frameSession++;
    _trayArea = null;
    _outline = null;
    _focus = null;
    _missingOutlines = 0;
    _sweeping = false;
    nextFrame = 0;
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
    _webFrames?.cancel();
    _webFrames = null;
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
    final watch = scan.state.mode.isAutomatic || scan.state.showGuide;
    if (kIsWeb) {
      if (watch) {
        _webFrames ??= Timer.periodic(const Duration(milliseconds: 300), (_) {
          unawaited(_webFrame(c));
        });
      } else {
        _webFrames?.cancel();
        _webFrames = null;
      }
      return;
    }
    if (watch == c.value.isStreamingImages) return;
    if (watch) {
      await c.startImageStream(_onFrame);
    } else {
      await c.stopImageStream();
    }
  }

  void _toggleAuto() {
    _autoModeChosen = true;
    _setMode(scan.state.mode.isAutomatic ? ScanMode.manual : _autoMode);
  }

  Future<void> _pickAutoMode() {
    unlockBrowserSound();
    return _paused(() async {
      final selected = await panel<ScanMode>(
        context,
        AutoScanModeSheet(_autoMode),
      );
      if (!mounted || selected == null) return;
      _autoModeChosen = true;
      setState(() => _autoMode = selected);
      if (scan.state.mode.isAutomatic && scan.state.mode != selected) {
        _setMode(selected);
      }
      await AndroidActions.scannerTray(selected == ScanMode.tray);
    });
  }

  void _setMode(ScanMode mode) {
    unlockBrowserSound();
    frameSession++;
    nextFrame = 0;
    _sweep(false);
    if (!mode.isAutomatic && !scan.state.showGuide) _outline = null;
    scan.setMode(mode);
    if (mode == ScanMode.tray) _warmSelectedModel();
    _syncCameraStream();
  }

  void _syncCameraStream() {
    cameraQueue = cameraQueue.then((_) => _syncStream()).catchError((Object e) {
      if (!mounted) return;
      scan.setMode(ScanMode.manual);
      _sweep(false);
      message('Не удалось переключить поток камеры');
    });
  }

  void _warmSelectedModel() {
    final engine = scan.state.model;
    if (_warmingTray != engine) unawaited(_warmTray(engine));
  }

  Future<void> _warmTray(RecognitionModel engine) async {
    setState(() => _warmingTray = engine);
    try {
      await AndroidActions.warmTray(engine)
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      // Следующий кадр повторит загрузку необходимых ресурсов.
    } finally {
      if (mounted && _warmingTray == engine) {
        setState(() => _warmingTray = null);
      }
    }
  }

  void _recalibrateTray() {
    frameSession++;
    scan.cancelFrame();
    _sweep(false);
    setState(() => _trayArea = null);
  }

  @override
  void dispose() {
    _webFrames?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    openCamera(false);
    unawaited(scan.close());
    super.dispose();
  }

  void message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(duration: noticeDuration, content: Text(value)),
        );
    }
  }

  bool get active => mounted && ModalRoute.of(context)?.isCurrent == true;
  bool _acceptsFrame(int token) =>
      active &&
      token == frameSession &&
      !modal &&
      !writing &&
      library.catalog != null &&
      (scan.state.mode.isAutomatic || scan.state.showGuide) &&
      (scan.state.mode != ScanMode.tray || _warmingTray == null);
  bool accepts(int token) =>
      _acceptsFrame(token) && scan.state.mode.isAutomatic;

  bool _readyForFrame(int token) =>
      !reading &&
      clock.elapsedMilliseconds >= nextFrame &&
      _acceptsFrame(token);

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
    if (!_readyForFrame(frameSession)) return;
    final c = camera;
    if (c == null || image.planes.length != 1) return;
    // Передаём весь кадр. Рамка служит визуальной подсказкой.
    final frame = (
      bytes: image.planes.single.bytes,
      width: image.width,
      height: image.height,
      rotation: rotation(c),
    );
    unawaited(_nativeFrame(frame, frameSession));
  }

  Future<XFile> _takePicture(CameraController controller) async {
    final capture = controller.takePicture();
    final photo = await (kIsWeb
        ? capture.timeout(const Duration(seconds: 5))
        : capture);
    if (!kIsWeb ||
        controller.description.lensDirection == CameraLensDirection.back) {
      return photo;
    }
    try {
      return XFile(await browserUnmirror(photo.path));
    } finally {
      releaseBrowserPhoto(photo.path);
    }
  }

  Future<void> _webFrame(CameraController c) async {
    final token = frameSession;
    if (!_readyForFrame(token) || !identical(c, camera)) return;
    reading = true;
    XFile? photo;
    try {
      final capture = _webCapture = _takePicture(c);
      try {
        photo = await capture;
      } finally {
        _webCapture = null;
      }
      if (!_acceptsFrame(token)) return;
      await _inspectFrame(token, file: photo.path);
    } catch (_) {
      _frameFailed(token);
    } finally {
      await _discard(photo);
      _finishFrame(token);
    }
  }

  Future<void> _nativeFrame(PreviewFrame frame, int token) async {
    reading = true;
    try {
      await _inspectFrame(token, frame: frame);
    } catch (_) {
      _frameFailed(token);
    } finally {
      _finishFrame(token);
    }
  }

  void _frameFailed(int token) {
    if (accepts(token)) {
      _setMode(ScanMode.manual);
      message('Автоскан остановлен. Попробуйте ещё раз.');
    } else if (_acceptsFrame(token)) {
      _observeOutline(const [], Size.zero, mirror: false);
    }
  }

  void _finishFrame(int token) {
    reading = false;
    if (token != frameSession) return;
    if (mounted && _focus != null) setState(() => _focus = null);
    final interval = scan.state.mode.isAutomatic ? (kIsWeb ? 0 : 220) : 850;
    nextFrame = clock.elapsedMilliseconds + interval;
  }

  Future<void> _inspectFrame(
    int token, {
    String? file,
    PreviewFrame? frame,
  }) async {
    final c = camera!;
    final size = frame == null
        ? c.value.previewSize!
        : frame.rotation % 180 == 0
        ? Size(frame.width.toDouble(), frame.height.toDouble())
        : Size(frame.height.toDouble(), frame.width.toDouble());
    final mirror = _mirrored(c);
    void showOutline(List<double> points) {
      if (!_acceptsFrame(token)) return;
      _observeOutline(points, size, mirror: mirror);
    }

    if (!scan.state.mode.isAutomatic) {
      showOutline(await library.previewOutline(file: file, frame: frame));
      return;
    }
    final inTray = scan.state.mode == ScanMode.tray;
    final engine = scan.state.model;
    var showStages = scan.gate.awaitingConfirmation;
    void showProgress(ScanStage stage, List<double> corners) {
      if (!accepts(token) || !scan.state.showGuide) return;
      if (stage == ScanStage.card) showOutline(corners);
      if (showStages) _showScanStage(stage, corners, size, mirror: mirror);
    }

    final matches = await library.recognizePreview(
      file: file,
      frame: frame,
      engine: engine,
      tray: inTray ? _trayArea : null,
      deferKeypoints: inTray,
      onOutline: showOutline,
      onProgress: scan.state.showGuide ? showProgress : null,
    );
    if (!accepts(token)) return;
    if (inTray && _trayArea == null) {
      final area = TrayArea.calibrate(matches.firstOrNull?.corners ?? const []);
      if (area == null) {
        scan.cancelFrame();
        _sweep(false);
        return;
      }
      setState(() => _trayArea = area);
    }
    final ready = scan.evaluate(matches) != null;
    _sweep(ready || scan.gate.awaitingConfirmation);
    if (!ready) return;
    showStages = true;
    try {
      await _store(
        matches,
        file: file,
        frame: frame,
        tray: inTray ? _trayArea : null,
        refineTrayMatch: inTray && engine == RecognitionModel.keypoints,
        accept: () => accepts(token),
        onProgress: showProgress,
      );
    } finally {
      if (mounted) _sweep(false);
    }
  }

  void _observeOutline(List<double> points, Size size, {required bool mirror}) {
    final observed = ScanOutline.fromCamera(points, mirror: mirror);
    if (observed == null) {
      if (++_missingOutlines >= 2 && _outline != null) {
        setState(() => _outline = null);
      }
      return;
    }
    _missingOutlines = 0;
    final next = _outline?.follow(observed) ?? observed;
    if (identical(next, _outline) && size == _frameSize) return;
    setState(() {
      _outline = next;
      _frameSize = size;
    });
  }

  void _sweep(bool reading) {
    if (_sweeping == reading && (reading || _focus == null)) return;
    setState(() {
      _sweeping = reading;
      if (!reading) _focus = null;
    });
  }

  bool _mirrored(CameraController camera) => kIsWeb
      ? camera.description.lensDirection != CameraLensDirection.back
      : camera.description.lensDirection == CameraLensDirection.front;

  void _showScanStage(
    ScanStage stage,
    List<double> card,
    Size size, {
    required bool mirror,
  }) {
    final region = ScanOutline.fromCamera(
      stage.focus(card),
      mirror: mirror,
      minTurn: .00001,
    );
    if (region == null) return;
    setState(() {
      _focus = (stage, region);
      _frameSize = size;
    });
  }

  Future<void> _save(
    PreparedScan result, {
    required bool trayScan,
    ScanEntry? previous,
  }) async {
    final (:card, :review) = result.decision;
    setState(() => writing = true);
    try {
      final seq = await scan.save(library, result, previous: previous);
      if (!mounted) return;
      final targetFound = scan.state.targets.contains(card.name);
      final soundOnSave = kIsWeb || trayScan || review != null;
      if (soundOnSave) {
        unawaited(AndroidActions.chime(targetFound: targetFound));
      }
      if (review == null) {
        unawaited(
          _loadScannedCardDetails(
            seq,
            card,
            targetFound,
            announce: !soundOnSave,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => writing = false);
    }
  }

  Future<void> _loadScannedCardDetails(
    int seq,
    Edition card,
    bool targetFound, {
    required bool announce,
  }) async {
    final token = _pendingSounds[seq] = Object();
    try {
      final (_, reference) = await (
        Pictures.shared.official(card.id),
        CardReferences.shared.get(card.id),
      ).wait;
      if (!announce ||
          !mounted ||
          _pendingSounds[seq] != token ||
          !reference.imageAvailable) {
        return;
      }
      final kept = library.state.recent.any(
        (entry) =>
            entry.sequence == seq && entry.card.printingKey == card.printingKey,
      );
      if (kept) await AndroidActions.chime(targetFound: targetFound);
    } catch (_) {
      // Данные Scryfall можно загрузить позже.
    } finally {
      if (_pendingSounds[seq] == token) _pendingSounds.remove(seq);
    }
  }

  ScanProgress? _manualProgress() {
    final c = camera;
    final size = c?.value.previewSize;
    if (c == null || size == null || !scan.state.showGuide) return null;
    final token = frameSession;
    final turned =
        !kIsWeb && MediaQuery.orientationOf(context) == Orientation.portrait;
    final displaySize = turned ? size.flipped : size;
    final mirror = _mirrored(c);
    return (stage, card) {
      if (!active || token != frameSession || !scan.state.showGuide) return;
      if (stage == ScanStage.card) {
        _observeOutline(card, displaySize, mirror: mirror);
        _sweep(true);
      }
      _showScanStage(stage, card, displaySize, mirror: mirror);
    };
  }

  Future<void> _recognize(
    XFile file, {
    required bool live,
    ScanEntry? previous,
  }) async {
    final onProgress = live ? _manualProgress() : null;
    final matches = await library.recognize(
      file.path,
      engine: scan.state.model,
      onProgress: onProgress,
    );
    if (!active) return;
    if (matches.isEmpty) {
      message('Карта не найдена');
      return;
    }
    if (live) _sweep(true);
    await _store(
      matches,
      file: file.path,
      accept: () => active,
      previous: previous,
      onProgress: onProgress,
    );
  }

  Future<void> _store(
    List<Match> detected, {
    String? file,
    PreviewFrame? frame,
    TrayArea? tray,
    bool refineTrayMatch = false,
    required bool Function() accept,
    ScanEntry? previous,
    ScanProgress? onProgress,
  }) async {
    final result = await prepareScan(
      detected,
      library: library,
      batch: scan.state.batch,
      isCurrent: accept,
      rescan: previous != null,
      file: file,
      frame: frame,
      tray: tray,
      refineTrayMatch: refineTrayMatch,
      onProgress: onProgress,
    );
    if (result == null || !accept()) return;
    await _save(result, trayScan: tray != null, previous: previous);
  }

  Future<void> _discard(XFile? file) async {
    if (file == null) return;
    if (kIsWeb) {
      releaseBrowserPhoto(file.path);
      return;
    }
    try {
      await File(file.path).delete();
    } on FileSystemException {
      /* Временный файл уже удалён. */
    }
  }

  Future<XFile?> _capture() async {
    final inFlight = _webCapture;
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (_) {
        // Ошибка предыдущего кадра не мешает сделать новый снимок.
      }
    }
    final c = camera;
    return c == null || !active ? null : _takePicture(c);
  }

  Future<void> _manual({bool gallery = false, ScanEntry? previous}) async {
    if (modal || writing) return;
    unlockBrowserSound();
    if (!gallery && previous == null && scan.state.mode.isAutomatic) {
      scan.shutter();
      nextFrame = 0;
      return;
    }
    frameSession++;
    scan.cancelFrame();
    _sweep(false);
    if (previous != null) _pendingSounds.remove(previous.sequence);
    setState(() => modal = true);
    XFile? file;
    try {
      file = gallery
          ? await ImagePicker().pickImage(
              source: ImageSource.gallery,
              maxWidth: 2000,
              maxHeight: 2000,
            )
          : await _capture();
      if (file == null || !active) return;
      await _recognize(file, live: !gallery, previous: previous);
    } catch (e) {
      message('Не удалось обработать снимок');
    } finally {
      if (!gallery || kIsWeb) await _discard(file);
      if (mounted) {
        _sweep(false);
        setState(() => modal = false);
      }
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
    if (edition != null && active) {
      _pendingSounds.remove(entry.sequence);
      await library.replace(entry, edition);
    }
  });

  Future<void> _paused(Future<void> Function() action) async {
    if (modal || writing) return;
    frameSession++;
    scan.cancelFrame();
    _sweep(false);
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

  Future<void> _pickModel() => _paused(() async {
    final selected = await panel<RecognitionModel>(
      context,
      SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHeading('Модель распознавания'),
            for (final model in RecognitionModel.values)
              ListTile(
                title: Text(model.label),
                subtitle: Text(switch (model) {
                  RecognitionModel.oracle => 'Каталог Картоведа',
                  RecognitionModel.mtgIdentification =>
                    'Уточняет близкие совпадения Oracle по галерее автора',
                  RecognitionModel.keypoints =>
                    'Сверяет варианты Oracle с изображениями Scryfall',
                }),
                selected: scan.state.model == model,
                trailing: scan.state.model == model
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, model),
              ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    _modelSelected = true;
    scan.setModel(selected);
    if (scan.state.mode == ScanMode.tray) _warmSelectedModel();
    await AndroidActions.scannerModel(selected);
  });

  Future<void> _targets() {
    unlockBrowserSound();
    return _paused(() async {
      final catalog = library.catalog;
      if (catalog == null) return;
      final hadTargets = scan.state.targets.isNotEmpty;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => ScanTargetsPage(catalog, scan)),
      );
      if (!mounted || hadTargets || scan.state.targets.isEmpty) return;
      if (scan.state.mode == ScanMode.manual) _toggleAuto();
    });
  }

  Future<void> _undo(int seq) => _paused(() async {
    _pendingSounds.remove(seq);
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

  String? get _targetLabel => switch (scan.state.targets.length) {
    0 => null,
    1 => 'Ищу · ${scan.state.targets.single}',
    final count => 'Ищу · карт: $count',
  };

  String? get _modelLabel {
    final model = switch (scan.state.model) {
      RecognitionModel.oracle => 'Oracle',
      RecognitionModel.mtgIdentification => 'MTG + Oracle',
      RecognitionModel.keypoints => 'Ключевые точки',
    };
    if (scan.state.mode == ScanMode.tray) {
      if (_warmingTray != null) return 'Лоток · загрузка моделей';
      return _trayArea == null
          ? 'Лоток · положите карту ровно'
          : 'Лоток · $model';
    }
    return scan.state.model == RecognitionModel.oracle ? null : model;
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
            if ((scan.state.showGuide && _focus != null) ||
                scan.state.batch.active ||
                scan.state.targets.isNotEmpty ||
                scan.state.model != RecognitionModel.oracle ||
                scan.state.mode == ScanMode.tray)
              Text(
                [
                  ?((scan.state.showGuide ? _focus?.$1.label : null) ??
                      _modelLabel),
                  ?_targetLabel,
                  if (scan.state.batch.active) scan.state.batch.label,
                ].join('  ·  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
              case 'target':
                _targets();
              case 'batch':
                _settings();
              case 'model':
                _pickModel();
              case 'guide':
                _toggleGuide();
              case 'torch':
                _torch();
              case 'calibrateTray':
                _recalibrateTray();
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'model',
              enabled: library.catalog != null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Модель распознавания'),
                  Text(
                    scan.state.model.label,
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'target',
              enabled: library.catalog != null,
              child: const Text('Искомые карты'),
            ),
            if (scan.state.mode == ScanMode.tray && _trayArea != null)
              const PopupMenuItem(
                value: 'calibrateTray',
                child: Text('Откалибровать лоток заново'),
              ),
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
          AutoScanButton(
            profile: _autoMode,
            running: mode.isAutomatic,
            onToggle: camera == null || modal || writing ? null : _toggleAuto,
            onChoose: modal || writing ? null : _pickAutoMode,
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
    final bottom = bounds.maxHeight - insets.bottom - 104;
    // Статус скана и кнопка проверки могут появиться над нижней панелью.
    final frameBottom = bottom - 52 - 48;
    final width = math.min(
      bounds.maxWidth * .77,
      math.max(20.0, (frameBottom - top) * ScanFrame.aspectRatio),
    );
    final height = width / ScanFrame.aspectRatio;
    final rect = Rect.fromCenter(
      center: Offset(
        bounds.maxWidth / 2,
        math.min((top + bottom) / 2, frameBottom - height / 2),
      ),
      width: width,
      height: height,
    );
    final outline = bounds.biggest.isEmpty || _frameSize.isEmpty
        ? null
        : _outline?.project(_frameSize, bounds.biggest);
    final focus = bounds.biggest.isEmpty || _frameSize.isEmpty
        ? null
        : _focus?.$2.project(_frameSize, bounds.biggest);
    return Stack(
      fit: StackFit.expand,
      children: [
        TrackedScanGuide(
          viewport: bounds.biggest,
          window: rect,
          outline: outline,
          focus: focus,
          showGuide: scan.state.showGuide,
          hasPreview: camera != null,
          reading: _sweeping,
        ),
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
                  child: _ScanResult(
                    'В коллекциях: ${state.owned(last.card.name)} · ${last.card.name}',
                    modal || writing || camera == null
                        ? null
                        : () => _manual(previous: last),
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

class _ScanResult extends StatelessWidget {
  const _ScanResult(this.label, this.repeat);

  final String label;
  final VoidCallback? repeat;

  @override
  Widget build(BuildContext context) => Frost(
    radius: 12,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: paper),
            ),
          ),
        ),
        TextButton(onPressed: repeat, child: const Text('Переснять')),
      ],
    ),
  );
}

class _CameraSurface extends StatelessWidget {
  const _CameraSurface(this.controller);
  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    // В браузере видео уже заполняет область через object-fit: cover.
    if (kIsWeb) return controller.buildPreview();
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
