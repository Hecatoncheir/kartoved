import 'package:material_ui/material_ui.dart';

import '../scan_cubit.dart';
import 'style.dart';

extension AutoScanProfile on ScanMode {
  String get label =>
      this == ScanMode.tray ? 'Автоскан в лотке' : 'Обычный автоскан';
  IconData get icon => this == ScanMode.tray
      ? Icons.inventory_2_outlined
      : Icons.center_focus_weak_rounded;
}

class AutoScanButton extends StatelessWidget {
  const AutoScanButton({
    super.key,
    required this.profile,
    required this.running,
    required this.onToggle,
    required this.onChoose,
  });

  final ScanMode profile;
  final bool running;
  final VoidCallback? onToggle;
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) => Semantics(
    toggled: running,
    label: profile.label,
    hint: 'Удерживайте для выбора режима',
    child: TextButton(
      onPressed: onToggle,
      onLongPress: onChoose,
      style: TextButton.styleFrom(
        foregroundColor: running ? butter : paper,
        disabledForegroundColor: muted,
        backgroundColor: running ? amberSurface : null,
        minimumSize: const Size(86, 54),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      ),
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(profile.icon, size: 23),
                const SizedBox(width: 4),
                Icon(
                  running ? Icons.pause : Icons.play_arrow_rounded,
                  size: 14,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  profile == ScanMode.tray ? 'В лотке' : 'Автоскан',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 16),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class AutoScanModeSheet extends StatelessWidget {
  const AutoScanModeSheet(this.profile, {super.key});

  final ScanMode profile;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SheetHeading('Режим автоскана'),
      for (final mode in [ScanMode.tray, ScanMode.automatic])
        ListTile(
          leading: Icon(mode.icon),
          title: Text(mode.label),
          subtitle: Text(
            mode == ScanMode.tray
                ? 'Card Slinger · фиксированная область'
                : 'Для карт в руке · выравнивание кадра',
          ),
          selected: mode == profile,
          trailing: mode == profile ? const Icon(Icons.check) : null,
          onTap: () => Navigator.pop(context, mode),
        ),
    ],
  );
}
