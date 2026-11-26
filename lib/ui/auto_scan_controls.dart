import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';

import '../scan_cubit.dart';
import 'scanner_style.dart';
import 'style.dart';

extension AutoScanProfile on ScanMode {
  static bool get supportsFast =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  String get label => switch (this) {
    ScanMode.tray => 'Автоскан в лотке',
    ScanMode.fast => 'Быстрый',
    _ => 'Обычный автоскан',
  };
  IconData get icon => switch (this) {
    ScanMode.tray => Icons.inventory_2_outlined,
    ScanMode.fast => Icons.bolt_outlined,
    _ => Icons.center_focus_weak_rounded,
  };
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
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Semantics(
        excludeSemantics: true,
        toggled: running,
        label: profile.label,
        enabled: onToggle != null,
        onTap: onToggle,
        onLongPress: onChoose,
        child: TextButton(
          onPressed: onToggle,
          onLongPress: onChoose,
          style: TextButton.styleFrom(
            foregroundColor: running ? scanOrange : scanPaper,
            disabledForegroundColor: scanMuted,
            backgroundColor: running ? const Color(0xff463342) : null,
            minimumSize: const Size(64, 54),
            padding: const EdgeInsets.symmetric(horizontal: 6),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(profile.icon, size: 23),
                  Icon(
                    running ? Icons.pause : Icons.play_arrow_rounded,
                    size: 14,
                  ),
                ],
              ),
              Text(
                switch (profile) {
                  ScanMode.tray => 'В лотке',
                  ScanMode.fast => 'Быстрый',
                  _ => 'Автоскан',
                },
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
      IconButton(
        tooltip: 'Выбрать режим автоскана',
        onPressed: onChoose,
        icon: const Icon(Icons.arrow_drop_down),
      ),
    ],
  );
}

class AutoScanModeSheet extends StatelessWidget {
  const AutoScanModeSheet(this.profile, {super.key});

  final ScanMode profile;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHeading('Режим автоскана'),
        for (final mode in [
          ScanMode.tray,
          ScanMode.automatic,
          if (AutoScanProfile.supportsFast) ScanMode.fast,
        ])
          ListTile(
            leading: Icon(mode.icon),
            title: Text(mode.label),
            subtitle: Text(switch (mode) {
              ScanMode.tray => 'Card Slinger · фиксированная область',
              ScanMode.fast =>
                'В лотке · добавление по первому уверенному кадру',
              _ => 'Для карт в руке · выравнивание кадра',
            }),
            selected: mode == profile,
            trailing: mode == profile ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(context, mode),
          ),
      ],
    ),
  );
}
