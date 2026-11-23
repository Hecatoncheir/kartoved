import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import '../scan_decision.dart';
import 'sheets.dart';
import 'style.dart';

const _languages = {
  'ru': 'Русский',
  'en': 'Английский',
  'de': 'Немецкий',
  'fr': 'Французский',
  'es': 'Испанский',
  'it': 'Итальянский',
  'pt': 'Португальский',
  'ja': 'Японский',
  'ko': 'Корейский',
  'zhs': 'Китайский (упрощённый)',
  'zht': 'Китайский (традиционный)',
};

class BatchSheet extends StatefulWidget {
  const BatchSheet(this.catalog, this.initial, {super.key});
  final Catalog catalog;
  final BatchSettings initial;
  @override
  State<BatchSheet> createState() => _BatchSheetState();
}

class _BatchSheetState extends State<BatchSheet> {
  late String? language = widget.initial.language, set = widget.initial.setCode;
  Future<void> _pick(bool languages) async {
    final codes = languages
        ? widget.catalog.languages
        : widget.catalog.setCodes;
    final value = await panel<String>(context, _CodePicker(codes, languages));
    if (!mounted || value == null) return;
    setState(() {
      final code = value.isEmpty ? null : value;
      if (languages) {
        language = code;
      } else {
        set = code;
      }
    });
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHeading('Настройки стопки'),
        ListTile(
          title: const Text('Язык'),
          trailing: Text(
            _languages[language] ?? language?.toUpperCase() ?? 'Авто',
          ),
          onTap: () => _pick(true),
        ),
        ListTile(
          title: const Text('Издание'),
          trailing: Text(set?.toUpperCase() ?? 'Авто'),
          onTap: () => _pick(false),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            BatchSettings(language: language, setCode: set),
          ),
          child: const Text('Применить'),
        ),
      ],
    ),
  );
}

class _CodePicker extends StatefulWidget {
  const _CodePicker(this.load, this.languages);
  final Future<List<String>> Function() load;
  final bool languages;
  @override
  State<_CodePicker> createState() => _CodePickerState();
}

class _CodePickerState extends State<_CodePicker> {
  late Future<List<String>> options = widget.load();
  String query = '';
  String label(String code) =>
      (widget.languages ? _languages[code] : null) ?? code.toUpperCase();
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .60,
      child: Column(
        children: [
          TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: widget.languages ? 'Найти язык' : 'Найти код издания',
            ),
            onChanged: (v) => setState(() => query = v.trim().toLowerCase()),
          ),
          ListTile(
            title: const Text('Авто'),
            onTap: () => Navigator.pop(context, ''),
          ),
          Expanded(
            child: FutureBuilder<List<String>>(
              future: options,
              builder: (_, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: TextButton(
                      onPressed: () => setState(() => options = widget.load()),
                      child: const Text('Повторить загрузку'),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final values = snapshot.requireData
                    .where(
                      (s) => '$s ${label(s)}'.toLowerCase().contains(query),
                    )
                    .toList();
                if (values.isEmpty) {
                  return const Center(child: Text('Нет совпадений'));
                }
                return ListView.builder(
                  itemCount: values.length,
                  itemBuilder: (_, i) => ListTile(
                    title: Text(label(values[i])),
                    onTap: () => Navigator.pop(context, values[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
