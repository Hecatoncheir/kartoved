import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import 'picture.dart';
import 'style.dart';

typedef CardSelection = ({CardGroup folder, Edition card, int quantity});

class CardDestination extends StatefulWidget {
  const CardDestination({
    super.key,
    required this.card,
    required this.groups,
    required this.initialFolder,
    this.available,
  });
  final Edition card;
  final List<CardGroup> groups;
  final int initialFolder;
  final int? available;

  @override
  State<CardDestination> createState() => _CardDestinationState();
}

class _CardDestinationState extends State<CardDestination> {
  final copies = TextEditingController(text: '1');
  late int folder = widget.initialFolder;
  late bool foil = widget.card.foil;
  int? get quantity => int.tryParse(copies.text);
  bool get valid =>
      quantity != null &&
      quantity! > 0 &&
      (widget.available == null || quantity! <= widget.available!);

  @override
  void dispose() {
    copies.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final moving = widget.available != null;
    final pictureWidth = moving || MediaQuery.viewInsetsOf(context).bottom > 0
        ? 60.0
        : (MediaQuery.sizeOf(context).width * .36).clamp(60.0, 160.0);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(
                  width: pictureWidth,
                  height: pictureWidth * 88 / 63,
                  child: CardPicture(widget.card.withFoil(foil)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SheetHeading(widget.card.name),
                      Text(widget.card.detail, style: codeText),
                      if (moving) Text(foil ? 'Фольга' : 'Обычная'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              isExpanded: true,
              initialValue: folder,
              decoration: const InputDecoration(labelText: 'Коллекция'),
              items: [
                for (final group in widget.groups)
                  DropdownMenuItem(
                    value: group.id,
                    child: Text(group.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => folder = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: copies,
              style: const TextStyle(fontFamily: monoFont),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Количество',
                helperText: moving ? 'Доступно: ${widget.available}' : null,
              ),
              onChanged: (_) => setState(() {}),
              onTap: () => copies.selection = TextSelection(
                baseOffset: 0,
                extentOffset: copies.text.length,
              ),
            ),
            if (!moving)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(widget.card.foil ? 'Только фольга' : 'Фольга'),
                value: foil,
                onChanged: widget.card.foil
                    ? null
                    : (value) => setState(() => foil = value),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: !valid
                  ? null
                  : () => Navigator.pop<CardSelection>(context, (
                      folder: widget.groups.firstWhere((g) => g.id == folder),
                      card: widget.card.withFoil(foil),
                      quantity: quantity!,
                    )),
              icon: Icon(moving ? Icons.drive_file_move_outline : Icons.add),
              label: Text(moving ? 'Переместить' : 'В коллекцию'),
            ),
          ],
        ),
      ),
    );
  }
}
