import 'package:material_ui/material_ui.dart';

import '../data/backup.dart';
import '../model.dart';
import 'library_style.dart';
import 'style.dart';

class BackupPanel extends StatefulWidget {
  const BackupPanel(this.model, {super.key});
  final AppModel model;

  @override
  State<BackupPanel> createState() => _BackupPanelState();
}

class _BackupPanelState extends State<BackupPanel> {
  LibraryBackup? preview;
  bool busy = false;
  String? message;

  Future<void> _run(Future<void> Function() action, String failure) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
    } on FormatException catch (error) {
      message = error.message;
    } catch (_) {
      message = failure;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _save() => _run(() async {
    if (await widget.model.saveBackup()) message = 'Копия сохранена';
  }, 'Не удалось сохранить копию. Проверьте место на диске и повторите.');

  Future<void> _open() => _run(() async {
    preview = await widget.model.openBackup();
  }, 'Не удалось прочитать файл. Выберите его ещё раз.');

  Future<void> _restore(LibraryBackup backup) => _run(() async {
    await widget.model.restoreBackup(backup);
    preview = null;
    message = 'Коллекции восстановлены';
  }, 'Не удалось восстановить коллекции');

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeading(
          preview == null ? 'Резервная копия' : 'Восстановить коллекции?',
        ),
        const SizedBox(height: 12),
        if (preview case final backup?) ...[
          LibraryGlass(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Коллекций: ${backup.folders.length}  ·  Карт: ${backup.copies}  ·  На проверке: ${backup.pending}',
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text('Текущие коллекции будут заменены данными из файла.'),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: busy ? null : () => _restore(backup),
            child: const Text('Заменить коллекции'),
          ),
          TextButton(
            onPressed: busy ? null : () => setState(() => preview = null),
            child: const Text('Отмена'),
          ),
        ] else ...[
          LibraryGlass(
            radius: 16,
            child: ListTile(
              leading: const Icon(Icons.save_alt_rounded),
              title: const Text('Сохранить в файл'),
              subtitle: const Text('Все коллекции и карты на проверке'),
              onTap: busy ? null : _save,
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
          const SizedBox(height: 8),
          LibraryGlass(
            radius: 16,
            child: ListTile(
              leading: const Icon(Icons.restore_rounded),
              title: const Text('Восстановить из файла'),
              onTap: busy ? null : _open,
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
        ],
        if (busy || message != null) const SizedBox(height: 12),
        if (busy) const LinearProgressIndicator(),
        if (message case final text?)
          Semantics(liveRegion: true, child: Text(text)),
      ],
    ),
  );
}
