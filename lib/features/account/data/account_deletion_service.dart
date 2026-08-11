import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/platform/device_identity.dart';

class AccountDeletionRequest {
  const AccountDeletionRequest({
    required this.requestedAt,
    required this.scheduledFor,
    required this.status,
  });

  factory AccountDeletionRequest.fromJson(Map<String, dynamic> value) {
    return AccountDeletionRequest(
      requestedAt: DateTime.parse(value['requested_at'] as String).toLocal(),
      scheduledFor: DateTime.parse(value['scheduled_for'] as String).toLocal(),
      status: value['status'] as String? ?? 'scheduled',
    );
  }

  final DateTime requestedAt;
  final DateTime scheduledFor;
  final String status;

  int get remainingDays {
    final difference = scheduledFor.difference(DateTime.now());
    return difference.isNegative ? 0 : difference.inDays + 1;
  }
}

class AccountDeletionService {
  AccountDeletionService(this.client);

  final SupabaseClient client;

  Future<AccountDeletionRequest?> current() async {
    final value = await client
        .from('account_deletion_requests')
        .select('requested_at,scheduled_for,status')
        .eq('status', 'scheduled')
        .maybeSingle();
    return value == null ? null : AccountDeletionRequest.fromJson(value);
  }

  Future<void> requestRecentAuthentication() => client.auth.reauthenticate();

  Future<void> confirmRecentAuthentication(String nonce) {
    return client.auth
        .updateUser(
          UserAttributes(
            nonce: nonce.trim(),
            data: {
              'last_sensitive_reauthentication_at': DateTime.now()
                  .toUtc()
                  .toIso8601String(),
            },
          ),
        )
        .then((_) {});
  }

  Future<AccountDeletionRequest> schedule() async {
    final user = client.auth.currentUser;
    if (user == null) throw AuthSessionMissingException();
    final deviceId = await DeviceIdentity.accountId(user.id);
    final value = await client.rpc<Map<String, dynamic>>(
      'schedule_account_deletion',
      params: {'p_device_id': deviceId, 'p_confirmation': 'DELETE'},
    );
    return AccountDeletionRequest.fromJson(value);
  }

  Future<AccountDeletionRequest> cancel() async {
    final user = client.auth.currentUser;
    if (user == null) throw AuthSessionMissingException();
    final deviceId = await DeviceIdentity.accountId(user.id);
    final value = await client.rpc<Map<String, dynamic>>(
      'cancel_account_deletion',
      params: {'p_device_id': deviceId},
    );
    return AccountDeletionRequest.fromJson(value);
  }
}
