import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/strings.dart';
import '../collection_rows.dart';
import '../data/catalog.dart';
import '../model.dart';
import 'card_facts.dart';
import 'glass_sheet.dart';
import 'library_style.dart';
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
  late final variants = {
    for (final variant in widget.row.variants)
      variant.card.printingKey: variant.card,
  };
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
          SnackBar(
            duration: noticeDuration,
            content: Text(context.strings.saveChangeFailed),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _move(AppModel model, int available) async {
    final source = model.state.folder;
    final others = model.state.groups.where((g) => g.id != source).toList();
    final messenger = ScaffoldMessenger.of(context);
    final result = await showGlassSheet<CardSelection>(
      context,
      CardDestination(
        card: selected,
        groups: others,
        initialFolder: others.firstOrNull?.id,
        available: available,
      ),
      library: true,
    );
    if (result == null || !mounted || model.state.folder != source) return;
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
        content: Text(
          context.strings.movedCopies(result.folderName, result.quantity),
        ),
        action: SnackBarAction(
          label: context.strings.undo,
          onPressed: () async {
            try {
              await model.undoMove(receipt);
            } catch (_) {
              if (messenger.mounted) {
                messenger.showSnackBar(
                  SnackBar(
                    duration: noticeDuration,
                    content: Text(context.strings.undoMoveFailed),
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
    final card = await choosePrinting(
      context,
      model.catalog!,
      selected,
      library: true,
    );
    if (!mounted || card == null || model.state.folder != folder) return;
    final previous = selected.printingKey;
    await model.resolvePrinting(folder, selected, card);
    if (!mounted) return;
    setState(() {
      if (!model.state.printings.any((p) => p.card.printingKey == previous)) {
        variants.remove(previous);
      }
      variants[card.printingKey] = card;
      selected = card;
    });
  }

  Widget _inventory(AppModel model, int quantity) {
    final canRemove = quantity > 0 && !saving;
    return LibraryGlass(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 4,
              children: [
                ExcludeSemantics(
                  child: Text(
                    context.strings.copies,
                    style: TextStyle(
                      fontFamily: headingFont,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: context.strings.subtractCopy,
                      onPressed: canRemove
                          ? () => _write(() => model.takeOne(selected))
                          : null,
                      icon: const Icon(Icons.remove),
                    ),
                    Flexible(
                      child: Semantics(
                        container: true,
                        liveRegion: true,
                        label: context.strings.copiesCount(quantity),
                        excludeSemantics: true,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '$quantity',
                              style: const TextStyle(
                                fontFamily: monoFont,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    DecoratedBox(
                      decoration: saving
                          ? const BoxDecoration()
                          : libraryActionSurface,
                      child: IconButton(
                        tooltip: context.strings.addCopy,
                        onPressed: saving
                            ? null
                            : () => _write(() => model.save(selected)),
                        icon: const Icon(Icons.add),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: canRemove
                      ? () => _write(() => _move(model, quantity))
                      : null,
                  icon: const Icon(Icons.drive_file_move_outline),
                  label: Text(context.strings.move),
                ),
                if (selected.needsPrinting)
                  TextButton.icon(
                    onPressed: canRemove && model.catalog != null
                        ? () => _write(() => _resolve(model))
                        : null,
                    icon: const Icon(Icons.style_outlined),
                    label: Text(context.strings.refineCopyPrinting),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _overview(AppModel model, int quantity) => LayoutBuilder(
    builder: (context, constraints) {
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              selected.name,
              style: const TextStyle(
                fontFamily: headingFont,
                color: libraryInk,
                fontSize: 30,
                height: 1.1,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _printingLabel(selected),
            style: const TextStyle(
              fontFamily: monoFont,
              color: libraryMuted,
              fontSize: 13,
            ),
          ),
        ],
      );
      final picture = Center(
        child: LibraryGlass(
          radius: 16,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              height: math.min(420.0, MediaQuery.sizeOf(context).height * .40),
              child: AspectRatio(
                aspectRatio: 63 / 88,
                child: Hero(
                  tag: widget.row.key,
                  child: CardPicture(selected, large: true),
                ),
              ),
            ),
          ),
        ),
      );
      final inventory = _inventory(model, quantity);
      if (constraints.maxWidth < 620) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heading,
            const SizedBox(height: 16),
            picture,
            const SizedBox(height: 16),
            inventory,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(flex: 2, child: picture),
          const SizedBox(width: 24),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [heading, const SizedBox(height: 18), inventory],
            ),
          ),
        ],
      );
    },
  );

  Widget _variants(Map<String, int> counts) => LibraryGlass(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text(
            context.strings.albumVariants,
            style: TextStyle(
              fontFamily: headingFont,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
        ),
        for (final card in variants.values)
          Semantics(
            checked: card.printingKey == selected.printingKey,
            inMutuallyExclusiveGroup: true,
            child: ListTile(
              selected: card.printingKey == selected.printingKey,
              leading: Icon(
                card.printingKey == selected.printingKey
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(
                _printingLabel(card),
                style: const TextStyle(fontFamily: monoFont, fontSize: 13),
              ),
              trailing: Text('×${counts[card.printingKey] ?? 0}'),
              onTap: saving ? null : () => _select(card),
            ),
          ),
      ],
    ),
  );

  String _printingLabel(Edition card) =>
      '${card.detail}  ·  ${card.foil ? context.strings.foil : context.strings.nonFoil}';

  @override
  Widget build(BuildContext context) => BlocBuilder<AppModel, LibraryState>(
    builder: (context, state) {
      final model = context.read<AppModel>();
      final printings = state.printings;
      final counts = {
        for (final p in printings) p.card.printingKey: p.quantity,
      };
      final quantity = counts[selected.printingKey] ?? 0;
      final flagged = state.flags.contains(selected.printingKey);
      return Theme(
        data: libraryTheme,
        child: DecoratedBox(
          decoration: librarySky,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              forceMaterialTransparency: true,
              systemOverlayStyle: SystemUiOverlayStyle.dark,
              title: Text(
                state.title,
                style: const TextStyle(
                  fontFamily: headingFont,
                  fontWeight: FontWeight.w800,
                ),
              ),
              actions: [
                IconButton(
                  tooltip: flagged
                      ? context.strings.removeFlag
                      : context.strings.addFlag,
                  onPressed: saving || quantity == 0
                      ? null
                      : () => _write(() => model.setFlag(selected, !flagged)),
                  icon: Icon(
                    flagged ? Icons.flag_rounded : Icons.flag_outlined,
                  ),
                  color: flagged ? const Color(0xff965019) : libraryInk,
                ),
              ],
            ),
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: ListView(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      _overview(model, quantity),
                      if (variants.length > 1) ...[
                        const SizedBox(height: 14),
                        _variants(counts),
                      ],
                      const SizedBox(height: 16),
                      CardFacts(selected, key: ValueKey(selected.id)),
                      if (!selected.needsPrinting) ScryfallLink(selected),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
