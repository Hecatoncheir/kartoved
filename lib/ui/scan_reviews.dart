import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import '../data/review.dart';
import '../model.dart';
import 'library_style.dart';
import 'picture.dart';
import 'glass_sheet.dart';
import 'style.dart';

Future<void> chooseReview(
  BuildContext context,
  AppModel model,
  int seq, {
  bool scanner = false,
}) async {
  final review = model.state.reviews[seq];
  if (review == null) return;
  final folder = model.state.folder;
  final choice = await showGlassSheet<({Edition? card})>(
    context,
    _ChoiceSheet(review),
    library: !scanner,
  );
  if (choice == null || folder != model.state.folder) return;
  if (choice.card case final card?) {
    await model.confirmReview(seq, card);
  } else {
    await model.discardScan(seq, pendingOnly: true);
  }
}

class ReviewList extends StatelessWidget {
  const ReviewList({
    required this.onRescan,
    required this.onBackToAlbum,
    super.key,
  });
  final ValueChanged<ScanEntry>? onRescan;
  final VoidCallback onBackToAlbum;
  Future<void> open(BuildContext context, int seq) async {
    try {
      await chooseReview(context, context.read<AppModel>(), seq);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: noticeDuration,
            content: Text('Не удалось сохранить решение'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppModel>().state;
    final pending = state.recent
        .where((entry) => state.reviews.containsKey(entry.sequence))
        .toList();
    if (pending.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          child: LibraryGlass(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    size: 32,
                    color: libraryMuted,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Все карты проверены',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: headingFont,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: libraryInk,
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: libraryInk),
                    onPressed: onBackToAlbum,
                    child: const Text('К альбому'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      key: PageStorageKey(('reviews', state.folder)),
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 12,
      ),
      itemCount: pending.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final item = pending[i];
        final card = item.card;
        return LibraryGlass(
          key: ValueKey(item.sequence),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  leading: SizedBox(
                    width: 46,
                    height: 62,
                    child: CardPicture(card, tilt: false),
                  ),
                  title: Text(
                    card.name,
                    style: const TextStyle(
                      fontFamily: headingFont,
                      color: libraryInk,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: Text(
                    state.reviews[item.sequence]!.reason.label,
                    style: const TextStyle(color: libraryMuted),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: libraryMuted,
                  ),
                  onTap: () => open(context, item.sequence),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: libraryInk),
                      onPressed: onRescan == null
                          ? null
                          : () => onRescan!(item),
                      icon: const Icon(Icons.camera_alt_outlined, size: 19),
                      label: Text(
                        'Переснять',
                        semanticsLabel: 'Переснять ${card.name}',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChoiceSheet extends StatefulWidget {
  const _ChoiceSheet(this.review);
  final ScanReview review;
  @override
  State<_ChoiceSheet> createState() => _ChoiceSheetState();
}

class _ChoiceSheetState extends State<_ChoiceSheet> {
  Edition? chosen;
  @override
  Widget build(BuildContext context) {
    final review = widget.review;
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeading(review.reason.label),
        if (review.batchLabel.isNotEmpty) Text('Стопка · ${review.batchLabel}'),
        const SizedBox(height: 8),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: review.choices.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (_, index) {
              final card = review.choices[index];
              final selected = chosen == card;
              return Material(
                color: selected
                    ? colors.secondaryContainer
                    : colors.surface.withValues(alpha: .72),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: selected ? colors.primary : colors.outlineVariant,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  selected: selected,
                  selectedColor: colors.onSecondaryContainer,
                  leading: SizedBox(
                    width: 42,
                    height: 56,
                    child: CardPicture(card, tilt: false),
                  ),
                  title: Text(card.name),
                  subtitle: Text(
                    card.foil ? '${card.detail} · Фольга' : card.detail,
                    style: codeText,
                  ),
                  trailing: Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked,
                  ),
                  onTap: () => setState(() => chosen = card),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: chosen == null
              ? null
              : () => Navigator.pop(context, (card: chosen)),
          child: const Text('Подтвердить'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, (card: null as Edition?)),
          child: const Text('Убрать из очереди'),
        ),
      ],
    );
  }
}
