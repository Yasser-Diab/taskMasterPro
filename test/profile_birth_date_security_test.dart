import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile birth-date validation is trigger-only, not an RPC surface', () {
    final definition = File(
      'supabase/migrations/20260726094500_profile_birth_date.sql',
    ).readAsStringSync();
    final hardening = File(
      'supabase/migrations/20260811191445_v0028_revoke_profile_trigger_execute.sql',
    ).readAsStringSync().toLowerCase();

    expect(
      definition,
      contains(
        'for each row execute function public.validate_profile_birth_date()',
      ),
    );
    expect(
      hardening,
      contains(
        'revoke execute on function public.validate_profile_birth_date() from public;',
      ),
    );
    expect(
      hardening,
      contains(
        'revoke execute on function public.validate_profile_birth_date() from anon;',
      ),
    );
    expect(
      hardening,
      contains(
        'revoke execute on function public.validate_profile_birth_date() from authenticated;',
      ),
    );
    expect(hardening, isNot(contains('drop trigger')));
  });
}
