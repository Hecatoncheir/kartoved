import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import 'picture.dart';
import 'sheets.dart';
import 'style.dart';

class NameSearch extends Cubit<AsyncSnapshot<List<String>>> {
  NameSearch(this.catalog) : super(const AsyncSnapshot.nothing());
  final Catalog catalog;
  Timer? timer;
  String query = '';

  void search(String text) {
    timer?.cancel();
    query = text.trim();
    if (query.isEmpty) {
      emit(const AsyncSnapshot.nothing());
      return;
    }
    emit(const AsyncSnapshot.waiting());
    final term = query;
    timer = Timer(const Duration(milliseconds: 160), () => _read(term));
  }

  Future<void> _read(String term) async {
    try {
      final rows = await catalog.searchNames(term);
      if (!isClosed && query == term) {
        emit(AsyncSnapshot.withData(ConnectionState.done, rows));
      }
    } catch (error) {
      if (!isClosed && query == term) {
        emit(AsyncSnapshot.withError(ConnectionState.done, error));
      }
    }
  }

  @override
  Future<void> close() {
    timer?.cancel();
    return super.close();
  }
}

class CatalogSearchPage extends StatefulWidget {
  const CatalogSearchPage(this.catalog, {super.key});
  final Catalog catalog;
  @override
  State<CatalogSearchPage> createState() => _CatalogSearchPageState();
}

class _CatalogSearchPageState extends State<CatalogSearchPage> {
  final text = TextEditingController();
  late final search = NameSearch(widget.catalog);
  @override
  void dispose() {
    text.dispose();
    search.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: TextField(
        controller: text,
        autofocus: true,
        onChanged: search.search,
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(
          hintText: 'Название карты',
          border: InputBorder.none,
        ),
      ),
      actions: [
        ValueListenableBuilder(
          valueListenable: text,
          builder: (_, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: 'Очистить поиск',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    text.clear();
                    search.search('');
                  },
                ),
        ),
      ],
    ),
    body: SafeArea(
      child: BlocBuilder<NameSearch, AsyncSnapshot<List<String>>>(
        bloc: search,
        builder: (context, state) {
          if (state.hasError) {
            return Center(
              child: TextButton(
                onPressed: () => search.search(text.text),
                child: const Text('Повторить поиск'),
              ),
            );
          }
          if (state.connectionState == ConnectionState.waiting) {
            return const Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(),
            );
          }
          if (!state.hasData) {
            return const Center(child: Text('Введите название карты'));
          }
          final names = state.requireData;
          if (names.isEmpty) return const Center(child: Text('Совпадений нет'));
          return ListView.separated(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            itemCount: names.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              if (i == 60) {
                return const ListTile(
                  subtitle: Text('Уточните название, чтобы сузить поиск'),
                );
              }
              return ListTile(
                title: Text(names[i]),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => _Printings(widget.catalog, names[i]),
                  ),
                ),
              );
            },
          );
        },
      ),
    ),
  );
}

class _Printings extends StatefulWidget {
  const _Printings(this.catalog, this.name);
  final Catalog catalog;
  final String name;
  @override
  State<_Printings> createState() => _PrintingsState();
}

class _PrintingsState extends State<_Printings> {
  late Future<List<Edition>> editions = widget.catalog.byName(widget.name);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.name)),
    body: SafeArea(
      child: FutureBuilder<List<Edition>>(
        future: editions,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: TextButton(
                onPressed: () => setState(
                  () => editions = widget.catalog.byName(widget.name),
                ),
                child: const Text('Загрузить издания ещё раз'),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final cards = snap.requireData;
          return ListView.builder(
            itemCount: cards.length,
            itemBuilder: (context, i) {
              final card = cards[i];
              return ListTile(
                leading: SizedBox(width: 40, child: CardPicture(card, slot: i)),
                title: Text(card.detail),
                subtitle: card.foil ? const Text('Только фольга') : null,
                onTap: () => panel<void>(
                  context,
                  SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FractionallySizedBox(
                          widthFactor: .55,
                          child: AspectRatio(
                            aspectRatio: 63 / 88,
                            child: CardPicture(card),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SheetHeading(card.name),
                        Text(card.detail),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    ),
  );
}
