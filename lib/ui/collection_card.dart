import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../collection_rows.dart';
import 'picture.dart';
import 'style.dart';

const collectionCardRadius = Radius.circular(19);

class CollectionCard extends StatefulWidget {
  const CollectionCard({
    super.key,
    required this.item,
    required this.slot,
    required this.flagged,
    required this.selected,
    required this.select,
    required this.flag,
    required this.remove,
    required this.open,
  });
  final CollectionRow item;
  final int slot;
  final bool flagged, selected;
  final ValueChanged<bool> select;
  final VoidCallback flag, remove, open;

  @override
  State<CollectionCard> createState() => _CollectionCardState();
}

class _CollectionCardState extends State<CollectionCard>
    with SingleTickerProviderStateMixin {
  late final slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  static const corners = BorderRadius.all(collectionCardRadius);

  void _move(bool open) {
    final target = open ? 1.0 : 0.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      slide.value = target;
    } else {
      slide.animateTo(target, curve: Curves.easeOutCubic);
    }
  }

  void _settle(bool open) {
    widget.select(open);
    _move(open);
  }

  @override
  void didUpdateWidget(CollectionCard old) {
    super.didUpdateWidget(old);
    if (old.selected && !widget.selected) _move(false);
  }

  @override
  void dispose() {
    slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, box) {
      final width = math.min(148.0, box.maxWidth * .62);
      final face = _Face(
        widget.item,
        widget.slot,
        flagged: widget.flagged,
        toggle: widget.item.multiple
            ? widget.open
            : () => _settle(slide.value < .5),
      );
      return ClipRRect(
        borderRadius: corners,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xf5454439), Color(0xf832332c), Color(0xfc282828)],
            ),
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: corners,
            border: Border.all(
              color: widget.flagged ? butter : const Color(0x668d886e),
            ),
          ),
          child: widget.item.multiple
              ? GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.open,
                  child: face,
                )
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (_) {
                    slide.stop();
                    widget.select(true);
                  },
                  onHorizontalDragUpdate: (d) {
                    slide.value -= d.delta.dx / width;
                  },
                  onHorizontalDragEnd: (d) {
                    final speed = d.velocity.pixelsPerSecond.dx;
                    _settle(speed.abs() > 400 ? speed < 0 : slide.value > .45);
                  },
                  onHorizontalDragCancel: () => _settle(slide.value > .5),
                  child: AnimatedBuilder(
                    animation: slide,
                    child: face,
                    builder: (_, front) => Stack(
                      fit: StackFit.expand,
                      children: [
                        if (slide.value > 0)
                          Positioned(
                            right: width * (slide.value - 1),
                            top: 0,
                            bottom: 0,
                            width: width + 32,
                            child: DecoratedBox(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0x00494735),
                                    Color(0xdf494735),
                                    Color(0xf5584538),
                                    Color(0xff654039),
                                  ],
                                  stops: [0, .37, .70, 1],
                                ),
                              ),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: SizedBox(
                                  width: width,
                                  height: double.infinity,
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _Action(
                                        icon: widget.flagged
                                            ? Icons.flag_outlined
                                            : Icons.flag_rounded,
                                        label: widget.flagged
                                            ? 'Снять'
                                            : 'Флажок',
                                        tooltip: widget.flagged
                                            ? 'Снять флажок'
                                            : 'Поставить флажок',
                                        accent: butter,
                                        onTap: () {
                                          _settle(false);
                                          widget.flag();
                                        },
                                      ),
                                      _Action(
                                        icon: Icons.delete_outline_rounded,
                                        label: 'Убрать',
                                        tooltip: 'Убрать из коллекции',
                                        accent: const Color(0xfffbcec0),
                                        onTap: () {
                                          _settle(false);
                                          widget.remove();
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Transform.translate(
                          offset: Offset(-width * slide.value, 0),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: slide.value > 0
                                ? () => _settle(false)
                                : widget.open,
                            child: front,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      );
    },
  );
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.accent,
    required this.onTap,
  });
  final IconData icon;
  final String label, tooltip;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Material(
      type: MaterialType.transparency,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: accent),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(color: accent, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Face extends StatelessWidget {
  const _Face(
    this.item,
    this.slot, {
    required this.flagged,
    required this.toggle,
  });
  final CollectionRow item;
  final int slot;
  final bool flagged;
  final VoidCallback toggle;

  @override
  Widget build(BuildContext context) {
    final card = item.card;
    final action = item.multiple ? 'Выбрать вариант' : 'Действия с картой';
    final mark = item.multiple
        ? 'есть отмеченные варианты'
        : 'отмечена флажком';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: 74,
            child: ExcludeSemantics(
              child: Hero(
                tag: item.key,
                child: CardPicture(card, slot: slot),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  card.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: paper,
                    fontFamily: headingFont,
                    fontSize: 18,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.multiple
                      ? 'Варианты · ${item.variants.length}'
                      : [card.detail, if (card.foil) 'Фольга'].join('  ·  '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cream,
                    fontFamily: item.multiple ? bodyFont : monoFont,
                    fontSize: 13,
                    height: 1.18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Semantics(
            button: true,
            onTap: toggle,
            label:
                '$action ${card.name}, ×${item.quantity}${flagged ? ', $mark' : ''}',
            child: ExcludeSemantics(
              child: TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: EdgeInsets.zero,
                ),
                onPressed: toggle,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (flagged)
                      const Icon(Icons.flag_rounded, color: butter, size: 16),
                    Text(
                      '×${item.quantity}',
                      style: const TextStyle(
                        color: paper,
                        fontFamily: monoFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Icon(
                      item.multiple ? Icons.layers_outlined : Icons.more_horiz,
                      size: 18,
                      color: muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
