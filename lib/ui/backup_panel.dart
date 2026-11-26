import 'package:material_ui/material_ui.dart';

import '../l10n/strings.dart';
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
    } on BackupFormatException catch (error) {
      if (!mounted) return;
      message = switch (error.issue) {
        BackupFormatIssue.damaged => context.strings.invalidBackup,
        BackupFormatIssue.wrongFile => context.strings.wrongBackupFile,
        BackupFormatIssue.unsupportedVersion =>
          context.strings.unsupportedBackup,
      };
    } catch (_) {
      message = failure;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _save() => _run(() async {
    if (await widget.model.saveBackup() && mounted) {
      message = context.strings.backupSaved;
    }
  }, context.strings.backupSaveFailed);

  Future<void> _open() => _run(() async {
    preview = await widget.model.openBackup();
  }, context.strings.backupReadFailed);

  Future<void> _restore(LibraryBackup backup) => _run(() async {
    await widget.model.restoreBackup(backup);
    preview = null;
    if (mounted) message = context.strings.collectionsRestored;
  }, context.strings.backupRestoreFailed);

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeading(
          preview == null
              ? context.strings.backup
              : context.strings.restoreCollectionsQuestion,
        ),
        const SizedBox(height: 12),
        if (preview case final backup?) ...[
          LibraryGlass(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                context.strings.backupSummary(
                  backup.folders.length,
                  backup.copies,
                  backup.pending,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(context.strings.backupReplaceWarning),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: busy ? null : () => _restore(backup),
            child: Text(context.strings.replaceCollections),
          ),
          TextButton(
            onPressed: busy ? null : () => setState(() => preview = null),
            child: Text(context.strings.cancel),
          ),
        ] else ...[
          LibraryGlass(
            radius: 16,
            child: ListTile(
              leading: const Icon(Icons.save_alt_rounded),
              title: Text(context.strings.saveToFile),
              subtitle: Text(context.strings.backupContents),
              onTap: busy ? null : _save,
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
          const SizedBox(height: 8),
          LibraryGlass(
            radius: 16,
            child: ListTile(
              leading: const Icon(Icons.restore_rounded),
              title: Text(context.strings.restoreFromFile),
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
