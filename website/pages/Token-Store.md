# Token Store / 令牌存储

`TokenStore` is the **only** persistence surface. The core never touches disk, secure storage, or `SharedPreferences` directly — you decide where tokens live.

`TokenStore` 是**唯一**的持久化接口。内核绝不直接访问磁盘、安全存储或 `SharedPreferences`——由你决定令牌存放位置。

## The contract / 契约

```dart
abstract class TokenStore {
  Future<void> save(AuthSession session);
  Future<AuthSession?> load();
  Future<void> clear();
}
```

`AuthManager` calls `load()` during `restore()`, `save()` after every successful login/refresh, and `clear()` on logout or a failed refresh.

`AuthManager` 在 `restore()` 时调用 `load()`，每次登录/刷新成功后调用 `save()`，在登出或刷新失败失败时调用 `clear()`。

## In-memory (ships in-core) / 内存实现（内核自带）

`InMemoryTokenStore` is the default. It survives process restarts? No — it is in-memory only, so the session is lost on restart. Use it for tests and quick prototypes.

`InMemoryTokenStore` 是默认实现，仅存在于内存，进程重启后会话丢失。适用于测试与原型。

```dart
final auth = AuthManager(strategy: s, tokenStore: InMemoryTokenStore());
```

## Secure storage (production) / 安全存储（生产）

`example/lib/secure_token_store.dart` shows a `flutter_secure_storage`-backed reference implementation. Adapt it for your app:

`example/lib/secure_token_store.dart` 提供了基于 `flutter_secure_storage` 的参考实现，可据此改造：

```dart
class SecureTokenStore implements TokenStore {
  final _box = FlutterSecureStorage();
  @override
  Future<void> save(AuthSession s) =>
      _box.write(key: 'zero_auth', value: jsonEncode(s.toJson()));
  @override
  Future<AuthSession?> load() async {
    final raw = await _box.read(key: 'zero_auth');
    return raw == null ? null : AuthSession.fromJson(jsonDecode(raw));
  }
  @override
  Future<void> clear() => _box.delete(key: 'zero_auth');
}
```

> Persist tokens only in OS-backed secure storage (Keychain / Keystore). Never store refresh tokens in plain `SharedPreferences`.
>
> 令牌只应存放在操作系统级安全存储（Keychain / Keystore）中，切勿把刷新令牌明文存入 `SharedPreferences`。

## Next Steps / 下一步

- [Session Persistence](Persistence) — persist sessions across restarts (serialization + reference stores) / 跨重启持久化会话（序列化与参考存储）
- [Backend Strategy](Backend-Strategy) — The other boundary / 另一个边界
- [Errors](Errors) — What `load()` failures become / `load()` 失败会变成什么
