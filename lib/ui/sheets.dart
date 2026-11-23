import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import '../model.dart';
import 'style.dart';

Future<T?> panel<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: paper,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (c) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
          child: child,
        ),
      ),
    );

class ResultSheet extends StatefulWidget {
  const ResultSheet(this.matches, this.path, {super.key});
  final List<Match> matches;
  final String path;
  @override
  State<ResultSheet> createState() => _ResultSheetState();
}

class _ResultSheetState extends State<ResultSheet> {
  int selected = 0;
  late Edition card = widget.matches.first.editions.first;
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
              child: Image.file(
                File(widget.path),
                width: 66,
                height: 90,
                fit: BoxFit.cover,
                cacheWidth: 160,
                errorBuilder: (_, _, _) => const Mark(),
              ),
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
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, card),
          icon: const Icon(Icons.add),
          label: const Text('В коллекцию'),
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

class CollectionPage extends StatelessWidget {
  const CollectionPage(this.model, {super.key});
  final AppModel model;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(backgroundColor: paper, title: const Text('Картовед')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHeading('Коллекция'),
            const SizedBox(height: 12),
            if (model.cards.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Folio(),
                      const SizedBox(height: 14),
                      const Text(
                        'Пока нет карт',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        icon: const Icon(Icons.center_focus_strong),
                        onPressed: () => Navigator.pop(context),
                        label: const Text('Сканировать карту'),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: model.cards.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (c, i) {
                    final entry = model.cards[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        entry.card.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(entry.card.detail),
                      trailing: Text(
                        '×${entry.quantity}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    ),
  );
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
