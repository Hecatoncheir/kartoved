import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/strings.dart';
import '../data/catalog.dart';
import '../data/scan_names.dart';
import '../scan_cubit.dart';
import 'name_search.dart';
import 'lookup_page.dart';

class ScanTargetsPage extends StatefulWidget {
  const ScanTargetsPage(this.catalog, this.scan, {super.key});

  final Catalog catalog;
  final ScanCubit scan;

  @override
  State<ScanTargetsPage> createState() => _ScanTargetsPageState();
}

class _ScanTargetsPageState extends State<ScanTargetsPage> {
  final text = TextEditingController();
  late final search = NameSearch(ScanNames(widget.catalog).search);

  @override
  void dispose() {
    text.dispose();
    search.close();
    super.dispose();
  }

  void _clearSearch() {
    text.clear();
    search.search('');
  }

  @override
  Widget build(BuildContext context) => LookupPage(
    title: context.strings.targetCards,
    scanner: true,
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.strings.done),
      ),
    ],
    header: _searchField(),
    results: BlocSelector<ScanCubit, ScanSession, Set<String>>(
      bloc: widget.scan,
      selector: (state) => state.targets,
      builder: (context, targets) =>
          BlocBuilder<NameSearch, AsyncSnapshot<List<String>>>(
            bloc: search,
            builder: (context, state) => _results(state, targets),
          ),
    ),
  );

  Widget _searchField() => TextField(
    controller: text,
    textInputAction: TextInputAction.search,
    onChanged: search.search,
    decoration: InputDecoration(
      prefixIcon: const Icon(Icons.search),
      labelText: context.strings.cardName,
      suffixIcon: ValueListenableBuilder(
        valueListenable: text,
        builder: (context, value, child) => value.text.isEmpty
            ? const SizedBox.shrink()
            : IconButton(
                tooltip: context.strings.clearSearch,
                icon: const Icon(Icons.close),
                onPressed: _clearSearch,
              ),
      ),
    ),
  );

  Widget _results(AsyncSnapshot<List<String>> state, Set<String> targets) {
    if (search.query.isEmpty) return _selected(targets);
    if (state.hasError) {
      return Center(
        child: TextButton(
          onPressed: () => search.search(search.query),
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
    final names = state.data ?? const [];
    if (names.isEmpty) {
      return LookupHint(Icons.search_off_rounded, context.strings.noMatches);
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: names.length,
      itemBuilder: (context, index) {
        final name = names[index];
        final selected = targets.contains(name);
        return ListTile(
          title: Text(name),
          selected: selected,
          trailing: selected
              ? Tooltip(
                  message: context.strings.alreadyInList,
                  child: Icon(Icons.check),
                )
              : const Icon(Icons.add),
          onTap: selected
              ? null
              : () {
                  widget.scan.addTarget(name);
                  _clearSearch();
                },
        );
      },
    );
  }

  Widget _selected(Set<String> targets) {
    if (targets.isEmpty) {
      return LookupHint(
        Icons.saved_search_rounded,
        context.strings.enterTargetName,
      );
    }
    final names = targets.toList();
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: names.length,
      itemBuilder: (context, index) {
        final name = names[index];
        return ListTile(
          key: ValueKey(name),
          title: Text(name),
          trailing: IconButton(
            tooltip: context.strings.removeTarget(name),
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: () => widget.scan.removeTarget(name),
          ),
        );
      },
    );
  }
}
