# Session Persistence / 会话持久化

`InMemoryTokenStore` loses the session on every restart. For a real app you must persist it — and `zero_auth` now ships the primitives that make this a one-liner: **session (de)serialization** plus two ready-to-copy reference stores.

`InMemoryTokenStore` 会在每次重启时丢失会话。真实应用必须把它持久化——而 `zero_auth` 现在提供了让这件事变成「一行代码」的原语：**会话（反）序列化**，外加两个开箱即用的参考存储。

## 1. Serialize the session / 序列化会话

`AuthSession` is JSON-safe out of the box. `null` fields are omitted, and `claims` round-trips as a plain map.

`AuthSession` 天生就是 JSON 安全的：`null` 字段会被省略，`claims` 作为普通映射原样往返。

```dart
final json = session.toJson();            // Map<String, Object?>
final restored = AuthSession.fromJson(json);

// Prefer this inside TokenStore.load(): malformed data yields null ("not signed
// in") instead of a FormatException / TypeError.
// TokenStore.load() 里请优先用它：畸形数据返回 null（即「未登录」），而不是抛
// FormatException / TypeError。
final safe = AuthSession.tryFromJson(json);
```

`RefreshToken` serializes to its raw string too, so a persisted session rehydrates losslessly.

`RefreshToken` 也序列化为其原始字符串，因此持久化的会话可无损恢复。

## 2. Flutter — encrypted secure storage / Flutter —— 加密安全存储

For mobile, persist into the OS keychain / keystore via `flutter_secure_storage`. A reference implementation lives at `example/lib/secure_token_store.dart`:

在移动端，通过 `flutter_secure_storage` 把令牌存入系统钥匙串 / Keystore。参考实现位于 `example/lib/secure_token_store.dart`：

```dart
final auth = AuthManager(
  strategy: myStrategy,
  tokenStore: SecureTokenStore(),   // from example/
);

await auth.restore();   // rehydrate before the first frame
```

> Never store refresh tokens in plain `SharedPreferences`. Use OS-backed secure storage only.
>
> 切勿把刷新令牌明文存入 `SharedPreferences`，只使用操作系统级安全存储。

## 3. Server / CLI / desktop — JSON file / 服务端 / CLI / 桌面 —— JSON 文件

On non-mobile Dart targets you can write the serialized session to a file. A reference implementation lives at `example/lib/json_token_store.dart`:

在非移动端 Dart 目标上，可以把序列化后的会话写入文件。参考实现位于 `example/lib/json_token_store.dart`：

```dart
final auth = AuthManager(
  strategy: myStrategy,
  tokenStore: JsonTokenStore(File('.zero_auth_session.json')),
);
```

This is ideal for a backend that keeps a logged-in user across process restarts, or a CLI that stays authenticated between invocations.

这非常适合「重启后仍保持登录」的后端，或「多次调用之间保持认证」的 CLI。

## 4. Combine with auto-refresh / 结合自动刷新

When you enable [proactive auto-refresh](Configuration), the manager renews the token before it expires — and every renewal is persisted through `save()`, so the on-disk session always carries a fresh access token.

当你开启[主动自动刷新](Configuration)时，管理器会在令牌过期前续期——而每次续期都会通过 `save()` 落盘，因此磁盘上的会话始终持有崭新的访问令牌。

```dart
final auth = AuthManager(
  strategy: myStrategy,
  tokenStore: SecureTokenStore(),
  autoRefreshAhead: const Duration(minutes: 5),
);
```

## 5. One owner for renewal / 续期只归一个所有者

`TokenStore` has no cross-isolate or cross-process lock. If two isolates — or an
app and its share extension — refresh the same refresh token at once, the first
rotation retires it and the second one reads as a **replay**, which a
rotation-aware backend answers by revoking the whole family and signing *both*
out.

`TokenStore` 没有跨 isolate / 跨进程锁。若两个 isolate（或 App 与其共享扩展）同时用
同一个刷新令牌续期，第一次轮换会让它退役，第二次就会被读成**重放** —— 支持轮换的后端
会据此吊销整个 family，把**两边**都登出。

Two safe shapes / 两种安全形态：

- **Separate keys** — give every isolate its own `TokenStore` key, so each holds
  an independent refresh token. / 为每个 isolate 使用独立的 `TokenStore` 键，各自持有
  独立的刷新令牌。
- **One owner** — let exactly one isolate own the `AuthManager` and broadcast the
  token to the rest; everyone else only reads. / 只让一个 isolate 持有 `AuthManager`
  并把令牌广播给其余；其他 isolate 只读取。

```dart
// Shape 2: the owner is the only writer — it renews and rotates, then pushes the
// fresh token over whatever channel you already have (SendPort, socket, …).
// 形态二：所有者是唯一的写入方 —— 由它续期与轮换，再通过你已有的通道
// （SendPort、socket 等）把新令牌推给其余。
final owner = AuthManager(
  strategy: strategy,
  tokenStore: store,
  onStateChanged: (state) => broadcast(state.session?.accessToken),
);

// Elsewhere: hold the broadcast token and never refresh. No renewal means no
// rotation race.
// 其它地方：持有广播来的令牌，且从不刷新。不续期就没有轮换竞争。
```

## Next Steps / 下一步

- [Token Store](Token-Store) — the `save` / `load` / `clear` contract / `save` / `load` / `clear` 契约
- [Configuration](Configuration) — enable proactive auto-refresh / 开启主动自动刷新
