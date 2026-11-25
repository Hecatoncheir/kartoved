import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'data/catalog.dart';
import 'data/browser.dart';
import 'model.dart';
import 'ui/collections.dart';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'ui/library_style.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
  final model = AppModel(createCatalogStore(), History())..initialize();
  runApp(
    BlocProvider.value(
      value: model,
      child: MaterialApp(
        title: 'Картовед',
        theme: libraryTheme,
        debugShowCheckedModeBanner: false,
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const CollectionsPage(),
      ),
    ),
  );
}
