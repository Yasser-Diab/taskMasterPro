import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vacation migration exposes reads but guards every mutation', () {
    final source = File(
      'supabase/migrations/20260818093000_v0031_vacation_periods.sql',
    ).readAsStringSync();

    expect(
      source,
      contains('taskmaster_internal.apply_vacation_period_command'),
    );
    expect(source, contains('security definer'));
    expect(
      source,
      contains(
        'create or replace function public.apply_vacation_period_command',
      ),
    );
    expect(source, contains('security invoker'));
    expect(source, contains('grant select on public.vacation_periods'));
    expect(
      source,
      contains('revoke insert, update, delete, truncate, references, trigger'),
    );
    expect(source, isNot(contains('grant select, insert, update, delete')));
    expect(source, contains("'verify_processed_command_session'"));
    expect(source, contains('authenticated_vacation_table_mutation_privilege'));
    expect(source, contains('unexpected_vacation_policy_surface'));
    expect(
      source,
      contains("processed_row.device_id is distinct from p_device_id"),
    );
    expect(
      source,
      contains(
        'processed_row.device_sequence is distinct from p_device_sequence',
      ),
    );
    expect(
      source,
      contains("processed_row.entity_type is distinct from 'vacation_periods'"),
    );
    expect(
      source,
      contains('processed_row.entity_id is distinct from p_entity_id'),
    );
    expect(
      source,
      contains('processed_row.command_type is distinct from p_operation'),
    );
    expect(
      source,
      contains('processed_row.base_revision is distinct from p_base_revision'),
    );
    expect(source, contains('command_identity_mismatch'));
    final replay = source.indexOf('from public.processed_commands');
    final mutableDeviceCheck = source.indexOf('from public.account_devices');
    expect(replay, greaterThanOrEqualTo(0));
    expect(mutableDeviceCheck, greaterThan(replay));
    expect(source, contains("task_scope = 'selectedTemplates'"));
    expect(source, contains('jsonb_array_length(selected_template_ids) > 0'));
    expect(source, contains('selected_vacation_tasks_required'));
  });
}
