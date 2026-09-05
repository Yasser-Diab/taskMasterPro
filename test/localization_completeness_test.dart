import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/localization/app_localizations.dart';

void main() {
  test('all client catalogs contain identical keys', () {
    expect(
      AppLocalizations.translationsComplete,
      isTrue,
      reason:
          'Every application-owned localization key must exist in English, '
          'Arabic, German, and Polish.',
    );
  });

  test(
    'Polish covers the visible dashboard, health, calendar and settings copy',
    () {
      const polish = AppLocalizations(Locale('pl'));

      expect(
        polish.format('dashboard_greeting_evening', {'userName': 'Yasser'}),
        'Dobry wieczór, Yasser',
      );
      expect(
        polish.text('dashboard_no_active_task'),
        'Żadne zadanie nie jest uruchomione',
      );
      expect(
        polish.text('health_recent_context'),
        'Dzisiejszy kontekst zdrowotny',
      );
      expect(polish.text('calendar_history'), 'Kalendarz i historia');
      expect(polish.text('settings_sections'), 'Ustawienia');
      expect(
        polish.text('sync_some_attention'),
        'Niektóre zmiany wymagają Twojej uwagi',
      );
    },
  );

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

  test('every statically referenced visible key resolves in all locales', () {
    final references = <String, Set<String>>{};
    final directKey = RegExp(
      r"\bl10n\.(?:text|format)\(\s*'([^']+)'",
      multiLine: true,
    );
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final match in directKey.allMatches(source)) {
        final key = match.group(1)!;
        if (key.contains(r'$')) continue;
        references.putIfAbsent(key, () => <String>{}).add(entity.path);
      }
    }

    final missing = <String>[];
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = AppLocalizations(locale);
      for (final entry in references.entries) {
        if (l10n.text(entry.key).contains('⟦')) {
          missing.add(
            '${locale.languageCode}.${entry.key} referenced by '
            '${entry.value.join(', ')}',
          );
        }
      }
    }
    expect(
      missing,
      isEmpty,
      reason: 'Visible localization calls must never expose a key or fallback.',
    );
  });
}
