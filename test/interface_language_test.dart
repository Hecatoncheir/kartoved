import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoved/data/catalog.dart';
import 'package:kartoved/l10n/interface_language.dart';
import 'package:kartoved/main.dart';
import 'package:kartoved/model.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('Язык меняется сразу и сохраняется после запуска', (
    tester,
  ) async {
    const channel = MethodChannel('kartoved/android');
    final messenger = tester.binding.defaultBinaryMessenger;
    String? savedCode;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'interfaceLanguage');
      if (call.arguments case final String code) savedCode = code;
      return savedCode;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    final model = AppModel(
      CatalogStore(),
      History(),
      initial: const LibraryState(
        groups: [(id: 1, name: 'На обмен', count: 3)],
        error: LibraryLoadError.catalog,
      ),
    );
    addTearDown(model.close);

    Future<void> openApp() async {
      final language = await InterfaceLanguageCubit.load();
      await tester.pumpWidget(KartovedApp(model: model, language: language));
      await tester.pumpAndSettle();
    }

    Future<void> choose(String name) async {
      await tester.tap(
        find.ancestor(
          of: find.text(name),
          matching: find.byType(CheckedPopupMenuItem<InterfaceLanguage>),
        ),
      );
      await tester.pumpAndSettle();
    }

    await openApp();
    expect(find.text('Библиотека'), findsOneWidget);
    expect(find.text('1 альбом · 3 карты'), findsOneWidget);
    await tester.tap(find.byTooltip('Язык интерфейса'));
    await tester.pumpAndSettle();
    final choices = find.byType(CheckedPopupMenuItem<InterfaceLanguage>);
    expect(
      tester
          .widgetList<CheckedPopupMenuItem<InterfaceLanguage>>(choices)
          .map((item) => item.value),
      InterfaceLanguage.values,
    );
    await choose('简体中文');
    expect(savedCode, 'zh');
    expect(find.text('收藏库'), findsOneWidget);
    expect(find.text('1 本相册 · 3 张卡牌'), findsOneWidget);
    expect(find.text('На обмен'), findsOneWidget);
    await tester.tap(find.byTooltip('备份'));
    await tester.pumpAndSettle();
    expect(find.text('保存到文件'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('界面语言'));
    await tester.pumpAndSettle();
    await choose('English');
    expect(savedCode, 'en');
    expect(find.text('Library'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await openApp();
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('1 album · 3 cards'), findsOneWidget);
    expect(find.text('На обмен'), findsOneWidget);

    await tester.tap(find.byTooltip('Interface language'));
    await tester.pumpAndSettle();
    await choose('Русский');
    expect(savedCode, 'ru');
    expect(find.text('Библиотека'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
