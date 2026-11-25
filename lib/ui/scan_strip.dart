import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import 'picture.dart';
import 'scanner_style.dart';

class ScanStrip extends StatefulWidget {
  static const limit = 10;
  static const buttonSpacing = 8.0;
  const ScanStrip(
    this.entries,
    this.edit, {
    super.key,
    this.pending = const {},
    this.rescan,
  });
  final List<ScanEntry> entries;
  final Set<int> pending;
  final ValueChanged<ScanEntry>? edit;
  final ValueChanged<ScanEntry>? rescan;
  @override
  State<ScanStrip> createState() => _ScanStripState();
}

class _ScanStripState extends State<ScanStrip> {
  final scroll = ScrollController();

  @override
  void didUpdateWidget(ScanStrip old) {
    super.didUpdateWidget(old);
    final newest = widget.entries.firstOrNull?.sequence;
    if (newest == null || newest <= (old.entries.firstOrNull?.sequence ?? 0)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients && scroll.offset != 0) scroll.jumpTo(0);
    });
  }

  int? _indexFor(Key key) {
    final sequence = (key as ValueKey<int>).value;
    for (final (index, entry) in widget.entries.take(ScanStrip.limit).indexed) {
      if (entry.sequence == sequence) return index;
    }
    return null;
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    scrollDirection: Axis.horizontal,
    controller: scroll,
    itemCount: math.min(widget.entries.length, ScanStrip.limit),
    findItemIndexCallback: _indexFor,
    separatorBuilder: (_, _) => const SizedBox(width: 6),
    itemBuilder: (c, i) {
      final entry = widget.entries[i];
      return SizedBox(
        key: ValueKey(entry.sequence),
        width: 108,
        child: Column(
          children: [
            Expanded(
              child: ScanSurface(
                radius: 10,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: InkWell(
                    onTap: widget.edit == null
                        ? null
                        : () => widget.edit!(entry),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CardPicture(entry.card, tilt: false, fit: BoxFit.cover),
                        if (widget.pending.contains(entry.sequence))
                          Positioned(
                            top: 3,
                            right: 3,
                            child: Semantics(
                              label: 'Требует проверки',
                              child: const DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: scanOrange,
                                  border: Border.fromBorderSide(
                                    BorderSide(color: scanInk),
                                  ),
                                ),
                                child: SizedBox.square(dimension: 12),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (entry.quantity == 1 || widget.pending.contains(entry.sequence))
              Padding(
                padding: const EdgeInsets.only(top: ScanStrip.buttonSpacing),
                child: TextButton(
                  onPressed: widget.rescan == null
                      ? null
                      : () => widget.rescan!(entry),
                  style: TextButton.styleFrom(
                    foregroundColor: scanPaper,
                    backgroundColor: const Color(0x33252242),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(80, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Переснять',
                    semanticsLabel: 'Переснять ${entry.card.name}',
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
