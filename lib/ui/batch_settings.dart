import 'package:material_ui/material_ui.dart';

import '../l10n/strings.dart';
import 'card_language.dart';
import 'scanner_style.dart';
import 'style.dart';

enum BatchField {
  language,
  edition;

  String hint(BuildContext context) => this == language
      ? context.strings.findLanguage
      : context.strings.findSetCode;

  String label(BuildContext context, String? code) {
    if (code == null) return context.strings.automatic;
    return this == language
        ? cardLanguageName(context, code)
        : code.toUpperCase();
  }
}

class BatchPicker extends StatefulWidget {
  const BatchPicker({
    super.key,
    required this.field,
    required this.load,
    required this.selected,
    required this.onSelect,
  });
  final BatchField field;
  final Future<List<String>> Function() load;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  State<BatchPicker> createState() => _BatchPickerState();
}

class _BatchPickerState extends State<BatchPicker> {
  final search = TextEditingController();
  late Future<List<String>> options = _loadOptions();

  Future<List<String>> _loadOptions() async {
    final preferred = cardLanguageNames(context).keys;
    final field = widget.field;
    final codes = await widget.load();
    if (field == BatchField.edition) return codes;
    final remaining = codes.toSet();
    return [
      for (final code in preferred)
        if (remaining.remove(code)) code,
      ...remaining,
    ];
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Widget _option(String? code) {
    final selected = code == widget.selected;
    return ListTile(
      selected: selected,
      selectedColor: scanPaper,
      selectedTileColor: const Color(0x225f638b),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(
        widget.field.label(context, code),
        style: TextStyle(
          fontFamily: code != null && widget.field == BatchField.edition
              ? monoFont
              : bodyFont,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      trailing: selected
          ? const Icon(Icons.check_rounded, color: scanOrange)
          : null,
      onTap: () => widget.onSelect(code),
    );
  }

  Widget _results(AsyncSnapshot<List<String>> snapshot) {
    if (snapshot.hasError) {
      return SliverToBoxAdapter(
        child: TextButton(
          onPressed: () => setState(() => options = _loadOptions()),
          child: Text(context.strings.retryLoading),
        ),
      );
    }
    if (!snapshot.hasData) {
      return const SliverToBoxAdapter(child: LinearProgressIndicator());
    }
    final query = search.text.trim().toLowerCase();
    final codes = snapshot.requireData
        .where(
          (code) => '$code ${widget.field.label(context, code)}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
    if (codes.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: Text(context.strings.noMatchesShort)),
        ),
      );
    }
    return SliverList.builder(
      itemCount: codes.length,
      itemBuilder: (_, i) => _option(codes[i]),
    );
  }

  @override
  Widget build(BuildContext context) => CustomScrollView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    slivers: [
      SliverToBoxAdapter(
        child: TextField(
          controller: search,
          onChanged: (_) => setState(() {}),
          style: TextStyle(
            fontFamily: widget.field == BatchField.edition
                ? monoFont
                : bodyFont,
          ),
          decoration: InputDecoration(
            hintText: widget.field.hint(context),
            hintStyle: const TextStyle(fontFamily: bodyFont, color: scanMuted),
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: const Color(0x227d7290),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            suffixIcon: search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: context.strings.clearSearch,
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(search.clear),
                  ),
          ),
        ),
      ),
      SliverToBoxAdapter(child: _option(null)),
      FutureBuilder<List<String>>(
        future: options,
        builder: (_, data) => _results(data),
      ),
    ],
  );
}
