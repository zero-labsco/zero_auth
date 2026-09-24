/// A verified account.
final class UserRecord {
  const UserRecord({required this.id, required this.displayName});

  final String id;
  final String displayName;
}

/// Credential verification.
///
/// The demo ships a single account, `user` / `user`, which is all the example
/// app needs. Swap this class for a database in a real deployment; nothing else
/// in the backend has to change.
final class UserStore {
  UserStore({Map<String, String>? credentials})
      : _credentials =
            credentials ?? Map<String, String>.of(_defaultCredentials);

  static const _defaultCredentials = <String, String>{'user': 'user'};

  final Map<String, String> _credentials;

  /// Returns the matching user, or `null` when the credentials are wrong.
  UserRecord? authenticate(String username, String password) {
    final expected = _credentials[username];
    if (expected == null || expected != password) return null;
    return UserRecord(id: username, displayName: _displayNameFor(username));
  }

  /// Creates an account, or returns `null` when the username is taken or the
  /// credentials are unusable.
  ///
  /// The account is added to the same in-memory map [authenticate] and
  /// [findById] read, so a freshly registered user can log in, refresh and call
  /// `/me` right away — until the process restarts.
  UserRecord? register(
    String username,
    String password, {
    String? displayName,
  }) {
    final id = username.trim();
    if (id.isEmpty || password.isEmpty) return null;
    if (_credentials.containsKey(id)) return null;
    _credentials[id] = password;
    return UserRecord(id: id, displayName: displayName ?? _displayNameFor(id));
  }

  /// Looks a user up by id, used when rebuilding a user from a valid token.
  UserRecord? findById(String id) {
    if (!_credentials.containsKey(id)) return null;
    return UserRecord(id: id, displayName: _displayNameFor(id));
  }

  static String _displayNameFor(String username) => '$username@demo';
}
