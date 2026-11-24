import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/android.dart';
import '../data/card_reference.dart';
import '../data/catalog.dart';
import 'style.dart';

class ScryfallLink extends StatelessWidget {
  const ScryfallLink(this.card, {super.key});

  final Edition card;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    icon: const Icon(Icons.open_in_new),
    label: const Text('Открыть в Scryfall'),
    onPressed: () async {
      final page = card.scryfallPage;
      if (await AndroidActions.openScryfall(page)) return;
      await Clipboard.setData(ClipboardData(text: page.toString()));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ссылка на Scryfall скопирована')),
        );
      }
    },
  );
}

class CardFacts extends StatefulWidget {
  const CardFacts(this.printingId, {super.key});

  final String printingId;

  @override
  State<CardFacts> createState() => _CardFactsState();
}

class _CardFactsState extends State<CardFacts> {
  late Future<CardReference> reference = CardReferences.shared.get(
    widget.printingId,
  );

  void _retry() => setState(() {
    reference = CardReferences.shared.get(widget.printingId);
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<CardReference>(
    future: reference,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Padding(
          padding: EdgeInsets.only(top: 8),
          child: LinearProgressIndicator(
            semanticsLabel: 'Загрузка текста и правил карты',
          ),
        );
      }
      if (!snapshot.hasData) {
        return ListTile(
          title: const Text('Текст и правила карты недоступны'),
          subtitle: const Text(
            'Для первой загрузки понадобится подключение к Scryfall.',
          ),
          trailing: IconButton(
            onPressed: _retry,
            tooltip: 'Повторить загрузку',
            icon: const Icon(Icons.refresh),
          ),
        );
      }
      final card = snapshot.requireData;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final face in card.faces) _FaceText(face),
          _EditionFacts(card),
          _Rules(card.rulings, _retry),
          if (card.legalities.isNotEmpty) _Formats(card.legalities),
          const Padding(
            padding: EdgeInsets.only(top: 6, left: 12),
            child: Text(
              'Данные Scryfall',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ),
        ],
      );
    },
  );
}

class _FaceText extends StatelessWidget {
  const _FaceText(this.face);

  final CardFaceText face;

  @override
  Widget build(BuildContext context) {
    final details = [face.type, face.mana, face.stats].nonNulls.join(' · ');
    final rules = face.printed ?? face.oracle;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(face.name, style: Theme.of(context).textTheme.titleLarge),
          if (details.isNotEmpty)
            Text(details, style: const TextStyle(color: muted)),
          if (rules != null) ...[
            const SizedBox(height: 10),
            SelectableText(rules),
          ],
          if (face.printed != null &&
              face.oracle != null &&
              face.oracle != rules)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Актуальный текст Oracle'),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(face.oracle!),
                ),
              ],
            ),
          if (face.flavor case final text?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                text,
                style: const TextStyle(
                  color: muted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EditionFacts extends StatelessWidget {
  const _EditionFacts(this.card);

  final CardReference card;

  static const rarityNames = {
    'common': 'обычная',
    'uncommon': 'необычная',
    'rare': 'редкая',
    'mythic': 'мифическая',
    'special': 'особая',
    'bonus': 'бонусная',
  };

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (card.setName case final name?) Text('Выпуск · $name'),
        if (card.rarity case final rarity?)
          Text('Редкость · ${rarityNames[rarity] ?? rarity}'),
        if (card.manaValue case final value?) Text('Мановая ценность · $value'),
        if (card.artist case final artist?) Text('Художник · $artist'),
      ],
    ),
  );
}

class _Rules extends StatelessWidget {
  const _Rules(this.rulings, this.retry);

  final List<CardRuling>? rulings;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) {
    final list = rulings;
    if (list == null) {
      return ListTile(
        title: const Text('Разъяснения правил недоступны'),
        trailing: IconButton(
          onPressed: retry,
          tooltip: 'Повторить загрузку',
          icon: const Icon(Icons.refresh),
        ),
      );
    }
    if (list.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      title: Text('Разъяснения правил · ${list.length}'),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final ruling in list) ...[
          if (ruling.date case final date?) Text(date, style: codeText),
          SelectableText(ruling.text),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _Formats extends StatelessWidget {
  const _Formats(this.legalities);

  final Map<String, String> legalities;

  static const statusNames = {
    'legal': 'Разрешена',
    'not_legal': 'Недоступна',
    'restricted': 'Ограничена',
    'banned': 'Запрещена',
  };

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: const Text('Допуск в форматах'),
    children: [
      for (final format in legalities.entries)
        ListTile(
          dense: true,
          title: Text(
            '${format.key[0].toUpperCase()}${format.key.substring(1)}',
          ),
          trailing: Text(statusNames[format.value] ?? format.value),
        ),
    ],
  );
}
