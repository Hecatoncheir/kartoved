import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/strings.dart';
import '../collection_rows.dart';
import '../data/catalog.dart';
import '../model.dart';
import 'name_search.dart';
import 'collection_detail.dart';
import 'collection_stack.dart';
import 'library_style.dart';

class CollectionBrowser extends StatefulWidget {
  const CollectionBrowser({
    super.key,
    required this.items,
    required this.flags,
    required this.catalog,
    required this.onFlag,
    required this.onRemove,
    this.initialName,
  });
  final List<CardCount> items;
  final String? initialName;
  final Set<String> flags;
  final Catalog? catalog;
  final void Function(Edition, bool) onFlag;
  final ValueChanged<Edition> onRemove;
  @override
  State<CollectionBrowser> createState() => _CollectionBrowserState();
}

class _CollectionBrowserState extends State<CollectionBrowser> {
  late final search = NameSearch(
    (term) =>
        widget.catalog?.searchNames(term, limit: -1) ??
        Future.value(<String>[]),
  );
  bool editing = false, flagsOnly = false, grouped = false;
  late String? focusName = widget.initialName;

  @override
  void didUpdateWidget(CollectionBrowser old) {
    super.didUpdateWidget(old);
    if (old.catalog != widget.catalog && search.query.isNotEmpty) {
      search.search(search.query);
    }
  }

  @override
  void dispose() {
    search.close();
    super.dispose();
  }

  void _open(CollectionRow row) {
    FocusScope.of(context).unfocus();
    final model = context.read<AppModel>();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            BlocProvider.value(value: model, child: CollectionDetail(row)),
      ),
    );
  }

  Widget _toolbar() => LibraryGlass(
    radius: 16,
    child: Row(
      children: [
        Expanded(
          child: editing
              ? TextField(
                  autofocus: true,
                  onChanged: (text) => setState(() => search.search(text)),
                  style: const TextStyle(color: libraryInk),
                  cursorColor: libraryInk,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    hintText: context.strings.cardName,
                    hintStyle: TextStyle(color: libraryMuted),
                    border: InputBorder.none,
                  ),
                )
              : TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: libraryInk,
                    alignment: Alignment.centerLeft,
                  ),
                  onPressed: () => setState(() => editing = true),
                  icon: const Icon(Icons.search),
                  label: Text(context.strings.findCard),
                ),
        ),
        if (editing)
          IconButton(
            color: libraryInk,
            tooltip: context.strings.closeSearch,
            icon: const Icon(Icons.close),
            onPressed: () {
              search.search('');
              setState(() => editing = false);
            },
          ),
        IconButton(
          isSelected: flagsOnly,
          tooltip: context.strings.flaggedOnly,
          color: flagsOnly ? const Color(0xff844202) : libraryMuted,
          icon: Icon(flagsOnly ? Icons.flag_rounded : Icons.flag_outlined),
          onPressed: () => setState(() => flagsOnly = !flagsOnly),
        ),
        IconButton(
          isSelected: grouped,
          tooltip: context.strings.groupByName,
          color: grouped ? const Color(0xff844202) : libraryMuted,
          icon: Icon(grouped ? Icons.layers : Icons.layers_outlined),
          onPressed: () => setState(() => grouped = !grouped),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _toolbar(),
      if (focusName case final name?)
        Align(
          alignment: Alignment.centerLeft,
          child: InputChip(
            label: Text(name, overflow: TextOverflow.ellipsis),
            deleteButtonTooltipMessage: context.strings.showAllCards,
            onDeleted: () => setState(() => focusName = null),
          ),
        ),
      const SizedBox(height: 8),
      Expanded(
        child: BlocBuilder<NameSearch, AsyncSnapshot<List<String>>>(
          bloc: search,
          builder: (_, result) {
            final term = search.query.toLowerCase().replaceAll('’', "'");
            final names = result.data?.toSet() ?? const <String>{};
            final visible = widget.items.where((item) {
              if (focusName != null && item.card.name != focusName) {
                return false;
              }
              if (flagsOnly && !widget.flags.contains(item.card.printingKey)) {
                return false;
              }
              return item.card.name
                      .toLowerCase()
                      .replaceAll('’', "'")
                      .contains(term) ||
                  names.contains(item.card.name);
            });
            final rows = CollectionRow.from(visible, groupNames: grouped);
            if (rows.isNotEmpty) {
              return CollectionStack(
                key: ValueKey((term, flagsOnly, grouped)),
                items: rows,
                flags: widget.flags,
                onFlag: widget.onFlag,
                onRemove: widget.onRemove,
                onOpen: _open,
              );
            }
            if (result.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: libraryMuted),
              );
            }
            if (result.hasError) {
              return Center(
                child: TextButton(
                  onPressed: () => search.search(search.query),
                  child: Text(
                    context.strings.retrySearch,
                    style: TextStyle(color: libraryInk),
                  ),
                ),
              );
            }
            return Center(
              child: Text(
                flagsOnly && term.isEmpty
                    ? context.strings.noFlaggedCards
                    : context.strings.noMatches,
                style: const TextStyle(color: libraryMuted),
              ),
            );
          },
        ),
      ),
    ],
  );
}
