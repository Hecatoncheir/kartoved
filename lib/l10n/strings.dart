import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';
import 'generated/app_localizations_ru.dart';

final _russian = AppLocalizationsRu();

extension LocalizedContext on BuildContext {
  AppLocalizations get strings => AppLocalizations.of(this) ?? _russian;
}
