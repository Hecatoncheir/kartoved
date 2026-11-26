import 'package:material_ui/material_ui.dart';

import '../l10n/strings.dart';
import '../data/catalog.dart';
import 'card_language.dart';
import 'glass_sheet.dart';
import 'style.dart';

Future<Edition?> showEditionPicker(
  BuildContext context,
  List<Edition> options,
  Edition selected, {
  bool library = false,
}) async {
  final choice = await showGlassSheet<Edition>(
    context,
    _EditionPicker(options, selected),
    library: library,
  );
  return choice?.withFoil(selected.foil || choice.foil);
}

class _EditionPicker extends StatefulWidget {
  const _EditionPicker(this.options, this.selected);
  final List<Edition> options;
  final Edition selected;

  @override
  State<_EditionPicker> createState() => _EditionPickerState();
}

class _EditionPickerState extends State<_EditionPicker> {
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  List<Edition> _matches() {
    final query = search.text.trim().toLowerCase();
    if (query.isEmpty) return widget.options;
    final terms = query.split(RegExp(r'\s+'));
    return widget.options.where((card) {
      final label = '${card.detail} ${cardLanguageName(context, card.language)}'
          .toLowerCase();
      return terms.every(label.contains);
    }).toList();
  }

  Widget _option(Edition card) {
    final colors = Theme.of(context).colorScheme;
    final current = widget.selected;
    final selected =
        !current.needsPrinting &&
        card.id == current.id &&
        card.language == current.language;
    final language = cardLanguageName(context, card.language);
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      selected: selected,
      selectedColor: colors.onSurface,
      selectedTileColor: colors.primary.withValues(alpha: .10),
      title: Text(
        card.detail,
        style: const TextStyle(
          fontFamily: monoFont,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        card.foil ? context.strings.detailFoilOnly(language) : language,
      ),
      trailing: selected
          ? Icon(Icons.check_rounded, color: colors.primary)
          : null,
      onTap: () => Navigator.pop(context, card),
    );
  }

  @override
  Widget build(BuildContext context) {
    final options = _matches();
    final colors = Theme.of(context).colorScheme;
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          context.strings.printingAndLanguage,
                          style: TextStyle(
                            fontFamily: headingFont,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      Text(
                        widget.selected.name,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: context.strings.close,
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: context.strings.printingNumberOrLanguage,
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: colors.surface.withValues(alpha: .65),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: context.strings.clearSearch,
                        onPressed: () => setState(search.clear),
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
          ),
        ),
        if (options.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.options.isEmpty
                    ? context.strings.noPrintingsForCard
                    : context.strings.noMatches,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: options.length,
            itemBuilder: (_, index) => _option(options[index]),
          ),
      ],
    );
  }
}
