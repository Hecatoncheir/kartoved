import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import '../data/scan_names.dart';
import 'name_search.dart';

class ScanTargetPage extends StatefulWidget {
  const ScanTargetPage(this.catalog, this.selected, {super.key});

  final Catalog catalog;
  final String? selected;

  @override
  State<ScanTargetPage> createState() => _ScanTargetPageState();
}

class _ScanTargetPageState extends State<ScanTargetPage> {
  late final search = NameSearch(ScanNames(widget.catalog).search);

  @override
  void dispose() {
    search.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Искомая карта'),
      actions: [
        if (widget.selected != null)
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Сбросить'),
          ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: search.search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Название карты',
              ),
            ),
          ),
          Expanded(
            child: BlocBuilder<NameSearch, AsyncSnapshot<List<String>>>(
              bloc: search,
              builder: _results,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _results(BuildContext context, AsyncSnapshot<List<String>> state) {
    if (state.hasError) {
      return Center(
        child: TextButton(
          onPressed: () => search.search(search.query),
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
    final names = state.data ?? const [];
    if (names.isEmpty) {
      final text = search.query.isEmpty
          ? 'Введите название карты'
          : 'Совпадений нет';
      return Center(child: Text(text));
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: names.length,
      itemBuilder: (context, index) {
        final name = names[index];
        return ListTile(
          title: Text(name),
          selected: name == widget.selected,
          onTap: () => Navigator.pop(context, name),
        );
      },
    );
  }
}
