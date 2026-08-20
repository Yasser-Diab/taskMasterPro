import 'dart:convert';

/// A login draft read from the currently visible page after the user chooses
/// Save sign-in. The value exists only long enough to prefill the native vault
/// confirmation dialog; it is never written to browser storage or sync data.
class BrowserCredentialDraft {
  const BrowserCredentialDraft({
    required this.username,
    required this.password,
    required this.website,
  });

  final String username;
  final String password;
  final String website;

  String get suggestedName {
    final user = username.trim();
    if (user.isNotEmpty) return user;
    return canonicalWebsiteHost(website) ?? '';
  }

  /// WebView2 and Android WebView encode JavaScript results differently. This
  /// accepts either shape, then binds the captured value to the exact current
  /// HTTPS origin before it can reach the vault confirmation UI.
  static BrowserCredentialDraft? fromJavaScript(
    Object? raw, {
    required String pageUrl,
  }) {
    final page = Uri.tryParse(pageUrl.trim());
    if (page == null ||
        page.scheme.toLowerCase() != 'https' ||
        page.host.isEmpty) {
      return null;
    }
    Object? decoded = raw;
    for (var attempt = 0; attempt < 2 && decoded is String; attempt++) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        return null;
      }
    }
    if (decoded is! Map) return null;
    final origin = decoded['origin']?.toString().trim();
    final captured = Uri.tryParse(origin ?? '');
    if (captured == null ||
        captured.scheme.toLowerCase() != 'https' ||
        captured.host.toLowerCase() != page.host.toLowerCase() ||
        _effectivePort(captured) != _effectivePort(page)) {
      return null;
    }
    final password = decoded['password']?.toString() ?? '';
    if (password.isEmpty || password.length > 4096) return null;
    final username = decoded['username']?.toString() ?? '';
    if (username.length > 512) return null;
    return BrowserCredentialDraft(
      username: username,
      password: password,
      website: captured.origin,
    );
  }
}

int _effectivePort(Uri uri) {
  if (uri.hasPort) return uri.port;
  return uri.scheme.toLowerCase() == 'https' ? 443 : 80;
}

String normalizeBrowserAddress(String value) {
  final trimmed = value.trim();
  final parsed = Uri.tryParse(trimmed);
  if (parsed != null &&
      const {'http', 'https'}.contains(parsed.scheme.toLowerCase()) &&
      parsed.host.isNotEmpty) {
    return parsed.toString();
  }
  // The task browser is a web surface, not a script or local-file executor.
  // Unsupported explicit schemes are treated as search text so an address-bar
  // paste cannot navigate to javascript:, data:, or file: content.
  if (parsed?.hasScheme == true) {
    return Uri.https('www.google.com', '/search', {'q': trimmed}).toString();
  }
  if (trimmed.contains('.') && !trimmed.contains(' ')) {
    return 'https://$trimmed';
  }
  return Uri.https('www.google.com', '/search', {'q': trimmed}).toString();
}

String? canonicalWebsiteHost(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
  final host = Uri.tryParse(withScheme)?.host.toLowerCase();
  if (host == null || host.isEmpty) return null;
  return host.startsWith('www.') ? host.substring(4) : host;
}

/// Credentials are offered only for the exact host (apart from a leading
/// `www.`). This deliberately avoids guessing across sibling subdomains.
bool websiteMatchesForCredential({
  required String savedWebsite,
  required String pageUrl,
}) {
  final savedHost = canonicalWebsiteHost(savedWebsite);
  final pageHost = canonicalWebsiteHost(pageUrl);
  return savedHost != null && savedHost == pageHost;
}

/// Builds an explicit, user-triggered fill operation. It changes only visible
/// username/password fields and dispatches input/change events for reactive
/// forms. It never submits a form, stores a credential in page storage, or
/// sends it to a different origin.
String buildCredentialFillScript({
  required String username,
  required String password,
}) {
  final encodedUsername = jsonEncode(username);
  final encodedPassword = jsonEncode(password);
  return '''
(() => {
  const username = $encodedUsername;
  const password = $encodedPassword;
  const visible = (element) => {
    if (!element || element.disabled || element.readOnly) return false;
    const style = window.getComputedStyle(element);
    return style.display !== 'none' && style.visibility !== 'hidden';
  };
  const first = (selectors) => {
    for (const selector of selectors) {
      const element = Array.from(document.querySelectorAll(selector))
        .find(visible);
      if (element) return element;
    }
    return null;
  };
  const setValue = (element, value) => {
    if (!element || !value) return false;
    const descriptor = Object.getOwnPropertyDescriptor(
      Object.getPrototypeOf(element),
      'value'
    );
    if (descriptor && descriptor.set) {
      descriptor.set.call(element, value);
    } else {
      element.value = value;
    }
    element.dispatchEvent(new Event('input', { bubbles: true }));
    element.dispatchEvent(new Event('change', { bubbles: true }));
    return true;
  };
  const usernameInput = first([
    'input[autocomplete="username"]',
    'input[type="email"]',
    'input[name*="email" i]',
    'input[name*="user" i]',
    'input[type="text"]'
  ]);
  const passwordInput = first([
    'input[autocomplete="current-password"]',
    'input[type="password"]'
  ]);
  const usernameFilled = setValue(usernameInput, username);
  const passwordFilled = setValue(passwordInput, password);
  if (passwordFilled) passwordInput.focus();
  return usernameFilled || passwordFilled;
})()
''';
}

/// Reads only visible sign-in fields after the user explicitly chooses
/// Save sign-in. It does not install listeners, intercept submission, send a
/// message, mutate the page, or retain a value in browser storage.
const browserCredentialCaptureScript = r'''
(() => {
  if (window.top !== window || window.location.protocol !== 'https:') {
    return null;
  }
  const visible = (element) => {
    if (!element || element.disabled) return false;
    const style = window.getComputedStyle(element);
    const rect = element.getBoundingClientRect();
    return style.display !== 'none' &&
      style.visibility !== 'hidden' &&
      rect.width > 0 && rect.height > 0;
  };
  const passwords = Array.from(document.querySelectorAll('input[type="password"]'))
    .filter(visible)
    .filter((input) => String(input.autocomplete || '').toLowerCase() !== 'new-password');
  const passwordInput = passwords.find(
    (input) => String(input.autocomplete || '').toLowerCase() === 'current-password',
  ) || (passwords.length === 1 ? passwords[0] : null);
  if (!passwordInput || !passwordInput.value) return null;
  const form = passwordInput.form;
  const scope = form || document;
  const candidates = [
    'input[autocomplete="username"]',
    'input[type="email"]',
    'input[name*="email" i]',
    'input[name*="user" i]',
    'input[type="text"]',
  ];
  let usernameInput = null;
  for (const selector of candidates) {
    usernameInput = Array.from(scope.querySelectorAll(selector)).find(visible) || null;
    if (usernameInput) break;
  }
  return JSON.stringify({
    origin: window.location.origin,
    username: usernameInput ? String(usernameInput.value || '') : '',
    password: String(passwordInput.value),
  });
})()
''';
