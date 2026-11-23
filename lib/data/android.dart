import 'package:flutter/services.dart';

class AndroidActions {
  static const _channel = MethodChannel('kartoved/android');
  static Future<void> chime() async {
    try {
      await _channel.invokeMethod<void>('chime');
    } on PlatformException {
      /* Звук может быть отключён. */
    }
  }

  static Future<bool> saveCsv(String name, String csv) async =>
      await _channel.invokeMethod<bool>('saveCsv', {
        'name': name,
        'csv': csv,
      }) ??
      false;
}
