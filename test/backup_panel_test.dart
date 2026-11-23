import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoved/data/backup.dart';
import 'package:kartoved/data/catalog.dart';
import 'package:kartoved/model.dart';
import 'package:kartoved/ui/backup_panel.dart';

class _TestModel extends AppModel {
  _TestModel() : super(CatalogStore(), History());
  LibraryBackup? file;
  int restores = 0;
  @override
  Future<LibraryBackup?> openBackup() async => file;
  @override
  Future<void> restoreBackup(LibraryBackup backup) async => restores++;
  @override
  Future<bool> saveBackup() async => false;
}

void main() {
  testWidgets('Отмена выбора или предпросмотра сохраняет коллекции', (
    tester,
  ) async {
    final model = _TestModel();
    addTearDown(model.close);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: BackupPanel(model))),
    );
    Future<void> tap(String label) async {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    await tap('Сохранить в файл');
    expect(find.text('Копия сохранена'), findsNothing);
    await tap('Восстановить из файла');
    expect(find.text('Заменить коллекции'), findsNothing);
    model.file = LibraryBackup.fromJson({
      'format': 'kartoved',
      'version': 1,
      'folders': [
        {'folder': 1, 'title': 'Альбом'},
      ],
      'scans': [],
    });
    await tap('Восстановить из файла');
    expect(find.textContaining('Коллекций: 1'), findsOneWidget);
    await tap('Отмена');
    expect(model.restores, 0);
    await tap('Восстановить из файла');
    await tap('Заменить коллекции');
    expect(model.restores, 1);
    expect(find.text('Коллекции восстановлены'), findsOneWidget);
  });
}
