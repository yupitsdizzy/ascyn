class Validators {
  static final _usernameRegExp = RegExp(r'^[a-zA-Z0-9_]{3,20}$');
  static final _displayNameRegExp = RegExp(r'^[a-zA-Z0-9 ]{1,30}$');

  static String? username(String value) {
    final v = value.trim();
    if (!_usernameRegExp.hasMatch(v)) {
      return '3–20 chars. Letters, numbers, underscore only.';
    }
    return null;
  }

  static String? displayName(String value) {
    final v = value.trim();
    if (!_displayNameRegExp.hasMatch(v)) {
      return '1–30 chars. Letters, numbers, spaces only.';
    }
    return null;
  }

  static String normalizeUsername(String value) => value.trim().toLowerCase();
}
