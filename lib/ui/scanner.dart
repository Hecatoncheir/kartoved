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
import '../scan_processing.dart';
import 'auto_scan_controls.dart';
import 'scanner_menu.dart';
import 'scanner_style.dart';
import 'scan_destination.dart';
import 'scan_frame.dart';
import 'scan_outline.dart';
import 'scan_reviews.dart';
import 'sheets.dart';
import 'glass_sheet.dart';
import 'scan_strip.dart';
import 'scan_target.dart';
import 'style.dart';
import 'tracked_scan_guide.dart';

class Scanner extends StatefulWidget {
  const Scanner({super.key, this.rescan});
  final ScanEntry? rescan;
  @override
  State<Scanner> createState() => _ScannerState();
}

class _ScannerState extends State<Scanner> with WidgetsBindingObserver {
  final scan = ScanCubit();
  final clock = Stopwatch()..start();
  CameraController? camera;
  Future<XFile>? _webCapture;
  Timer? _webFrames;
  String? error;
  bool reading = false, modal = false, writing = false;
  bool _modelSelected = false, _guideChosen = false, _settingTorch = false;
  bool _autoModeChosen = false;
  final _changedOptions = <ScanOption>{};
  bool get essentials =>
      widget.rescan == null &&
      !scan.state.batch.active &&
      scan.state.options.contains(ScanOption.essentials);
  RecognitionModel get engine =>
      essentials ? RecognitionModel.oracle : scan.state.model;
  RecognitionModel? _warmingTray;
  ScanMode _autoMode = ScanMode.tray;
  TrayArea? _trayArea;
  final _trayChanges = TrayChangeDetector();
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
    for (final option in ScanOption.values) {
      unawaited(_restoreOption(option));
    }
    unawaited(warmTitleRecognition());
    openCamera(true);
  }

  Future<void> _restoreGuide() async {
    final visible = await AndroidActions.scannerGuide();
    if (mounted &&
        !_guideChosen &&
        visible != null &&
        visible != scan.state.showGuide) {
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

  Future<void> _restoreOption(ScanOption option) async {
    final enabled = await AndroidActions.scannerOption(option.name);
    if (mounted && enabled && !_changedOptions.contains(option)) {
      frameSession++;
      scan.setOption(option, true);
    }
  }

  void _toggleOption(ScanOption option) {
    final enabled = !scan.state.options.contains(option);
    _changedOptions.add(option);
    frameSession++;
    nextFrame = 0;
    _sweep(false);
    scan.setOption(option, enabled);
    unawaited(AndroidActions.scannerOption(option.name, enabled));
  }

  void _toggleGuide() {
    _guideChosen = true;
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
    scan.stopRepeats();
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
    if (mounted && !scan.isClosed) scan.setLight(ScanLight.unavailable);
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
      scan.setLight(ScanLight.off);
      await _syncStream();
    } on CameraException catch (e) {
      if (identical(camera, next)) {
        camera = null;
        scan.setLight(ScanLight.unavailable);
      }
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
      _webFrames?.cancel();
      _webFrames = null;
      if (watch) {
        final interval = scan.state.mode.isAutomatic ? 100 : 300;
        _webFrames = Timer.periodic(Duration(milliseconds: interval), (_) {
          unawaited(_webFrame(c));
        });
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
      final selected = await showGlassSheet<ScanMode>(
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
    if (_warmingTray != engine) unawaited(_warmTray(engine));
  }

  Future<void> _warmTray(RecognitionModel engine) async {
    setState(() => _warmingTray = engine);
    try {
      await AndroidActions.warmTray(
        engine,
        essentials: essentials,
      ).timeout(const Duration(seconds: 30));
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
    scan.stopRepeats();
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
    final interval = switch (scan.state.mode) {
      ScanMode.manual => 850,
      ScanMode.tray => kIsWeb ? 0 : 80,
      ScanMode.automatic => essentials || kIsWeb ? 0 : 220,
    };
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
    final canRepeat = inTray && scan.repeatReady;
    final consecutive =
        inTray && scan.state.options.contains(ScanOption.consecutive);
    Future<Uint8List?> sampleTray(TrayArea area) async => frame == null
        ? browserTraySample(file!, area, details: consecutive)
        : area.sampleFrame(frame, details: consecutive);
    final area = inTray ? _trayArea : null;
    if (area != null) {
      final sample = await sampleTray(area);
      if (!accepts(token)) return;
      if (consecutive) scan.observeTray(sample);
      if (sample != null &&
          !_trayChanges.shouldInspect(
            sample,
            clock.elapsedMilliseconds,
            token,
            force: canRepeat || scan.needsFullFrame,
          )) {
        return;
      }
    }
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
    if (consecutive && matches.isEmpty) scan.observeTray(null);
    if (inTray && _trayArea == null) {
      final area = TrayArea.calibrate(matches.firstOrNull?.corners ?? const []);
      if (area == null) {
        scan.cancelFrame();
        _sweep(false);
        return;
      }
      setState(() => _trayArea = area);
      if (consecutive) {
        final sample = await sampleTray(area);
        if (!accepts(token)) return;
        scan.observeTray(sample);
      }
    }
    final repeat = canRepeat ? scan.repeatFor(matches) : null;
    if (repeat != null && repeat.reuse) {
      await _save((
        decision: (card: repeat.card, review: null),
        matches: matches,
      ), trayScan: true);
      return;
    }
    final ready = repeat != null || scan.evaluate(matches) != null;
    _sweep(ready || scan.gate.awaitingConfirmation);
    if (!ready) return;
    showStages = true;
    try {
      await _store(
        matches,
        file: file,
        frame: frame,
        tray: inTray ? _trayArea : null,
        repeatCheck: !consecutive
            ? null
            : repeat == null
            ? TrayRepeatCheck.firstCopy
            : TrayRepeatCheck.replacement,
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
      final seq = await scan.save(
        library,
        result,
        previous: previous,
        trayScan: trayScan,
      );
      if (!mounted) return;
      final targetFound = scan.state.targets.contains(card.name);
      final sound = review != null
          ? ScanSound.review
          : targetFound
          ? ScanSound.found
          : ScanSound.added;
      unawaited(AndroidActions.chime(sound));
      if (review == null && !essentials) {
        unawaited(_loadScannedCardDetails(card));
      }
      if (widget.rescan != null && active) {
        Navigator.pop(context, '${card.name}\n${_outcome(seq)}');
      }
    } finally {
      if (mounted) setState(() => writing = false);
    }
  }

  String _outcome(int sequence) {
    final review = library.state.reviews[sequence];
    if (review == null) {
      final card = library.state.recent
          .where((entry) => entry.sequence == sequence)
          .firstOrNull
          ?.card;
      final note = card?.needsPrinting == true ? ' · Издание не уточнено' : '';
      return 'Учтено в «${library.state.title}»$note';
    }
    final batch = review.batchLabel;
    return 'На проверке · ${review.reason.label}${batch.isEmpty ? '' : ' ($batch)'}';
  }

  Future<void> _loadScannedCardDetails(Edition card) async {
    try {
      await (
        Pictures.shared.official(card.id),
        CardReferences.shared.get(card.id),
      ).wait;
    } catch (_) {
      // Данные Scryfall можно загрузить позже.
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
      engine: previous == null ? engine : scan.state.model,
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
    TrayRepeatCheck? repeatCheck,
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
      essentials: essentials,
      file: file,
      frame: frame,
      tray: tray,
      repeatCheck: repeatCheck,
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
    previous ??= widget.rescan;
    unlockBrowserSound();
    if (!gallery && previous == null && scan.state.mode.isAutomatic) {
      scan.shutter();
      nextFrame = 0;
      return;
    }
    frameSession++;
    scan.cancelFrame();
    _sweep(false);
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
    scan.stopRepeats();
    if (library.state.reviews.containsKey(entry.sequence)) {
      await chooseReview(context, library, entry.sequence, scanner: true);
      return;
    }
    if (entry.card.needsPrinting) {
      final folder = library.state.folder;
      final card = await choosePrinting(context, library.catalog!, entry.card);
      if (card != null && active && folder == library.state.folder) {
        await library.resolvePrinting(
          folder,
          entry.card,
          card,
          sequence: entry.sequence,
        );
      }
      return;
    }
    final variants = await library.catalog!.variants(entry.card);
    if (!mounted || !active || variants.isEmpty) return;
    final edition = await showGlassSheet<Edition>(
      context,
      ResultSheet([Match(variants)], entry.card, action: 'Сохранить'),
    );
    if (edition != null && active) {
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

  Future<void> _menu() => _paused(() async {
    final action = await showModalBottomSheet<ScannerMenuAction>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x990c1024),
      constraints: const BoxConstraints(maxWidth: 540),
      builder: (_) => ScannerMenu(
        scan: scan,
        catalog: library.catalog,
        rescan: widget.rescan != null,
        calibrated: _trayArea != null,
        toggleOption: _toggleOption,
        toggleGuide: _toggleGuide,
        toggleTorch: _torch,
        selectModel: _selectModel,
      ),
    );
    if (!mounted) return;
    switch (action) {
      case ScannerMenuAction.targets:
        await _targets();
      case ScannerMenuAction.calibrate:
        _recalibrateTray();
      case null:
        break;
    }
  });

  Future<void> _selectModel(RecognitionModel selected) async {
    _modelSelected = true;
    scan.setModel(selected);
    if (scan.state.mode == ScanMode.tray) _warmSelectedModel();
    await AndroidActions.scannerModel(selected);
  }

  Future<void> _targets() async {
    unlockBrowserSound();
    final catalog = library.catalog;
    if (catalog == null) return;
    final hadTargets = scan.state.targets.isNotEmpty;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ScanTargetsPage(catalog, scan)),
    );
    if (!mounted || hadTargets || scan.state.targets.isEmpty) return;
    if (scan.state.mode == ScanMode.manual) _toggleAuto();
  }

  Future<void> _chooseFolder() => _paused(() async {
    final folder = await showGlassSheet<int>(
      context,
      ScanDestination(library.state.groups),
    );
    if (!mounted || folder == null || folder == library.state.folder) return;
    await library.select(folder);
    if (mounted) scan.changedFolder();
  });

  Future<void> _undo(int seq) => _paused(() async {
    await library.discardScan(seq);
    if (mounted) scan.undone();
  });

  Future<void> _torch() async {
    final c = camera;
    if (c == null || _settingTorch) return;
    _settingTorch = true;
    final turnOn = scan.state.light != ScanLight.on;
    try {
      await c.setFlashMode(turnOn ? FlashMode.torch : FlashMode.off);
      if (mounted && identical(c, camera)) {
        scan.setLight(turnOn ? ScanLight.on : ScanLight.off);
      }
    } catch (_) {
      if (mounted && identical(c, camera)) message('Фонарь недоступен');
    } finally {
      _settingTorch = false;
    }
  }

  String? get _targetLabel => switch (scan.state.targets.length) {
    0 => null,
    1 => 'Ищу · ${scan.state.targets.single}',
    final count => 'Ищу · карт: $count',
  };

  String? get _modelLabel {
    final model = essentials
        ? 'Только необходимое'
        : switch (scan.state.model) {
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
    return engine == RecognitionModel.oracle && !essentials ? null : model;
  }

  Widget _header() => Row(
    children: [
      IconButton(
        tooltip: 'К коллекции',
        onPressed: () => Navigator.maybePop(context),
        icon: const Icon(Icons.arrow_back, color: scanPaper),
      ),
      const Mark(size: 26, color: scanPaper),
      const SizedBox(width: 8),
      const Expanded(
        child: Text(
          'Картовед',
          style: TextStyle(
            fontFamily: headingFont,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: scanPaper,
          ),
        ),
      ),
      ScanSurface(
        radius: 14,
        child: IconButton(
          tooltip: 'Меню сканера',
          onPressed: modal || writing ? null : _menu,
          icon: Icon(
            Icons.tune,
            color: scan.state.batch.active ? scanOrange : scanPaper,
          ),
        ),
      ),
    ],
  );

  Widget _controls(BuildContext context, ScanMode mode) => ScanSurface(
    radius: 28,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Wrap(
        alignment: WrapAlignment.spaceAround,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _DockAction(
            Icons.photo_library_outlined,
            'Из фото',
            modal ? null : () => _manual(gallery: true),
          ),
          IconButton.filled(
            tooltip: widget.rescan == null
                ? 'Добавить карту'
                : 'Сделать новый снимок',
            style: IconButton.styleFrom(
              backgroundColor: scanOrange,
              foregroundColor: scanInk,
              fixedSize: const Size.square(60),
            ),
            onPressed: camera == null || modal ? null : () => _manual(),
            icon: modal && _sweeping
                ? const CircularProgressIndicator()
                : const Icon(Icons.center_focus_strong_rounded, size: 31),
          ),
          if (widget.rescan == null)
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
  Widget _history(LibraryState state) {
    final target = widget.rescan;
    final entries = target == null ? state.recent : [target];
    final displayed =
        target ??
        entries.where((e) => e.sequence == scan.state.lastScan).firstOrNull;
    final status = [
      ?((scan.state.showGuide ? _focus?.$1.label : null) ?? _modelLabel),
      ?_targetLabel,
      if (scan.state.batch.active) scan.state.batch.label,
    ].join('  ·  ');
    final choose = target == null && state.groups.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        const Divider(height: 12, color: Color(0x447f91b5)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: choose && !modal && !writing ? _chooseFolder : null,
            style: TextButton.styleFrom(
              foregroundColor: scanPaper,
              disabledForegroundColor: scanPaper,
              backgroundColor: const Color(0x334f6684),
            ),
            icon: const Icon(Icons.collections_bookmark_outlined, size: 18),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(state.title)),
                if (choose) const Icon(Icons.expand_more, size: 18),
              ],
            ),
          ),
        ),
        if (status.isNotEmpty)
          Text(
            status,
            style: const TextStyle(
              color: scanMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        if (entries.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SizedBox(
              height: 108,
              child: Row(
                children: [
                  Expanded(
                    child: ScanStrip(
                      entries,
                      target == null ? _edit : null,
                      pending: {
                        for (final e in entries.take(ScanStrip.limit))
                          if (state.reviews.containsKey(e.sequence)) e.sequence,
                      },
                      rescan: modal || writing
                          ? null
                          : (entry) => _manual(
                              previous: entry,
                              gallery: camera == null,
                            ),
                    ),
                  ),
                  if (scan.state.lastAdded case final undo?)
                    IconButton(
                      tooltip: 'Отменить последнее добавление',
                      onPressed: modal || writing ? null : () => _undo(undo),
                      icon: const Icon(Icons.undo, color: scanPaper),
                    ),
                ],
              ),
            ),
          ),
        if (displayed != null)
          Semantics(
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayed.card.name,
                  style: const TextStyle(
                    fontFamily: headingFont,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    color: scanPaper,
                  ),
                ),
                Text(
                  target != null
                      ? 'Пересъёмка спорной карты'
                      : scan.state.repeatSeconds > 0
                      ? '${_outcome(displayed.sequence)} · Повтор через ${scan.state.repeatSeconds} с'
                      : _outcome(displayed.sequence),
                  style: const TextStyle(color: scanMuted),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _viewfinder(BuildContext context, BoxConstraints bounds) {
    final size = bounds.biggest;
    final width = math.min(
      size.width * .85,
      size.height * .92 * ScanFrame.aspectRatio,
    );
    final window = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: width,
      height: width / ScanFrame.aspectRatio,
    );
    List<Offset>? project(ScanOutline? outline) =>
        _frameSize.isEmpty ? null : outline?.project(_frameSize, size);
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: scanInk),
        if (camera case final c?) _CameraSurface(c),
        TrackedScanGuide(
          viewport: size,
          window: window,
          outline: project(_outline),
          focus: project(_focus?.$2),
          showGuide: scan.state.showGuide,
          hasPreview: camera != null,
          reading: _sweeping,
        ),
        if (camera == null)
          Center(
            child: TextButton(
              onPressed: () => openCamera(true),
              child: Text(
                error ?? 'Открытие камеры…',
                style: const TextStyle(color: scanPaper),
              ),
            ),
          ),
      ],
    );
  }

  Widget _layout(LibraryState state, BoxConstraints bounds) {
    final history = SingleChildScrollView(child: _history(state));
    final viewer = ScanSurface(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: LayoutBuilder(builder: _viewfinder),
        ),
      ),
    );
    final controls = _controls(context, scan.state.mode);
    if (bounds.maxWidth > 600 && bounds.maxHeight < 520) {
      return Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Expanded(child: history),
                controls,
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: viewer),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: bounds.maxHeight * .46),
          child: history,
        ),
        const SizedBox(height: 8),
        Expanded(child: viewer),
        const SizedBox(height: 8),
        controls,
      ],
    );
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<AppModel, LibraryState>(
    builder: (context, state) => AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Theme(
        data: scannerTheme,
        child: Scaffold(
          backgroundColor: scanInk,
          resizeToAvoidBottomInset: false,
          body: DecoratedBox(
            decoration: const BoxDecoration(gradient: scanBackdrop),
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    child: BlocBuilder<ScanCubit, ScanSession>(
                      bloc: scan,
                      builder: (_, _) => LayoutBuilder(
                        builder: (_, bounds) => _layout(state, bounds),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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
      foregroundColor: scanPaper,
      disabledForegroundColor: scanMuted,
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
