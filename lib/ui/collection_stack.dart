import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import '../collection_rows.dart';
import 'collection_card.dart';

class CollectionStack extends StatefulWidget {
  const CollectionStack({
    super.key,
    required this.items,
    required this.flags,
    required this.onFlag,
    required this.onRemove,
    required this.onOpen,
  });
  final List<CollectionRow> items;
  final Set<String> flags;
  final void Function(Edition, bool) onFlag;
  final ValueChanged<Edition> onRemove;
  final ValueChanged<CollectionRow> onOpen;
  @override
  State<CollectionStack> createState() => _CollectionStackState();
}

class _CollectionStackState extends State<CollectionStack> {
  final scroll = ScrollController();
  String? menu;

  void _select(String? key) {
    if (menu != key) setState(() => menu = key);
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, box) {
      final scale = MediaQuery.textScalerOf(context);
      final height = math.max(
        98.0,
        32 + 2.2 * scale.scale(18) + 2.36 * scale.scale(13),
      );
      final step = height + 9;
      final count = widget.items.length;
      final naturalHeight = count * step - 9;
      // Scaffold передаёт сюда фактическую высоту кнопки вместе с системным отступом.
      final dock = MediaQuery.paddingOf(context).bottom;
      final bottomSpace = dock + 12;
      final contentHeight = naturalHeight + bottomSpace > box.maxHeight
          ? naturalHeight + bottomSpace + 20
          : box.maxHeight;
      return ClipRect(
        child: NotificationListener<ScrollStartNotification>(
          onNotification: (event) {
            if (event.dragDetails != null) _select(null);
            return false;
          },
          child: SingleChildScrollView(
            controller: scroll,
            child: SizedBox(
              height: contentHeight,
              width: box.maxWidth,
              child: AnimatedBuilder(
                animation: scroll,
                builder: (_, _) {
                  final pixels = scroll.hasClients
                      ? scroll.offset.clamp(0.0, contentHeight - box.maxHeight)
                      : 0.0;
                  final front = (pixels / step).floor();
                  final first = math.max(0, front - 2);
                  final end = math.min(
                    count,
                    front + (box.maxHeight / step).ceil() + 1,
                  );
                  final rim = math.min(pixels / step, 2.0) * 10;
                  // После верхней границы карта сдвигается всего на ширину кромки.
                  double depth(int i) =>
                      i == count - 1 ? 0 : (pixels / step - i).clamp(0.0, 2.0);
                  double top(int i) {
                    final natural = i * step - pixels;
                    if (i == count - 1) return rim + natural;
                    return rim + math.max(0.0, natural) - 10 * depth(i);
                  }

                  return Stack(
                    children: [
                      for (int i = first; i < end; i++)
                        _position(
                          i,
                          pixels + top(i),
                          7 * depth(i),
                          height,
                          (top(i + 1) - top(i)).clamp(0.0, height),
                          7 * (depth(i) - depth(i + 1)),
                          depth(i) >= 1,
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _position(
    int i,
    double y,
    double inset,
    double height,
    double exposed,
    double overhang,
    bool tucked,
  ) {
    final item = widget.items[i];
    final key = item.key;
    final flagged = item.variants.any(
      (v) => widget.flags.contains(v.card.printingKey),
    );
    return Positioned(
      key: ValueKey(key),
      top: y,
      left: inset,
      right: inset,
      height: height,
      child: ExcludeSemantics(
        excluding: tucked,
        child: IgnorePointer(
          ignoring: tucked,
          child: ClipPath(
            clipBehavior: exposed >= height ? Clip.none : Clip.antiAlias,
            clipper: _StackEdge(exposed, overhang),
            child: CollectionCard(
              item: item,
              open: () => widget.onOpen(item),
              slot: i,
              flagged: flagged,
              selected: menu == key,
              select: (open) => _select(open ? key : null),
              flag: () => widget.onFlag(item.card, !flagged),
              remove: () => widget.onRemove(item.card),
            ),
          ),
        ),
      ),
    );
  }
}

// Кромка повторяет дугу передней карты.
class _StackEdge extends CustomClipper<Path> {
  const _StackEdge(this.top, this.overhang);
  final double top, overhang;

  @override
  Path getClip(Size size) {
    final next = Rect.fromLTWH(
      -overhang,
      top,
      size.width + 2 * overhang,
      size.height,
    );
    return Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(RRect.fromRectAndRadius(next, collectionCardRadius)),
    );
  }

  @override
  bool shouldReclip(_StackEdge old) =>
      old.top != top || old.overhang != overhang;
}
