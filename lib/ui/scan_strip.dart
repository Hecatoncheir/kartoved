import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import 'picture.dart';

class ScanStrip extends StatefulWidget {
  const ScanStrip(this.entries, this.edit, {super.key});
  final List<ScanEntry> entries;
  final ValueChanged<ScanEntry> edit;
  @override
  State<ScanStrip> createState() => _ScanStripState();
}

class _ScanStripState extends State<ScanStrip> {
  final scroll = ScrollController();
  @override
  void didUpdateWidget(ScanStrip old) {
    super.didUpdateWidget(old);
    if (old.entries.firstOrNull?.sequence ==
        widget.entries.firstOrNull?.sequence) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) {
        scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    scrollDirection: Axis.horizontal,
    controller: scroll,
    itemCount: widget.entries.length,
    separatorBuilder: (_, _) => const SizedBox(width: 6),
    itemBuilder: (c, i) {
      final entry = widget.entries[i];
      return AspectRatio(
        aspectRatio: 63 / 88,
        child: InkWell(
          key: ValueKey(entry.sequence),
          onTap: () => widget.edit(entry),
          child: CardPicture(entry.card),
        ),
      );
    },
  );
}
