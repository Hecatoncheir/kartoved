typedef ScanProgress = void Function(ScanStage stage, List<double> card);
typedef CardRegion = ({double left, double top, double right, double bottom});

const titleRegion = (left: .09, top: .08, right: .815, bottom: .16);

enum ScanStage {
  card('Контур карты'),
  title('Читаю название', titleRegion),
  // Основное окно иллюстрации Oracle. Остальные форматы проверяются параллельно.
  artwork('Сверяю иллюстрацию', (
    left: .08,
    top: .115,
    right: .92,
    bottom: .553,
  )),
  details('Сверяю детали карты'),
  footer('Читаю нижнюю строку', (
    left: 0.0,
    top: 730 / 840,
    right: 440 / 600,
    bottom: 1.0,
  )),
  text('Уточняю по тексту', (left: 0.0, top: .53, right: 1.0, bottom: 1.0));

  const ScanStage(this.label, [this.region]);
  final String label;
  final CardRegion? region;

  List<double> focus(List<double> quad) {
    final bounds = region;
    if (bounds == null || quad.length != 8) return quad;
    return [
      for (final (x, y) in [
        cardPoint(quad, bounds.left, bounds.top),
        cardPoint(quad, bounds.right, bounds.top),
        cardPoint(quad, bounds.right, bounds.bottom),
        cardPoint(quad, bounds.left, bounds.bottom),
      ]) ...[x, y],
    ];
  }
}

(double, double) cardPoint(List<double> quad, double u, double v) => (
  _mix(_mix(quad[0], quad[2], u), _mix(quad[6], quad[4], u), v),
  _mix(_mix(quad[1], quad[3], u), _mix(quad[7], quad[5], u), v),
);

double _mix(double a, double b, double t) => a + (b - a) * t;
