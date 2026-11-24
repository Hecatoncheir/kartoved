import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import '../data/review.dart';
import '../model.dart';
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

Future<void> openReviews(BuildContext context, AppModel model) =>
    Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => _ReviewPage(model)),
    );

Future<bool> reviewBeforeExport(BuildContext context, AppModel model) async {
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
    await openReviews(context, model);
  }
  return proceed == true;
}

class ReviewButton extends StatelessWidget {
  const ReviewButton(this.count, this.onPressed, {super.key});
  final int count;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.fact_check_outlined),
    label: Text('Проверить · $count'),
    style: TextButton.styleFrom(foregroundColor: butter, backgroundColor: dark),
  );
}

class _ReviewPage extends StatelessWidget {
  const _ReviewPage(this.model);
  final AppModel model;
  Future<void> open(BuildContext context, int seq) async {
    try {
      await chooseReview(context, model, seq);
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Проверка карт')),
    body: BlocBuilder<AppModel, LibraryState>(
      bloc: model,
      builder: (_, state) {
        final pending = state.reviews.entries.toList();
        if (pending.isEmpty) {
          return const Center(child: Text('Все карты проверены'));
        }
        return ListView.builder(
          itemCount: pending.length,
          itemBuilder: (_, i) {
            final item = pending[i];
            final card = item.value.choices.first;
            return ListTile(
              leading: SizedBox(width: 38, child: CardPicture(card)),
              title: Text(card.name),
              subtitle: Text(item.value.reason.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => open(context, item.key),
            );
          },
        );
      },
    ),
  );
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
