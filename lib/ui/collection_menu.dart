import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/strings.dart';
import '../data/catalog.dart';
import '../model.dart';
import 'style.dart';

enum _Action { rename, transfer, delete }

class CollectionMenu extends StatefulWidget {
  const CollectionMenu(this.library, {super.key});
  final LibraryState library;

  @override
  State<CollectionMenu> createState() => _CollectionMenuState();
}

class _CollectionMenuState extends State<CollectionMenu> {
  bool busy = false;

  Future<void> _manage(_Action action) async {
    if (busy) return;
    setState(() => busy = true);
    final model = context.read<AppModel>();
    try {
      if (action == _Action.rename) {
        await _rename(model, widget.library);
      } else {
        await _delete(
          model,
          widget.library,
          transfer: action == _Action.transfer,
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: noticeDuration,
            content: Text(context.strings.changeCollectionFailed),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _rename(AppModel model, LibraryState library) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => CollectionNameDialog(initialName: library.title),
    );
    if (name != null && mounted) await model.renameFolder(library.folder, name);
  }

  Future<void> _delete(
    AppModel model,
    LibraryState library, {
    required bool transfer,
  }) async {
    final targets = transfer
        ? library.groups.where((g) => g.id != library.folder).toList()
        : const <CardGroup>[];
    if (transfer && targets.isEmpty) return;
    final result = await showDialog<({CardGroup? target})>(
      context: context,
      builder: (_) => _DeleteDialog(library, targets),
    );
    if (result == null || !mounted) return;
    // Последняя коллекция может исчезнуть вместе с кнопкой меню.
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final target = result.target;
    final strings = context.strings;
    await model.deleteFolder(library.folder, moveTo: target?.id);
    if (route?.isCurrent == true && navigator.canPop()) navigator.pop();
    if (!messenger.mounted) return;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        duration: noticeDuration,
        content: Text(
          target == null
              ? strings.collectionDeleted(library.title)
              : strings.cardsTransferred(target.name),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<_Action>(
    tooltip: context.strings.collectionActions,
    enabled: !busy,
    onSelected: _manage,
    itemBuilder: (_) => [
      PopupMenuItem(value: _Action.rename, child: Text(context.strings.rename)),
      if (widget.library.groups.length > 1 && widget.library.recent.isNotEmpty)
        PopupMenuItem(
          value: _Action.transfer,
          child: Text(context.strings.moveCardsAndDelete),
        ),
      PopupMenuItem(
        value: _Action.delete,
        child: Text(
          widget.library.recent.isEmpty
              ? context.strings.deleteCollection
              : context.strings.deleteWithCards,
        ),
      ),
    ],
  );
}

class CollectionNameDialog extends StatefulWidget {
  const CollectionNameDialog({super.key, this.initialName});
  final String? initialName;

  @override
  State<CollectionNameDialog> createState() => _CollectionNameDialogState();
}

class _CollectionNameDialogState extends State<CollectionNameDialog> {
  late String value = widget.initialName ?? '';
  bool get valid => value.isNotEmpty && value != widget.initialName;

  void submit() {
    if (valid) Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(
      widget.initialName == null
          ? context.strings.newCollection
          : context.strings.renameCollection,
    ),
    content: TextFormField(
      initialValue: widget.initialName,
      autofocus: true,
      maxLength: 80,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(labelText: context.strings.name),
      onChanged: (v) => setState(() => value = v.trim()),
      onFieldSubmitted: (_) => submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.strings.cancel),
      ),
      FilledButton(
        onPressed: valid ? submit : null,
        child: Text(
          widget.initialName == null
              ? context.strings.create
              : context.strings.save,
        ),
      ),
    ],
  );
}

class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog(this.library, this.targets);
  final LibraryState library;
  final List<CardGroup> targets;

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  late CardGroup? target = widget.targets.firstOrNull;

  @override
  Widget build(BuildContext context) {
    final library = widget.library;
    final targets = widget.targets;
    final group = library.groups.firstWhere((g) => g.id == library.folder);
    return AlertDialog(
      scrollable: true,
      icon: Icon(
        targets.isEmpty ? Icons.delete_outline : Icons.drive_file_move_outline,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text(context.strings.deleteNamedCollection(group.name)),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.strings.deleteCollectionStats(
              group.count,
              library.reviews.length,
            ),
          ),
          const SizedBox(height: 12),
          if (targets.isNotEmpty) ...[
            Text(context.strings.moveCollectionWarning),
            const SizedBox(height: 12),
            DropdownButtonFormField<CardGroup>(
              initialValue: targets.first,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.strings.moveDestination,
              ),
              items: [
                for (final target in targets)
                  DropdownMenuItem(
                    value: target,
                    child: Text(target.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => target = value,
            ),
          ] else
            Text(
              library.recent.isEmpty
                  ? context.strings.deleteEmptyCollectionWarning
                  : context.strings.deleteAllCollectionWarning,
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.strings.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, (target: target)),
          child: Text(
            targets.isEmpty
                ? context.strings.delete
                : context.strings.moveAndDelete,
          ),
        ),
      ],
    );
  }
}
