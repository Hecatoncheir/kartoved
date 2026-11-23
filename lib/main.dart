import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'data/catalog.dart';
import 'model.dart';
import 'ui/scanner.dart';
import 'ui/style.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  final model = AppModel(CatalogStore(), History())..initialize();
  runApp(
    MaterialApp(
      title: 'Картовед',
      theme: kartovedTheme(),
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scanner(model),
    ),
  );
}
