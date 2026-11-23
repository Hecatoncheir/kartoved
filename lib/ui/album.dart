import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import 'style.dart';

class AlbumHeader extends StatefulWidget {
  const AlbumHeader({super.key, required this.total, this.search});
  final int total;
  final VoidCallback? search;
  @override
  State<AlbumHeader> createState() => _AlbumHeaderState();
}

class _AlbumHeaderState extends State<AlbumHeader>
    with SingleTickerProviderStateMixin {
  late final drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      drift.stop();
    } else if (!drift.isAnimating) {
      drift.repeat();
    }
  }

  @override
  void dispose() {
    drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).height < 500;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(child: CustomPaint(painter: _Lamp(drift))),
          ),
          Padding(
            padding: EdgeInsets.all(compact ? 12 : 16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Коллекции',
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              color: paper,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Всего карт  ·  ${widget.total}',
                            style: const TextStyle(
                              color: paper,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!compact)
                      const ExcludeSemantics(
                        child: SizedBox(
                          width: 86,
                          height: 72,
                          child: FittedBox(child: Folio()),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Frost(
                  radius: 16,
                  child: TextButton.icon(
                    onPressed: widget.search,
                    icon: const Icon(Icons.search_rounded),
                    label: const Text('Найти карту по названию'),
                    style: TextButton.styleFrom(
                      foregroundColor: paper,
                      disabledForegroundColor: cream,
                      minimumSize: const Size(double.infinity, 46),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Lamp extends CustomPainter {
  _Lamp(this.drift) : super(repaint: drift);
  final Animation<double> drift;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawColor(const Color(0xff302d28), BlendMode.src);
    final phase = drift.value * 2 * math.pi;
    void glow(double x, double y, double radius, Color tint) {
      final center = Offset(x * size.width, y * size.height);
      final shader = ui.Gradient.radial(
        center,
        radius * size.width,
        [tint, tint.withValues(alpha: .5), tint.withValues(alpha: 0)],
        [0, .48, 1],
      );
      canvas.drawRect(rect, Paint()..shader = shader);
    }

    glow(
      .72 + .14 * math.cos(phase),
      .13 + .2 * math.sin(phase),
      .55,
      const Color(0xeeba812c),
    );
    glow(
      .85 - .18 * math.cos(phase),
      .97 - .16 * math.sin(phase),
      .50,
      const Color(0xc472a295),
    );
    glow(.02, .98, .45, const Color(0x9665484e));
    final sway = math.sin(phase);
    final pool = Path()
      ..moveTo(size.width * .55, -10)
      ..cubicTo(
        size.width * (.37 + .08 * sway),
        size.height * .52,
        size.width * (.84 - .1 * sway),
        size.height * .22,
        size.width * .73,
        size.height * (.68 + .12 * sway),
      )
      ..cubicTo(
        size.width * .68,
        size.height * .93,
        size.width * 1.15,
        size.height * 1.1,
        size.width * 1.12,
        -10,
      )
      ..close();
    canvas.drawPath(
      pool,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(size.width * .65, 0),
          rect.bottomRight,
          const [Color(0x80f6bd59), Color(0x8069b5a6)],
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
  }

  @override
  bool shouldRepaint(_Lamp old) => drift != old.drift;
}

const _covers = [
  (Color(0xff83a598), Icons.eco_outlined),
  (Color(0xffd79921), Icons.wb_sunny_outlined),
  (Color(0xffb99ab1), Icons.nights_stay_outlined),
  (Color(0xffd78b69), Icons.local_fire_department_outlined),
];

class AlbumTile extends StatelessWidget {
  const AlbumTile(this.group, this.open, {super.key});
  final CardGroup group;
  final VoidCallback open;
  @override
  Widget build(BuildContext context) {
    final (tint, mark) = _covers[(group.id - 1) % _covers.length];
    return Material(
      color: const Color(0xfff7ebcb),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xffd9c9a7)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          width: 37,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(6),
            border: const Border(
              left: BorderSide(width: 4, color: Color(0xff504945)),
            ),
            boxShadow: const [
              BoxShadow(color: Color(0xffd1c3a2), offset: Offset(2, 2)),
            ],
          ),
          child: Icon(mark, color: ink, size: 21),
        ),
        title: Text(
          group.name,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text('Карт: ${group.count}'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: open,
      ),
    );
  }
}
