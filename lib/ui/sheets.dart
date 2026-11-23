import 'picture.dart';
import '../data/pictures.dart';

import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import '../model.dart';
import 'style.dart';

Future<T?> panel<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (c) => Frost(
        light: true,
        radius: 0,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            child: child,
          ),
        ),
      ),
    );

class ResultSheet extends StatefulWidget {
  const ResultSheet(
    this.matches,
    this.initial, {
    super.key,
    this.action = 'В коллекцию',
  });
  final List<Match> matches;
  final Edition initial;
  final String action;
  @override
  State<ResultSheet> createState() => _ResultSheetState();
}

class _ResultSheetState extends State<ResultSheet> {
  int selected = 0;
  late Edition card = widget.initial;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHeading('Результат'),
        const SizedBox(height: 18),
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(width: 66, height: 90, child: CardPicture(card)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.name,
                    style: const TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(card.detail, style: const TextStyle(color: muted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (widget.matches[selected].editions.length > 1)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.layers_outlined),
            title: const Text('Издание и язык'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final edition = await panel<Edition>(
                context,
                EditionPicker(widget.matches[selected].editions, card),
              );
              if (edition != null && mounted) setState(() => card = edition);
            },
          ),
        if (widget.matches.length > 1)
          ExpansionTile(
            key: ValueKey(selected),
            tilePadding: EdgeInsets.zero,
            title: const Text('Другие совпадения'),
            children: [
              for (final (i, match) in widget.matches.indexed)
                if (i != selected)
                  ListTile(
                    title: Text(match.editions.first.name),
                    subtitle: Text(match.editions.first.detail),
                    onTap: () => setState(() {
                      selected = i;
                      card = match.editions.first;
                    }),
                  ),
            ],
          ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.auto_awesome_outlined),
          title: const Text('Фольга'),
          value: card.foil,
          onChanged: (value) => setState(() => card = card.withFoil(value)),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, card),
          icon: const Icon(Icons.check),
          label: Text(widget.action),
        ),
      ],
    ),
  );
}

class EditionPicker extends StatefulWidget {
  const EditionPicker(this.options, this.selected, {super.key});
  final List<Edition> options;
  final Edition selected;
  @override
  State<EditionPicker> createState() => _EditionPickerState();
}

class _EditionPickerState extends State<EditionPicker> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final options = widget.options
        .where((e) => e.detail.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .68,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetHeading('Издание и язык'),
          const SizedBox(height: 10),
          TextField(
            onChanged: (s) => setState(() => query = s),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Код выпуска, номер или язык',
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: options.length,
              itemBuilder: (c, i) => ListTile(
                title: Text(options[i].detail),
                trailing: options[i].id == widget.selected.id
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(c, options[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CatalogPanel extends StatefulWidget {
  const CatalogPanel(this.model, {super.key});
  final AppModel model;
  @override
  State<CatalogPanel> createState() => _CatalogPanelState();
}

class _CatalogPanelState extends State<CatalogPanel> {
  String? message;
  bool loading = false;
  Future<void> update() async {
    setState(() {
      loading = true;
      message = null;
    });
    String result;
    try {
      result = await widget.model.update()
          ? 'База обновлена'
          : 'Установлена последняя версия';
    } catch (e) {
      debugPrint('Обновление: $e');
      result = 'Не удалось обновить. Сохранённая база доступна.';
    }
    if (mounted) {
      setState(() {
        message = result;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.model.catalog!.spec;
    final date = spec.created;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHeading('База карт'),
        const SizedBox(height: 18),
        DecoratedBox(
          decoration: BoxDecoration(
            color: cream,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const Icon(Icons.inventory_2_outlined, size: 32),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${spec.count} иллюстраций',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'От ${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} · доступна офлайн',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        TextButton.icon(
          icon: const Icon(Icons.download_outlined),
          label: const Text('Миниатюры выпуска офлайн'),
          onPressed: loading
              ? null
              : () => panel<void>(context, PicturePack(widget.model.catalog!)),
        ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(message!, semanticsLabel: message),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: loading ? null : update,
          icon: loading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync),
          label: Text(loading ? 'Обновление…' : 'Проверить обновления'),
        ),
      ],
    );
  }
}

class PicturePack extends StatefulWidget {
  const PicturePack(this.catalog, {super.key});
  final Catalog catalog;
  @override
  State<PicturePack> createState() => _PicturePackState();
}

class _PicturePackState extends State<PicturePack> {
  String code = '', language = 'en', status = '';
  bool loading = false;
  void progress(String text) {
    if (mounted) setState(() => status = text);
  }

  Future<void> download() async {
    setState(() {
      loading = true;
      status = 'Поиск изданий…';
    });
    try {
      final cards = await widget.catalog.inSet(
        code.trim().toLowerCase(),
        language.trim().toLowerCase(),
      );
      var done = 0;
      for (final card in cards) {
        if (!mounted) return;
        await Pictures.shared.get(card.id);
        if (mounted) setState(() => status = '${++done} из ${cards.length}');
      }
      progress(
        cards.isEmpty
            ? 'Выпуск на этом языке не найден'
            : 'Миниатюры сохранены',
      );
    } catch (_) {
      progress('Загрузка прервана. Можно продолжить.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHeading('Миниатюры выпуска'),
        TextField(
          enabled: !loading,
          decoration: const InputDecoration(
            labelText: 'Код выпуска',
            hintText: 'SNC',
          ),
          onChanged: (v) => setState(() => code = v),
        ),
        TextFormField(
          initialValue: language,
          enabled: !loading,
          decoration: const InputDecoration(
            labelText: 'Язык',
            hintText: 'ru, en…',
          ),
          onChanged: (v) => setState(() => language = v),
        ),
        if (status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(status),
          ),
        FilledButton(
          onPressed: code.trim().isEmpty || language.trim().isEmpty || loading
              ? null
              : download,
          child: const Text('Скачать'),
        ),
      ],
    ),
  );
}
