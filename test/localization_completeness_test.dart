import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/localization/app_localizations.dart';

void main() {
  test('English, Arabic, and German catalogs contain identical keys', () {
    expect(
      AppLocalizations.translationsComplete,
      isTrue,
      reason:
          'Every application-owned localization key must exist in English, '
          'Arabic, and German.',
    );
  });

  test('long durations stay human-readable in every supported locale', () {
    const duration = Duration(minutes: 955);

    expect(
      const AppLocalizations(Locale('en')).duration(duration),
      '15 hours 55 min',
    );
    expect(
      const AppLocalizations(Locale('ar')).duration(duration),
      '15 ساعة و55 دقيقة',
    );
    expect(
      const AppLocalizations(Locale('de')).duration(duration),
      '15 Stunden 55 Min.',
    );
  });
}
