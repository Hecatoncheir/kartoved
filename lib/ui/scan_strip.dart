import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import 'picture.dart';

class ScanStrip extends StatefulWidget {
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

class _ScanStripState extends State<ScanStrip>
    with SingleTickerProviderStateMixin {
  static const duration = Duration(milliseconds: 220);
  final scroll = ScrollController();
  late final insertion = AnimationController(
    vsync: this,
    duration: duration,
    value: 1,
  );
  late final reveal = insertion.drive(CurveTween(curve: Curves.easeOutCubic));

  @override
  void didUpdateWidget(ScanStrip old) {
    super.didUpdateWidget(old);
    final newest = widget.entries.firstOrNull?.sequence;
    if (newest == null || newest <= (old.entries.firstOrNull?.sequence ?? 0)) {
      return;
    }
    if (!MediaQuery.disableAnimationsOf(context)) insertion.forward(from: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) => _showNewest());
  }

  void _showNewest() {
    if (!mounted || !scroll.hasClients || scroll.offset == 0) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      scroll.jumpTo(0);
      return;
    }
    scroll.animateTo(0, duration: duration, curve: Curves.easeOutCubic);
  }

  int? _indexFor(Key key) {
    final sequence = (key as ValueKey<int>).value;
    final index = widget.entries.indexWhere(
      (entry) => entry.sequence == sequence,
    );
    return index < 0 ? null : index;
  }

  @override
  void dispose() {
    insertion.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    scrollDirection: Axis.horizontal,
    controller: scroll,
    itemCount: widget.entries.length,
    findItemIndexCallback: _indexFor,
    separatorBuilder: (_, _) => const SizedBox(width: 6),
    itemBuilder: (c, i) {
      final entry = widget.entries[i];
      final animation = i == 0 && !MediaQuery.disableAnimationsOf(c)
          ? reveal
          : kAlwaysCompleteAnimation;
      return SizeTransition(
        key: ValueKey(entry.sequence),
        axis: Axis.horizontal,
        alignment: Alignment.centerRight,
        sizeFactor: animation,
        child: FadeTransition(
          opacity: animation,
          child: SizedBox(
            width: 88,
            child: Column(
              children: [
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 63 / 88,
                    child: InkWell(
                      onTap: widget.edit == null
                          ? null
                          : () => widget.edit!(entry),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CardPicture(entry.card, slot: entry.sequence),
                          if (widget.pending.contains(entry.sequence))
                            Positioned(
                              top: 3,
                              right: 3,
                              child: Semantics(
                                label: 'Требует проверки',
                                child: const DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xfffabd2f),
                                    border: Border.fromBorderSide(
                                      BorderSide(color: Color(0xff282828)),
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
                if (entry.quantity == 1 ||
                    widget.pending.contains(entry.sequence))
                  Padding(
                    padding: const EdgeInsets.only(
                      top: ScanStrip.buttonSpacing,
                    ),
                    child: TextButton(
                      onPressed: widget.rescan == null
                          ? null
                          : () => widget.rescan!(entry),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: const Color(0xcc282828),
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
          ),
        ),
      );
    },
  );
}
