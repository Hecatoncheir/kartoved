import 'package:flutter_test/flutter_test.dart';
import 'package:kartoved/data/scan_progress.dart';
import 'package:kartoved/scan_cubit.dart';
import 'package:kartoved/ui/auto_scan_controls.dart';
import 'package:kartoved/ui/scan_frame.dart';
import 'package:kartoved/ui/scan_outline.dart';
import 'package:kartoved/ui/scan_mesh.dart';
import 'package:kartoved/ui/tracked_scan_guide.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('Стрелка меняет профиль независимо от запуска и паузы', (
    tester,
  ) async {
    var profile = ScanMode.tray;
    var running = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => AutoScanButton(
              profile: profile,
              running: running,
              onToggle: () => update(() => running = !running),
              onChoose: () async {
                final choice = await showModalBottomSheet<ScanMode>(
                  context: context,
                  builder: (_) => AutoScanModeSheet(profile),
                );
                if (choice != null) update(() => profile = choice);
              },
            ),
          ),
        ),
      ),
    );
    final choose = find.byTooltip('Выбрать режим автоскана');
    expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
    await tester.tap(choose);
    await tester.pumpAndSettle();
    expect(running, isFalse);
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.tap(find.text('Обычный автоскан'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.center_focus_weak_rounded), findsOneWidget);
    await tester.tap(find.text('Автоскан'));
    await tester.pumpAndSettle();
    expect(running, isTrue);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    await tester.longPress(find.text('Автоскан'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Автоскан в лотке'));
    await tester.pumpAndSettle();
    expect(running, isTrue);
    expect(profile, ScanMode.tray);
  });

  testWidgets('Проекция учитывает обрезку видео, стекло повторяет контур', (
    tester,
  ) async {
    final contour = ScanOutline.fromCamera([
      .75,
      .7,
      .65,
      .3,
      .25,
      .3,
      .35,
      .7,
    ], mirror: true)!;
    const viewport = Size(200, 400);
    final points = contour.project(const Size(400, 400), viewport);
    expect(points, [
      const Offset(40, 120),
      const Offset(200, 120),
      const Offset(160, 280),
      const Offset(0, 280),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: ScanFrame(
          window: const Rect.fromLTWH(10, 10, 60, 80),
          hasPreview: true,
          outline: points,
        ),
      ),
    );
    final path = tester
        .widget<ClipPath>(find.byType(ClipPath))
        .clipper!
        .getClip(viewport);
    expect(path.contains(const Offset(100, 200)), isFalse);
    expect(path.contains(const Offset(20, 140)), isTrue);
    expect(path.contains(const Offset(20, 265)), isFalse);
  });

  testWidgets('Сетка затухает после распознавания и перестаёт обновляться', (
    tester,
  ) async {
    Widget effect(bool reading) => MaterialApp(
      home: ScanMesh(
        outline: const [
          Offset(40, 30),
          Offset(210, 40),
          Offset(200, 300),
          Offset(40, 280),
        ],
        reading: reading,
      ),
    );
    await tester.pumpWidget(effect(true));
    await tester.pump(const Duration(milliseconds: 200));
    final effectOpacity = find.descendant(
      of: find.byType(ScanMesh),
      matching: find.byType(FadeTransition),
    );
    expect(tester.widget<FadeTransition>(effectOpacity).opacity.value, 1);
    await tester.pumpWidget(effect(false));
    await tester.pump(const Duration(milliseconds: 180));
    final opacity = find.descendant(
      of: find.byType(ScanMesh),
      matching: find.byType(FadeTransition),
    );
    expect(
      tester.widget<FadeTransition>(opacity).opacity.value,
      closeTo(.53, .04),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<FadeTransition>(opacity).opacity.value, 0);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('Рамка проходит промежуточное положение при движении карты', (
    tester,
  ) async {
    const before = [
      Offset(40, 30),
      Offset(210, 40),
      Offset(200, 300),
      Offset(40, 280),
    ];
    final after = before.map((point) => point + const Offset(90, 0)).toList();
    Widget guide(List<Offset> outline) => MaterialApp(
      home: TrackedScanGuide(
        viewport: const Size(800, 600),
        window: const Rect.fromLTWH(40, 30, 160, 250),
        outline: outline,
        showGuide: true,
        hasPreview: true,
        reading: false,
      ),
    );
    await tester.pumpWidget(guide(before));
    await tester.pumpWidget(guide(after));
    await tester.pump(const Duration(milliseconds: 65));
    final frame = find.byType(ScanFrame);
    expect(
      tester.widget<ScanFrame>(frame).outline!.first.dx,
      inExclusiveRange(40, 130),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<ScanFrame>(frame).outline, after);
  });

  testWidgets('Фокус и сетка вместе переходят от названия к нижней строке', (
    tester,
  ) async {
    const viewport = Size(800, 600);
    const card = [.2, .1, .7, .15, .65, .85, .25, .8];
    List<Offset> project(List<double> corners) => ScanOutline.fromCamera(
      corners,
      mirror: false,
    )!.project(viewport, viewport);
    final outline = project(card);
    final title = project(ScanStage.title.focus(card));
    final footer = project(ScanStage.footer.focus(card));
    Widget guide(List<Offset>? focus, {bool reading = true}) => MaterialApp(
      home: TrackedScanGuide(
        viewport: viewport,
        window: const Rect.fromLTWH(40, 30, 160, 250),
        outline: outline,
        focus: focus,
        showGuide: true,
        hasPreview: true,
        reading: reading,
      ),
    );
    ScanFrame frame() => tester.widget<ScanFrame>(find.byType(ScanFrame));
    List<Offset> meshCorners() =>
        tester.widget<ScanMesh>(find.byType(ScanMesh)).outline;

    await tester.pumpWidget(guide(null));
    await tester.pumpWidget(guide(title));
    await tester.pump(const Duration(milliseconds: 80));
    expect(frame().outline, outline);
    expect(
      frame().focus!.first.dy,
      inExclusiveRange(outline.first.dy, title.first.dy),
    );
    expect(meshCorners(), frame().focus);
    await tester.pump(const Duration(milliseconds: 100));
    expect(frame().focus, title);

    await tester.pumpWidget(guide(footer));
    await tester.pump(const Duration(milliseconds: 80));
    expect(
      frame().focus!.first.dy,
      inExclusiveRange(title.first.dy, footer.first.dy),
    );
    expect(meshCorners(), frame().focus);
    await tester.pump(const Duration(milliseconds: 100));
    expect(frame().focus, footer);

    await tester.pumpWidget(guide(null, reading: false));
    await tester.pumpAndSettle();
    expect(frame().focus, outline);
    expect(meshCorners(), outline);
  });
}
