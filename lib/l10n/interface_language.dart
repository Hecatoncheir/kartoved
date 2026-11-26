import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/browser.dart';

enum InterfaceLanguage {
  russian(Locale('ru'), 'Русский'),
  chinese(Locale('zh'), '简体中文'),
  english(Locale('en'), 'English');

  const InterfaceLanguage(this.locale, this.label);

  final Locale locale;
  final String label;

  static InterfaceLanguage fromCode(String? code) =>
      values
          .where((language) => language.locale.languageCode == code)
          .firstOrNull ??
      russian;
}

class InterfaceLanguageCubit extends Cubit<InterfaceLanguage> {
  InterfaceLanguageCubit(super.initialState);

  static const _channel = MethodChannel('kartoved/android');

  static Future<InterfaceLanguage> load() async {
    final language = InterfaceLanguage.fromCode(await _preference());
    if (kIsWeb) browserPageLanguage(language.locale.languageCode);
    return language;
  }

  Future<void> select(InterfaceLanguage language) async {
    if (language == state) return;
    emit(language);
    final code = language.locale.languageCode;
    if (kIsWeb) browserPageLanguage(code);
    await _preference(code);
  }

  static Future<String?> _preference([String? code]) async {
    if (kIsWeb) return browserInterfaceLanguage(code);
    try {
      return await _channel.invokeMethod<String>('interfaceLanguage', code);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
