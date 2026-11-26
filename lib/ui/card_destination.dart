import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/strings.dart';
import '../data/backup.dart' show maxCardQuantity;
import '../data/catalog.dart';
import 'library_style.dart';
import 'picture.dart';
import 'style.dart';

typedef CardSelection = ({
  int? folderId,
  String folderName,
  Edition card,
  int quantity,
});

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
  final int? initialFolder;
  final int? available;

  @override
  State<CardDestination> createState() => _CardDestinationState();
}

class _CardDestinationState extends State<CardDestination> {
  static const newCollection = 0;
  final copies = TextEditingController(text: '1');
  late int? folder =
      widget.groups.any((group) => group.id == widget.initialFolder)
      ? widget.initialFolder
      : widget.groups.firstOrNull?.id;
  String newName = '';
  late bool foil = widget.card.foil;

  bool get moving => widget.available != null;
  int? get quantity => int.tryParse(copies.text);
  bool get hasDestination => folder != null || (moving && newName.isNotEmpty);

  String? get quantityError {
    final count = quantity;
    if (count == null || count < 1) {
      return context.strings.positiveIntegerRequired;
    }
    if (count > maxCardQuantity) return context.strings.quantityTooLarge;
    final available = widget.available;
    if (available != null && count > available) {
      return context.strings.onlyAvailable(available);
    }
    return null;
  }

  void _setQuantity(int value) {
    final text = value.toString();
    setState(
      () => copies.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );
  }

  void _submit() {
    final name = folder == null
        ? newName
        : widget.groups.firstWhere((group) => group.id == folder).name;
    Navigator.pop<CardSelection>(context, (
      folderId: folder,
      folderName: name,
      card: widget.card.withFoil(foil),
      quantity: quantity!,
    ));
  }

  @override
  void dispose() {
    copies.dispose();
    super.dispose();
  }

  Widget _header() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: SizedBox(
          width: 54,
          height: 75,
          child: CardPicture(widget.card.withFoil(foil), tilt: false),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                widget.card.name,
                style: const TextStyle(
                  fontFamily: headingFont,
                  fontSize: 22,
                  height: 1.12,
                  fontWeight: FontWeight.w900,
                  color: libraryInk,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.card.detail,
              style: const TextStyle(
                fontFamily: monoFont,
                fontSize: 13,
                color: libraryMuted,
              ),
            ),
            if (moving)
              Text(
                foil ? context.strings.foil : context.strings.nonFoil,
                style: const TextStyle(color: libraryMuted),
              ),
          ],
        ),
      ),
      IconButton(
        tooltip: context.strings.close,
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.close),
      ),
    ],
  );

  InputDecoration _field(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: const Color(0xaafffaff),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
  );

  Widget _folderField() => DropdownButtonFormField<int>(
    isExpanded: true,
    initialValue: folder ?? newCollection,
    decoration: _field(context.strings.collection),
    items: [
      for (final group in widget.groups)
        DropdownMenuItem(
          value: group.id,
          child: Text(group.name, overflow: TextOverflow.ellipsis),
        ),
      if (moving)
        DropdownMenuItem(
          value: newCollection,
          child: Text(context.strings.createCollection),
        ),
    ],
    onChanged: (value) =>
        setState(() => folder = value == newCollection ? null : value),
  );

  Widget _quantityField() {
    final count = quantity ?? 0;
    final limit = widget.available ?? maxCardQuantity;
    return TextField(
      controller: copies,
      style: const TextStyle(fontFamily: monoFont),
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: _field(context.strings.quantity).copyWith(
        errorText: copies.text.isEmpty ? null : quantityError,
        errorMaxLines: 2,
        prefixIcon: IconButton(
          tooltip: context.strings.decreaseQuantity,
          onPressed: count > 1 ? () => _setQuantity(count - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        suffixIcon: IconButton(
          tooltip: context.strings.increaseQuantity,
          onPressed: count < limit ? () => _setQuantity(count + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ),
      onChanged: (_) => setState(() {}),
      onTap: () => copies.selection = TextSelection(
        baseOffset: 0,
        extentOffset: copies.text.length,
      ),
    );
  }

  Widget _fields() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _header(),
      const SizedBox(height: 18),
      if (widget.groups.isNotEmpty) _folderField(),
      if (moving && folder == null) ...[
        if (widget.groups.isNotEmpty) const SizedBox(height: 14),
        TextFormField(
          initialValue: newName,
          maxLength: 80,
          textInputAction: TextInputAction.next,
          decoration: _field(context.strings.newCollectionName),
          onChanged: (value) => setState(() => newName = value.trim()),
        ),
      ],
      const SizedBox(height: 16),
      _quantityField(),
      if (widget.available case final available? when available > 1)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: quantity == available
                ? null
                : () => _setQuantity(available),
            child: Text(context.strings.selectAllCount(available)),
          ),
        ),
      if (!moving)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            widget.card.foil ? context.strings.foilOnly : context.strings.foil,
          ),
          value: foil,
          onChanged: widget.card.foil
              ? null
              : (value) => setState(() => foil = value),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final action = LibraryActionButton(
      label: switch ((moving, folder)) {
        (false, _) => context.strings.addToCollection,
        (true, null) => context.strings.createAndMove,
        _ => context.strings.move,
      },
      icon: moving ? Icons.drive_file_move_outline : Icons.add,
      onPressed: hasDestination && quantityError == null ? _submit : null,
    );
    return LayoutBuilder(
      builder: (_, constraints) {
        final fields = Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: _fields(),
        );
        if (constraints.maxHeight < 220) {
          return ListView(children: [fields, action]);
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(child: SingleChildScrollView(child: fields)),
            Padding(padding: const EdgeInsets.only(top: 8), child: action),
          ],
        );
      },
    );
  }
}
