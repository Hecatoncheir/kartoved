import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/strings.dart';
import '../data/catalog.dart';
import '../model.dart';
import 'collections.dart';
import 'card_destination.dart';
import 'name_search.dart';
import 'picture.dart';
import 'glass_sheet.dart';
import 'lookup_page.dart';
import 'style.dart';

class CatalogSearchPage extends StatefulWidget {
  const CatalogSearchPage(
    this.catalog,
    this.model, {
    super.key,
    this.initialMine = false,
  });
  final Catalog catalog;
  final AppModel model;
  final bool initialMine;
  @override
  State<CatalogSearchPage> createState() => _CatalogSearchPageState();
}

class _CatalogSearchPageState extends State<CatalogSearchPage> {
  final text = TextEditingController();
  late bool mine = widget.initialMine;
  late final search = NameSearch(
    (term) => widget.catalog.searchNames(term, limit: mine ? -1 : 61),
  );
  @override
  void dispose() {
    text.dispose();
    search.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LookupPage(
    title: context.strings.searchCards,
    header: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: text,
          autofocus: !widget.initialMine,
          onChanged: search.search,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: context.strings.cardName,
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: ValueListenableBuilder(
              valueListenable: text,
              builder: (_, value, _) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      tooltip: context.strings.clearSearch,
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        text.clear();
                        search.search('');
                      },
                    ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(context.strings.catalog)),
            ButtonSegment(value: true, label: Text(context.strings.myCards)),
          ],
          selected: {mine},
          onSelectionChanged: (choice) {
            setState(() => mine = choice.single);
            search.search(text.text);
          },
        ),
      ],
    ),
    results: BlocBuilder<NameSearch, AsyncSnapshot<List<String>>>(
      bloc: search,
      builder: _results,
    ),
  );

  Widget _results(BuildContext context, AsyncSnapshot<List<String>> state) {
    if (state.hasError) {
      return Center(
        child: TextButton(
          onPressed: () => search.search(text.text),
          child: Text(context.strings.retrySearch),
        ),
      );
    }
    if (state.connectionState == ConnectionState.waiting) {
      return const Align(
        alignment: Alignment.topCenter,
        child: LinearProgressIndicator(),
      );
    }
    if (mine) {
      return _OwnedResults(widget.model, search.query, state.data ?? const []);
    }
    if (!state.hasData) {
      return LookupHint(
        Icons.manage_search_rounded,
        context.strings.enterCardName,
      );
    }
    final names = state.requireData;
    if (names.isEmpty) {
      return LookupHint(Icons.search_off_rounded, context.strings.noMatches);
    }
    return _catalogNames(names);
  }

  Widget _catalogNames(List<String> names) => ListView.separated(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    itemCount: names.length,
    separatorBuilder: (_, _) => const Divider(height: 1),
    itemBuilder: (context, i) {
      if (i == 60) {
        return ListTile(subtitle: Text(context.strings.refineName));
      }
      return ListTile(
        title: Text(names[i]),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => _Printings(widget.catalog, names[i], widget.model),
          ),
        ),
      );
    },
  );
}

class _OwnedResults extends StatelessWidget {
  const _OwnedResults(this.model, this.query, this.aliases);
  final AppModel model;
  final String query;
  final List<String> aliases;

  Future<void> _open(BuildContext context, int folder, String name) async {
    FocusScope.of(context).unfocus();
    await model.select(folder);
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => BlocProvider.value(
          value: model,
          child: CollectionPage(initialName: name),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<AppModel, LibraryState>(
    bloc: model,
    builder: (_, state) {
      final matches = aliases.toSet();
      final term = query.toLowerCase().replaceAll('’', "'");
      final names =
          state.holdings.keys
              .where(
                (name) =>
                    matches.contains(name) ||
                    name.toLowerCase().replaceAll('’', "'").contains(term),
              )
              .toList()
            ..sort();
      if (names.isEmpty) {
        return LookupHint(
          Icons.collections_bookmark_outlined,
          context.strings.noCollectionMatches,
        );
      }
      return ListView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: names.length,
        itemBuilder: (context, index) {
          final name = names[index];
          final places = state.holdings[name]!;
          return ListTile(
            title: Text(name),
            trailing: Text('×${state.owned(name)}', style: codeText),
            subtitle: Wrap(
              spacing: 6,
              children: [
                for (final group in state.groups)
                  if (places[group.id] case final count?)
                    ActionChip(
                      label: Text('${group.name} · $count'),
                      onPressed: () => _open(context, group.id, name),
                    ),
              ],
            ),
          );
        },
      );
    },
  );
}

class _Printings extends StatefulWidget {
  const _Printings(this.catalog, this.name, this.model);
  final Catalog catalog;
  final String name;
  final AppModel model;
  @override
  State<_Printings> createState() => _PrintingsState();
}

class _PrintingsState extends State<_Printings> {
  late Future<List<Edition>> editions = widget.catalog.byName(widget.name);
  String filter = '';
  Future<void> _add(Edition card) async {
    final model = widget.model;
    final result = await showGlassSheet<CardSelection>(
      context,
      CardDestination(
        card: card,
        groups: model.state.groups,
        initialFolder: model.state.folder,
      ),
      library: true,
    );
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final strings = context.strings;
    try {
      await model.addFromCatalog(
        result.folderId!,
        result.card,
        result.quantity,
      );
      messenger.showSnackBar(
        SnackBar(
          duration: noticeDuration,
          content: Text(
            strings.addedToCollection(result.folderName, result.quantity),
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          duration: noticeDuration,
          content: Text(strings.addCardFailed),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => LookupPage(
    title: widget.name,
    header: TextField(
      decoration: InputDecoration(
        prefixIcon: Icon(Icons.filter_list),
        hintText: context.strings.printingNumberOrCode,
      ),
      onChanged: (value) => setState(() => filter = value.toLowerCase().trim()),
    ),
    results: FutureBuilder<List<Edition>>(
      future: editions,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: TextButton(
              onPressed: () =>
                  setState(() => editions = widget.catalog.byName(widget.name)),
              child: Text(context.strings.retryPrintings),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final terms = filter.split(RegExp(r'\s+'));
        final canAdd = widget.model.state.groups.isNotEmpty;
        final cards = snap.requireData
            .where((c) => terms.every(c.detail.toLowerCase().contains))
            .toList();
        if (cards.isEmpty) {
          return LookupHint(
            Icons.search_off_rounded,
            context.strings.noMatches,
          );
        }
        return ListView.builder(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount: cards.length + (canAdd ? 0 : 1),
          itemBuilder: (_, index) {
            if (!canAdd && index == 0) {
              return Padding(
                padding: EdgeInsets.all(12),
                child: Text(context.strings.createCollectionFirst),
              );
            }
            final card = cards[canAdd ? index : index - 1];
            return ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: SizedBox(
                  width: 40,
                  height: 54,
                  child: CardPicture(card, slot: index),
                ),
              ),
              title: Text(card.detail, style: codeText),
              subtitle: card.foil ? Text(context.strings.foilOnly) : null,
              trailing: canAdd ? const Icon(Icons.add_circle_outline) : null,
              onTap: canAdd ? () => _add(card) : null,
            );
          },
        );
      },
    ),
  );
}
