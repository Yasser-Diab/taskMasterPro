import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('authentication emails carry TaskMaster Pro identity', () {
    final config = File('supabase/config.toml').readAsStringSync();
    final templates = <String, String>{
      'confirmation': 'ConfirmationURL',
      'recovery': 'ConfirmationURL',
      'magic_link': 'ConfirmationURL',
      'invite': 'ConfirmationURL',
      'email_change': 'NewEmail',
      'reauthentication': 'Token',
    };

    for (final entry in templates.entries) {
      expect(
        config,
        contains('[auth.email.template.${entry.key}]'),
        reason: '${entry.key} must be configured for local and CLI workflows.',
      );
      expect(
        config,
        contains('content_path = "./supabase/templates/${entry.key}.html"'),
      );
      final html = File(
        'supabase/templates/${entry.key}.html',
      ).readAsStringSync();
      expect(html, contains('TaskMaster Pro'));
      expect(html, contains('name="viewport"'));
      expect(html, contains('{{ .${entry.value} }}'));
      expect(html.toLowerCase(), isNot(contains('supabase')));
    }

    expect(
      RegExp(r'^\[auth\.email\.smtp\]', multiLine: true).hasMatch(config),
      isFalse,
      reason:
          'Do not enable placeholder SMTP settings. Hosted delivery requires '
          'real credentials and a verified From address.',
    );
  });
}
