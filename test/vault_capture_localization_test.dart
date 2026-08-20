import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/localization/app_localizations.dart';

void main() {
  test('vault capture and device unlock copy is localized without mixing', () {
    const keys = <String>[
      'browser_vault_capture_fields_not_found',
      'vault_review_captured_sign_in',
      'vault_allow_device_auth',
      'vault_device_key_detail',
    ];
    final values = <String, List<String>>{};
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = AppLocalizations(locale);
      values[locale.languageCode] = [for (final key in keys) l10n.text(key)];
    }

    for (final translated in values.values.expand((value) => value)) {
      expect(translated, isNotEmpty);
      expect(translated, isNot(contains('⟦')));
    }
    expect(values['ar']!.join(' '), contains('الجهاز'));
    expect(values['de']!.join(' '), contains('Gerät'));
    expect(values['en']!.join(' '), contains('device'));
    expect(values['ar'], isNot(values['en']));
    expect(values['de'], isNot(values['en']));
  });
}
