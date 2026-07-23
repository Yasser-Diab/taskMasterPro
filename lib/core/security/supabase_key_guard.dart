import 'dart:convert';

class SupabaseKeyGuard {
  const SupabaseKeyGuard._();

  static String? validateUrl(String value) {
    final trimmed = value.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'Enter a valid Supabase project URL.';
    }
    if (uri.scheme != 'https') {
      return 'Supabase URLs must use HTTPS.';
    }
    return null;
  }

  static String? validatePublicClientKey(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'Enter a public publishable or anon key.';
    }

    final lowered = trimmed.toLowerCase();
    if (lowered.startsWith('postgresql://') ||
        lowered.startsWith('postgres://') ||
        lowered.contains('[your-password]')) {
      return 'Database connection strings do not belong in client settings.';
    }

    if (lowered.startsWith('sb_secret_') ||
        lowered.contains('service_role') ||
        lowered.contains('jwt_secret')) {
      return 'Secret, service-role, and JWT-signing keys are not allowed in the app.';
    }

    final jwtRole = _tryReadJwtRole(trimmed);
    if (jwtRole == 'service_role' || jwtRole == 'supabase_admin') {
      return 'Service-role and admin JWTs are not allowed in the app.';
    }

    return null;
  }

  static String? _tryReadJwtRole(String token) {
    final parts = token.split('.');
    if (parts.length < 2) {
      return null;
    }

    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final json = jsonDecode(payload);
      if (json is Map<String, dynamic>) {
        return json['role']?.toString();
      }
    } on FormatException {
      return null;
    }

    return null;
  }
}
