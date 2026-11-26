import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/strings.dart';
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
    label: Text(context.strings.openScryfall),
    onPressed: () async {
      final page = card.scryfallPage;
      if (await AndroidActions.openScryfall(page)) return;
      await Clipboard.setData(ClipboardData(text: page.toString()));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.strings.scryfallLinkCopied)),
        );
      }
    },
  );
}

class CardFacts extends StatefulWidget {
  const CardFacts(this.edition, {super.key});

  final Edition edition;

  @override
  State<CardFacts> createState() => _CardFactsState();
}

class _CardFactsState extends State<CardFacts> {
  late Future<CardReference> reference = CardReferences.shared.get(
    widget.edition.id,
  );

  void _retry() => setState(() {
    reference = CardReferences.shared.get(widget.edition.id);
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<CardReference>(
    future: reference,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return Padding(
          padding: EdgeInsets.only(top: 8),
          child: LinearProgressIndicator(
            semanticsLabel: context.strings.loadingCardRules,
          ),
        );
      }
      if (!snapshot.hasData) {
        return ListTile(
          title: Text(context.strings.cardRulesUnavailable),
          subtitle: Text(context.strings.scryfallFirstLoad),
          trailing: IconButton(
            onPressed: _retry,
            tooltip: context.strings.retryLoading,
            icon: const Icon(Icons.refresh),
          ),
        );
      }
      final card = snapshot.requireData;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final face in card.faces)
            _FaceText(face, showPrinting: !widget.edition.needsPrinting),
          if (!widget.edition.needsPrinting) _EditionFacts(card),
          _Rules(card.rulings, _retry),
          if (card.legalities.isNotEmpty) _Formats(card.legalities),
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Text(
              context.strings.scryfallData,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _FaceText extends StatelessWidget {
  const _FaceText(this.face, {required this.showPrinting});

  final CardFaceText face;
  final bool showPrinting;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final details = [face.type, face.mana, face.stats].nonNulls.join(' · ');
    final rules = showPrinting ? face.printed ?? face.oracle : face.oracle;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(face.name, style: Theme.of(context).textTheme.titleLarge),
          if (details.isNotEmpty)
            Text(details, style: TextStyle(color: colors.onSurfaceVariant)),
          if (rules != null) ...[
            const SizedBox(height: 10),
            SelectableText(rules),
          ],
          if (face.printed != null &&
              face.oracle != null &&
              face.oracle != rules)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(context.strings.currentOracleText),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(face.oracle!),
                ),
              ],
            ),
          if (showPrinting && face.flavor != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                face.flavor!,
                style: TextStyle(
                  color: colors.onSurfaceVariant,
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

  String _rarity(BuildContext context, String rarity) => switch (rarity) {
    'common' => context.strings.rarityCommon,
    'uncommon' => context.strings.rarityUncommon,
    'rare' => context.strings.rarityRare,
    'mythic' => context.strings.rarityMythic,
    'special' => context.strings.raritySpecial,
    'bonus' => context.strings.rarityBonus,
    _ => rarity,
  };

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (card.setName case final name?) Text(context.strings.setName(name)),
        if (card.rarity case final rarity?)
          Text(context.strings.rarity(_rarity(context, rarity))),
        if (card.manaValue case final value?)
          Text(context.strings.manaValue(value)),
        if (card.artist case final artist?)
          Text(context.strings.artist(artist)),
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
        title: Text(context.strings.rulingsUnavailable),
        trailing: IconButton(
          onPressed: retry,
          tooltip: context.strings.retryLoading,
          icon: const Icon(Icons.refresh),
        ),
      );
    }
    if (list.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      title: Text(context.strings.rulingsCount(list.length)),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final ruling in list) ...[
          if (ruling.date case final date?)
            Text(
              date,
              style: TextStyle(
                fontFamily: monoFont,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
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

  String _status(BuildContext context, String status) => switch (status) {
    'legal' => context.strings.formatLegal,
    'not_legal' => context.strings.formatNotLegal,
    'restricted' => context.strings.formatRestricted,
    'banned' => context.strings.formatBanned,
    _ => status,
  };

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: Text(context.strings.formatLegality),
    children: [
      for (final format in legalities.entries)
        ListTile(
          dense: true,
          title: Text(
            '${format.key[0].toUpperCase()}${format.key.substring(1)}',
          ),
          trailing: Text(_status(context, format.value)),
        ),
    ],
  );
}
