import 'dart:convert';

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
