import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import '../data/review.dart';
import '../model.dart';
import 'library_style.dart';
import 'picture.dart';
import 'sheets.dart';
import 'style.dart';

Future<void> chooseReview(BuildContext context, AppModel model, int seq) async {
  final review = model.state.reviews[seq];
  if (review == null) return;
  final folder = model.state.folder;
  final choice = await panel<({Edition? card})>(context, _ChoiceSheet(review));
  if (choice == null || folder != model.state.folder) return;
  if (choice.card case final card?) {
    await model.confirmReview(seq, card);
  } else {
    await model.discardScan(seq, pendingOnly: true);
  }
}

Future<bool> reviewBeforeExport(
  BuildContext context,
  AppModel model,
  VoidCallback showReviews,
) async {
  final folder = model.state.folder;
  final proceed = await panel<bool>(
    context,
    Builder(
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHeading('Есть спорные карты'),
          Text(
            'В CSV попадут только подтверждённые экземпляры. На проверке: ${model.state.reviews.length}.',
          ),
          FilledButton(
            onPressed: () => Navigator.pop(sheet, false),
            child: const Text('Проверить карты'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(sheet, true),
            child: const Text('Экспортировать подтверждённые'),
          ),
        ],
      ),
    ),
  );
  if (proceed == false && context.mounted && model.state.folder == folder) {
    showReviews();
  }
  return proceed == true;
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
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .82,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.review.reason.label,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (widget.review.batchLabel.isNotEmpty)
          Text('Стопка · ${widget.review.batchLabel}'),
        const SizedBox(height: 12),
        Flexible(
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 210,
              mainAxisExtent: 176,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: widget.review.choices.length,
            itemBuilder: (_, i) {
              final card = widget.review.choices[i];
              final selected = chosen == card;
              return Semantics(
                selected: selected,
                button: true,
                child: InkWell(
                  onTap: () => setState(() => chosen = card),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? butter : strongOutline,
                        width: selected ? 2 : .5,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        children: [
                          Expanded(
                            child: Stack(
                              alignment: Alignment.center,
                              fit: StackFit.expand,
                              children: [
                                Center(
                                  child: AspectRatio(
                                    aspectRatio: 63 / 88,
                                    child: CardPicture(card),
                                  ),
                                ),
                                if (selected)
                                  const Align(
                                    alignment: Alignment.topRight,
                                    child: Icon(
                                      Icons.check_circle,
                                      color: butter,
                                      size: 19,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            card.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            card.foil ? '${card.detail} · Фольга' : card.detail,
                            textAlign: TextAlign.center,
                            style: codeText,
                          ),
                        ],
                      ),
                    ),
                  ),
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
    ),
  );
}
