import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import 'style.dart';

class AlbumHeader extends StatefulWidget {
  const AlbumHeader({
    super.key,
    required this.albums,
    required this.cards,
    required this.onScan,
  });

  final int albums;
  final int cards;
  final VoidCallback? onScan;

  @override
  State<AlbumHeader> createState() => _AlbumHeaderState();
}

class _AlbumHeaderState extends State<AlbumHeader>
    with SingleTickerProviderStateMixin {
  late final glow = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      glow.stop();
    } else if (!glow.isAnimating) {
      glow.repeat();
    }
  }

  @override
  void dispose() {
    glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, bounds) {
      final compact = bounds.maxWidth < 550;
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/design/hero.webp',
                fit: BoxFit.cover,
                alignment: compact ? const Alignment(.62, 0) : Alignment.center,
                excludeFromSemantics: true,
              ),
            ),
            Positioned.fill(
              child: RepaintBoundary(child: CustomPaint(painter: _Lamp(glow))),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      dark,
                      Color(0xe81d2021),
                      Color(0x901d2021),
                      Color(0x081d2021),
                    ],
                    stops: [0, .23, .54, .84],
                  ),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: compact ? 216 : 250),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.all(compact ? 20 : 34),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: compact ? 205 : 560,
                        ),
                        child: Text(
                          'Мои коллекции',
                          style: TextStyle(
                            color: paper,
                            fontFamily: headingFont,
                            fontSize: compact ? 34 : 47,
                            height: 1.04,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 14,
                        runSpacing: 4,
                        children: [
                          _LibraryTotal('Альбомы', widget.albums),
                          _LibraryTotal('Карты', widget.cards),
                        ],
                      ),
                      const SizedBox(height: 17),
                      FilledButton.icon(
                        onPressed: widget.onScan,
                        icon: const Icon(Icons.center_focus_strong),
                        label: const Text('Сканировать карту'),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _LibraryTotal extends StatelessWidget {
  const _LibraryTotal(this.label, this.count);

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      text: '$label ',
      children: [
        TextSpan(
          text: '$count',
          style: const TextStyle(
            fontFamily: monoFont,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
    style: const TextStyle(color: paper),
  );
}

class _Lamp extends CustomPainter {
  _Lamp(this.drift) : super(repaint: drift);

  final Animation<double> drift;

  @override
  void paint(Canvas canvas, Size size) {
    final phase = drift.value * 2 * math.pi;
    final center = Offset(
      (.76 + .14 * math.cos(phase)) * size.width,
      (.26 + .20 * math.sin(phase)) * size.height,
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(center, size.width * .51, [
          butter.withValues(alpha: .24),
          butter.withValues(alpha: 0),
        ]),
    );
  }

  @override
  bool shouldRepaint(_Lamp old) => old.drift != drift;
}

class AlbumShelf extends StatelessWidget {
  const AlbumShelf(this.groups, this.onOpen, {super.key});

  final List<CardGroup> groups;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final height = 131 + 3 * MediaQuery.textScalerOf(context).scale(16);
      final shelf = constraints.crossAxisExtent < 600
          ? SliverToBoxAdapter(
              child: SizedBox(
                height: height,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: groups.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) => SizedBox(
                    width: (constraints.crossAxisExtent * .41).clamp(143, 220),
                    child: _tile(index),
                  ),
                ),
              ),
            )
          : SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 340,
                mainAxisExtent: height + 40,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: groups.length,
              itemBuilder: (_, index) => _tile(index),
            );
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        builder: (_, value, child) =>
            SliverOpacity(opacity: value, sliver: child),
        child: shelf,
      );
    },
  );

  Widget _tile(int index) {
    final group = groups[index];
    return _AlbumTile(group, () => onOpen(group.id), key: ValueKey(group.id));
  }
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile(this.group, this.open, {super.key});

  static const covers = ['forest', 'dragon', 'island'];
  final CardGroup group;
  final VoidCallback open;

  @override
  Widget build(BuildContext context) {
    final cover = covers[(group.id - 1) % covers.length];
    final titleHeight = MediaQuery.textScalerOf(context).scale(17) * 2.2;
    return Material(
      color: surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: outline),
        borderRadius: BorderRadius.circular(15),
      ),
      child: InkWell(
        onTap: open,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Ink.image(
                image: AssetImage('assets/design/$cover-cover.webp'),
                fit: BoxFit.cover,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 9, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(minHeight: titleHeight),
                          child: Text(
                            group.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: headingFont,
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                              height: 1.1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Карт: ${group.count}',
                          style: codeText.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: muted,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
