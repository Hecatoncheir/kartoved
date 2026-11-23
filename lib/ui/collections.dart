import 'dart:ui' as ui;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../data/android.dart';
import '../data/catalog.dart';
import '../model.dart';
import 'scanner.dart';
import 'style.dart';
import 'sheets.dart';
import 'collection_light.dart';
import 'collection_stack.dart';
import 'album.dart';
import 'catalog_search.dart';

class CollectionsPage extends StatelessWidget {
  const CollectionsPage({super.key});
  Future<void> _create(BuildContext context) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => const _NameDialog(),
    );
    if (title == null || !context.mounted) return;
    await context.read<AppModel>().create(title);
    if (context.mounted) await _open(context);
  }

  Future<void> _open(BuildContext context) => Navigator.of(context)
      .push<void>(MaterialPageRoute(builder: (_) => const CollectionPage()));
  @override
  Widget build(BuildContext context) => BlocBuilder<AppModel, LibraryState>(
    builder: (context, state) {
      final model = context.read<AppModel>();
      return Scaffold(
        appBar: AppBar(
          title: const Row(
            children: [
              Mark(size: 32, color: ink),
              SizedBox(width: 8),
              Text('Картовед'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'База карт',
              onPressed: state.catalog == null
                  ? null
                  : () => panel<void>(context, CatalogPanel(model)),
              icon: const Icon(Icons.storage_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AlbumHeader(
                  total: state.groups.fold(0, (sum, g) => sum + g.count),
                  search: state.catalog == null
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => CatalogSearchPage(state.catalog!),
                          ),
                        ),
                ),
                const SizedBox(height: 16),
                if (state.error != null)
                  TextButton(
                    onPressed: model.initialize,
                    child: Text('${state.error}. Повторить'),
                  ),
                if (state.catalog == null && state.error == null)
                  const LinearProgressIndicator(),
                Expanded(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: state.groups.isEmpty ? 0 : 1),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    builder: (_, value, child) => Transform.translate(
                      offset: Offset(0, 10 * (1 - value)),
                      child: Opacity(opacity: value, child: child),
                    ),
                    child: ListView.separated(
                      itemCount: state.groups.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (c, i) {
                        final group = state.groups[i];
                        return AlbumTile(group, () async {
                          await model.select(group.id);
                          if (context.mounted) await _open(context);
                        });
                      },
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: state.catalog == null
                      ? null
                      : () => _create(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Создать коллекцию'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog();
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  String value = '';
  void submit() {
    if (value.isNotEmpty) Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Новая коллекция'),
    content: TextField(
      autofocus: true,
      maxLength: 80,
      textInputAction: TextInputAction.done,
      decoration: const InputDecoration(labelText: 'Название'),
      onChanged: (v) => setState(() => value = v.trim()),
      onSubmitted: (_) => submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: value.isEmpty ? null : submit,
        child: const Text('Создать'),
      ),
    ],
  );
}

class CollectionPage extends StatelessWidget {
  const CollectionPage({super.key});
  Future<void> _flag(BuildContext context, Edition card, bool value) async {
    try {
      await context.read<AppModel>().setFlag(card, value);
    } catch (_) {
      if (context.mounted) _message(context, 'Не удалось сохранить флажок');
    }
  }

  void _message(BuildContext context, String text, [SnackBarAction? action]) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(text), action: action));
  }

  Future<void> _remove(BuildContext context, Edition card) async {
    final model = context.read<AppModel>();
    try {
      final removed = await model.remove(card);
      if (!context.mounted || removed.scans.isEmpty) return;
      final count = removed.scans.fold(0, (n, scan) => n + scan.quantity);
      _message(
        context,
        'Убрано: ${card.name} ×$count',
        SnackBarAction(
          label: 'Отменить',
          onPressed: () async {
            try {
              await model.restore(removed);
            } catch (_) {
              if (context.mounted) {
                _message(context, 'Не удалось вернуть карту');
              }
            }
          },
        ),
      );
    } catch (_) {
      if (context.mounted) _message(context, 'Не удалось убрать карту');
    }
  }

  Future<void> _export(BuildContext context) async {
    final model = context.read<AppModel>();
    try {
      final csv = await model.export();
      final name = model.state.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      await AndroidActions.saveCsv('${name}_Moxfield.csv', csv);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить CSV')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<AppModel, LibraryState>(
    builder: (context, state) {
      final rows = <String, CardCount>{};
      for (final r in state.recent) {
        final key = r.card.printingKey;
        rows[key] = (
          card: r.card,
          quantity: (rows[key]?.quantity ?? 0) + r.quantity,
        );
      }
      final items = rows.values.toList();
      return CollectionLight(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            scrolledUnderElevation: 0,
            foregroundColor: paper,
            titleTextStyle: const TextStyle(
              color: paper,
              fontFamily: 'Nunito',
              fontWeight: FontWeight.w900,
              fontSize: 25,
            ),
            title: Text(state.title),
            actions: [
              IconButton(
                tooltip: 'Экспорт для Moxfield',
                onPressed: items.isEmpty ? null : () => _export(context),
                icon: const Icon(Icons.ios_share_outlined),
              ),
            ],
          ),
          body: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
              child: Column(
                children: [
                  if (items.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Frost(
                        radius: 16,
                        child: DefaultTextStyle(
                          style: const TextStyle(
                            color: paper,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Nunito Sans',
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 14,
                            ),
                            child: Wrap(
                              spacing: 14,
                              runSpacing: 4,
                              children: [
                                Text(
                                  'Карт · ${items.fold<int>(0, (a, b) => a + b.quantity)}',
                                ),
                                Text(
                                  'Названий · ${items.map((r) => r.card.name).toSet().length}',
                                ),
                                Text(
                                  'Фольга · ${items.where((r) => r.card.foil).fold<int>(0, (a, b) => a + b.quantity)}',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: items.isEmpty
                        ? const SafeArea(
                            top: false,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Folio(),
                                  Text(
                                    'Пока нет карт',
                                    style: TextStyle(color: paper),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : CollectionStack(
                            key: ValueKey(state.folder),
                            items: items,
                            flags: state.flags,
                            onFlag: (card, value) =>
                                _flag(context, card, value),
                            onRemove: (card) => _remove(context, card),
                          ),
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: const _ScanButton(),
        ),
      );
    },
  );
}

class _ScanButton extends StatelessWidget {
  const _ScanButton();

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: DecoratedBox(
            decoration: const ShapeDecoration(
              shape: StadiumBorder(side: BorderSide(color: Color(0xadffe6a3))),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xb3ffe6a3),
                  Color(0x99ffcc54),
                  Color(0x8cfabd2f),
                  Color(0x9afabd2f),
                ],
                stops: [0, .12, .65, 1],
              ),
            ),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: const Color(0xff090a07),
                elevation: 0,
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const Scanner()),
              ),
              icon: const Icon(Icons.center_focus_strong),
              label: const Text('Сканировать карту'),
            ),
          ),
        ),
      ),
    ),
  );
}
