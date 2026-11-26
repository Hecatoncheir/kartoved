import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/interface_language.dart';
import '../l10n/strings.dart';

class InterfaceLanguageButton extends StatelessWidget {
  const InterfaceLanguageButton({super.key});

  @override
  Widget build(BuildContext context) {
    final languageCubit = context.watch<InterfaceLanguageCubit?>();
    if (languageCubit == null) return const SizedBox.shrink();
    final current = languageCubit.state;
    return PopupMenuButton<InterfaceLanguage>(
      tooltip: context.strings.interfaceLanguage,
      icon: const Icon(Icons.language_rounded),
      initialValue: current,
      onSelected: languageCubit.select,
      itemBuilder: (_) => [
        for (final language in InterfaceLanguage.values)
          CheckedPopupMenuItem(
            value: language,
            checked: language == current,
            child: Text(language.label),
          ),
      ],
    );
  }
}
