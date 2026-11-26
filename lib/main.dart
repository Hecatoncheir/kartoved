import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import 'data/browser.dart';
import 'data/catalog.dart';
import 'l10n/generated/app_localizations.dart';
import 'l10n/interface_language.dart';
import 'l10n/strings.dart';
import 'model.dart';
import 'ui/collections.dart';
import 'ui/library_style.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
  final model = AppModel(createCatalogStore(), History())..initialize();
  final language = await InterfaceLanguageCubit.load();
  runApp(KartovedApp(model: model, language: language));
}

class KartovedApp extends StatelessWidget {
  const KartovedApp({super.key, required this.model, required this.language});

  final AppModel model;
  final InterfaceLanguage language;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => InterfaceLanguageCubit(language),
    child: BlocProvider.value(
      value: model,
      child: BlocBuilder<InterfaceLanguageCubit, InterfaceLanguage>(
        builder: (context, selected) => MaterialApp(
          onGenerateTitle: (context) => context.strings.appTitle,
          theme: libraryTheme,
          debugShowCheckedModeBanner: false,
          locale: selected.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: const CollectionsPage(),
        ),
      ),
    ),
  );
}
