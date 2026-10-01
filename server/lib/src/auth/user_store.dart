/// A verified account.
final class UserRecord {
  const UserRecord({required this.id, required this.displayName});

  final String id;
  final String displayName;
}

/// A stored account: the password plus the display name it was created with.
///
/// Keeping the name here (rather than deriving it from the id every time) is
/// what makes a `displayName` chosen at registration survive a later login,
/// refresh or `/me` call.
/// 已存储的账号：密码加上创建时指定的显示名。
///
/// 把名称存在这里（而不是每次都从 id 推导），正是注册时选择的 `displayName` 能在后续
/// 登录、续期与 `/me` 调用中保持一致的原因。
final class _Account {
  const _Account({required this.password, required this.displayName});

  final String password;
  final String displayName;
}

/// Credential verification.
///
/// The demo ships a single account, `user` / `user`, which is all the example
/// app needs. Swap this class for a database in a real deployment; nothing else
/// in the backend has to change.
final class UserStore {
  UserStore({Map<String, String>? credentials})
      : _accounts = {
          for (final entry in (credentials ?? _defaultCredentials).entries)
            entry.key: _Account(
              password: entry.value,
              displayName: _displayNameFor(entry.key),
            ),
        };

  static const _defaultCredentials = <String, String>{'user': 'user'};

  final Map<String, _Account> _accounts;

  /// Returns the matching user, or `null` when the credentials are wrong.
  UserRecord? authenticate(String username, String password) {
    final account = _accounts[username];
    if (account == null || !_constantTimeEquals(account.password, password)) {
      return null;
    }
    return UserRecord(id: username, displayName: account.displayName);
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
    if (_accounts.containsKey(id)) return null;

    final account = _Account(
      password: password,
      displayName: displayName ?? _displayNameFor(id),
    );
    _accounts[id] = account;
    return UserRecord(id: id, displayName: account.displayName);
  }

  /// Looks a user up by id, used when rebuilding a user from a valid token.
  UserRecord? findById(String id) {
    final account = _accounts[id];
    if (account == null) return null;
    return UserRecord(id: id, displayName: account.displayName);
  }

  static String _displayNameFor(String username) => '$username@demo';

  /// Length-tolerant comparison, so a wrong password cannot be narrowed down
  /// one character at a time.
  /// 长度不敏感的常量时间比较，避免密码被逐字符猜解。
  static bool _constantTimeEquals(String a, String b) {
    var diff = a.length ^ b.length;
    for (var i = 0; i < a.length && i < b.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
