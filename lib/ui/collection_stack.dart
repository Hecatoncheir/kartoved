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
  final menu = ValueNotifier<String?>(null);
  late final changes = Listenable.merge([scroll, menu]);

  @override
  void dispose() {
    scroll.dispose();
    menu.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, box) {
      const gap = 9.0;
      // Карта за двумя кромками уже на 14 точек с каждой стороны.
      final offsets = CollectionCard.rowOffsets(
        context,
        box.maxWidth - 28,
        widget.items,
        gap,
      );
      final count = widget.items.length;
      final naturalHeight = offsets.last - gap;
      // Scaffold передаёт сюда фактическую высоту кнопки вместе с системным отступом.
      final dock = MediaQuery.paddingOf(context).bottom;
      final bottomSpace = dock + 12;
      final contentHeight = naturalHeight + bottomSpace > box.maxHeight
          ? naturalHeight + bottomSpace + 20
          : box.maxHeight;
      return ClipRect(
        child: NotificationListener<ScrollStartNotification>(
          onNotification: (event) {
            if (event.dragDetails != null) menu.value = null;
            return false;
          },
          child: SingleChildScrollView(
            controller: scroll,
            child: SizedBox(
              height: contentHeight,
              width: box.maxWidth,
              child: AnimatedBuilder(
                animation: changes,
                builder: (_, _) {
                  final pixels = scroll.hasClients
                      ? scroll.offset.clamp(0.0, contentHeight - box.maxHeight)
                      : 0.0;
                  final front = _rowAt(offsets, pixels);
                  final progress =
                      front +
                      (pixels - offsets[front]) /
                          (offsets[front + 1] - offsets[front]);
                  final first = math.max(0, front - 2);
                  final end = _rowAt(offsets, pixels + box.maxHeight) + 1;
                  final rim = math.min(progress, 2.0) * 10;
                  // После верхней границы карта сдвигается всего на ширину кромки.
                  double depth(int i) =>
                      i == count - 1 ? 0 : (progress - i).clamp(0.0, 2.0);
                  double top(int i) {
                    final natural = offsets[i] - pixels;
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
                          offsets[i + 1] - offsets[i] - gap,
                          math.max(0.0, top(i + 1) - top(i)),
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

  int _rowAt(List<double> offsets, double y) {
    var low = 0, high = offsets.length - 1;
    while (high - low > 1) {
      final mid = (low + high) ~/ 2;
      if (offsets[mid] <= y) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return low;
  }

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
              flagged: flagged,
              selected: menu.value == key,
              select: (open) => menu.value = open ? key : null,
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
