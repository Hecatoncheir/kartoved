import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../collection_rows.dart';
import '../data/catalog.dart';
import '../model.dart';
import 'card_facts.dart';
import 'picture.dart';
import 'style.dart';
import 'card_destination.dart';
import 'sheets.dart';

class CollectionDetail extends StatefulWidget {
  const CollectionDetail(this.row, {super.key});
  final CollectionRow row;

  @override
  State<CollectionDetail> createState() => _CollectionDetailState();
}

class _CollectionDetailState extends State<CollectionDetail> {
  late Edition selected = widget.row.card;
  bool saving = false;
  final scroll = ScrollController();

  void _select(Edition card) {
    setState(() => selected = card);
    if (MediaQuery.disableAnimationsOf(context)) {
      scroll.jumpTo(0);
    } else {
      scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  Future<void> _write(Future<void> Function() action) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: noticeDuration,
            content: Text('Не удалось сохранить изменение'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _move(AppModel model, int available) async {
    final others = model.state.groups
        .where((g) => g.id != model.state.folder)
        .toList();
    final messenger = ScaffoldMessenger.of(context);
    final result = await panel<CardSelection>(
      context,
      CardDestination(
        card: selected,
        groups: others,
        initialFolder: others.firstOrNull?.id,
        available: available,
      ),
    );
    if (result == null || !mounted) return;
    final receipt = switch (result.folderId) {
      final id? => await model.moveCards(id, result.card, result.quantity),
      null => await model.moveToNewCollection(
        result.folderName,
        result.card,
        result.quantity,
      ),
    };
    if (!mounted) return;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        duration: noticeDuration,
        persist: false,
        content: Text('В «${result.folderName}» · ${result.quantity}'),
        action: SnackBarAction(
          label: 'Отменить',
          onPressed: () async {
            try {
              await model.undoMove(receipt);
            } catch (_) {
              if (messenger.mounted) {
                messenger.showSnackBar(
                  const SnackBar(
                    duration: noticeDuration,
                    content: Text('Не удалось отменить перемещение'),
                  ),
                );
              }
            }
          },
        ),
      ),
    );
  }

  Future<void> _resolve(AppModel model) async {
    final folder = model.state.folder;
    final card = await choosePrinting(context, model.catalog!, selected);
    if (!mounted || card == null || model.state.folder != folder) return;
    await model.resolvePrinting(folder, selected, card);
    if (mounted) setState(() => selected = card);
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<AppModel, LibraryState>(
    builder: (context, state) {
      final model = context.read<AppModel>();
      final counts = {
        for (final p in state.printings) p.card.printingKey: p.quantity,
      };
      final quantity = counts[selected.printingKey] ?? 0;
      final flagged = state.flags.contains(selected.printingKey);
      return Scaffold(
        backgroundColor: dark,
        appBar: AppBar(
          backgroundColor: dark,
          foregroundColor: paper,
          title: Text(selected.name),
          actions: [
            IconButton(
              tooltip: flagged ? 'Снять флажок' : 'Поставить флажок',
              onPressed: saving || quantity == 0
                  ? null
                  : () => _write(() => model.setFlag(selected, !flagged)),
              icon: Icon(
                flagged ? Icons.flag_rounded : Icons.flag_outlined,
                color: flagged ? butter : paper,
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
            children: [
              SizedBox(
                height: math.min(
                  420.0,
                  MediaQuery.sizeOf(context).height * .44,
                ),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 63 / 88,
                    child: Hero(
                      tag: widget.row.key,
                      child: CardPicture(selected, large: true),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '${selected.detail}  ·  ${selected.foil ? 'Фольга' : 'Обычная'}',
                textAlign: TextAlign.center,
                style: codeText,
              ),
              const SizedBox(height: 12),
              if (selected.needsPrinting)
                OutlinedButton.icon(
                  icon: const Icon(Icons.style_outlined),
                  label: const Text('Уточнить издание экземпляра'),
                  onPressed: saving || quantity == 0 || model.catalog == null
                      ? null
                      : () => _write(() => _resolve(model)),
                ),
              Center(
                child: Frost(
                  radius: 24,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Убрать один экземпляр',
                        color: paper,
                        onPressed: saving || quantity == 0
                            ? null
                            : () => _write(() => model.takeOne(selected)),
                        icon: const Icon(Icons.remove),
                      ),
                      Semantics(
                        liveRegion: true,
                        label: 'Экземпляров',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            '$quantity',
                            style: const TextStyle(
                              fontSize: 21,
                              fontFamily: monoFont,
                              fontWeight: FontWeight.w800,
                              color: paper,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Добавить один экземпляр',
                        color: butter,
                        onPressed: saving
                            ? null
                            : () => _write(() => model.save(selected)),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: butter),
                onPressed: saving || quantity == 0
                    ? null
                    : () => _write(() => _move(model, quantity)),
                icon: const Icon(Icons.drive_file_move_outline),
                label: const Text('Переместить'),
              ),
              if (widget.row.multiple) ...[
                const SizedBox(height: 20),
                for (final v in widget.row.variants)
                  ListTile(
                    textColor: paper,
                    iconColor: butter,
                    leading: Icon(
                      v.card.printingKey == selected.printingKey
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    title: Text(
                      '${v.card.detail}  ·  ${v.card.foil ? 'Фольга' : 'Обычная'}',
                      style: codeText,
                    ),
                    trailing: Text(
                      '×${counts[v.card.printingKey] ?? 0}',
                      style: codeText,
                    ),
                    onTap: saving ? null : () => _select(v.card),
                  ),
              ],
              const SizedBox(height: 12),
              if (!selected.needsPrinting) ScryfallLink(selected),
              CardFacts(selected.id, key: ValueKey(selected.id)),
            ],
          ),
        ),
      );
    },
  );
}
