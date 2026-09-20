# Multiple Accounts / 多账号

## First: which kind do you need? / 先分清你需要哪一种

"Multiple accounts" means two very different things, and they do **not** need the
same solution:

「多账号」其实指两种截然不同的需求，它们的解法**不一样**：

| Shape | Description | Recommendation |
|-------|-------------|----------------|
| **Switching** / 账号切换 | Several accounts are remembered, but only one is used at a time (like Gmail's account picker) / 记住多个账号，但同时只用一个 | Plain `AuthManager`: `logout()` then `login()`. No new API. / 普通 `AuthManager`：登出再登录，不需要新 API |
| **Concurrent** / 账号并存 | Several accounts are signed in *at the same time* and all can make requests / 多个账号同时登录，且都能发请求 | `AuthManagerGroup` — one `AuthManager` per account |

Most apps only need the first. Reach for `AuthManagerGroup` only when an account
must keep working while another one is in the foreground.

多数应用只需要第一种。只有当「某个账号在后台也要继续工作」时，才需要 `AuthManagerGroup`。

## Shape 1: switching / 形态一：切换

`AuthManager` models one session. Switching accounts is just logging out and back
in — the state machine stays honest, and there is no second source of truth:

```dart
// Keep your own list of saved account identifiers (email, phone, …).
// 自己维护已保存账号标识（邮箱、手机号等）的列表。
final savedAccounts = <String>['alice@example.com', 'bob@example.com'];

Future<void> switchTo(String account, String password) async {
  if (auth.current.isAuthenticated) await auth.logout();
  await auth.login(Credentials(username: account, password: password));
}
```

Because `username` is just an opaque identifier, this works for email or phone
logins with no extra plumbing — see
[Backend Strategy](Backend-Strategy) for what the contract fixes.

## Shape 2: concurrent / 形态二：并存

`AuthManagerGroup` owns one `AuthManager` per account and tracks which is active.

```dart
final group = AuthManagerGroup(
  // Both factories receive the account id; sharing one strategy instance is fine.
  // 两个工厂都会收到账号 id；共用一个策略实例也没问题。
  strategyFactory: (accountId) => MyAuthStrategy(),
  // CRITICAL: one store per account, so persisted sessions stay isolated.
  // 关键：每个账号一个存储，持久化会话才不会互相覆盖。
  storeFactory: (accountId) => SecureTokenStore(key: 'auth_$accountId'),
);

// Sign in (or restore) each account independently.
// 各账号独立登录（或恢复）。
await group.forAccount('alice').login(
  Credentials(username: 'alice@example.com', password: pw),
);
await group.forAccount('bob').login(
  Credentials(username: 'bob@example.com', password: pw),
);

// Pick the active one — nothing is signed out by this call.
// 选择激活账号 —— 此调用不会登出任何账号。
group.switchTo('bob');
```

### Reading the active account / 读取激活账号

The group mirrors the active account and implements `AuthTokenSource`, so
interceptors keep depending on the narrow interface:

```dart
group.current            // active account's AuthState / 激活账号的状态
group.currentSession     // active account's session / 激活账号的会话
group.accessToken        // active account's token / 激活账号的令牌
group.state              // stream that follows the active account / 跟随激活账号的流

dio.interceptors.add(AuthInterceptor(group)); // reads the active token / 读激活账号令牌
```

### Restoring on startup / 启动时恢复

```dart
// `knownIds` comes from your own saved-account list.
// `knownIds` 来自你自己保存的账号列表。
await group.restoreAll(knownIds, activeId: lastUsedId);
```

### Removing an account / 移除账号

```dart
await group.remove('alice');   // logs out, disposes, forgets it
```

If the removed account was active, the group becomes inactive and emits
`Unauthenticated`.

### Teardown / 释放

```dart
await group.disposeAll();      // disposes every manager and closes the stream
```

## Why the core stays single-session / 为什么核心仍是单会话

`AuthManager` answers a singular question: **who is logged in?** Multi-account asks
a different one: **of these signed-in identities, which is active?**

Folding the second into the first would mean a `Map` of sessions inside every
state, a `Refreshing` that needs an account id, and a breaking change for every
existing user. Keeping `AuthManager` single-session and adding an opt-in
coordinator gives you both without muddying either.

把第二个问题塞进第一个，会导致每个状态里都带一个会话 `Map`、`Refreshing` 需要携带账号
id，并且对所有现有用户构成破坏性变更。让 `AuthManager` 保持单会话、再提供一个可选的
协调层，两者都能得到，且互不污染。

## Gotchas / 注意点

- **Never share one `TokenStore` between accounts** — the second `save()` would
  overwrite the first session. / **绝不要在多个账号间共用一个 `TokenStore`**，第二次
  `save()` 会覆盖第一个会话。
- Switching does not sign anyone out; all managers keep refreshing in the
  background. / 切换不会登出任何账号，所有管理器仍会在后台续期。
- `remove()` also disposes that manager — do not use it afterwards. /
  `remove()` 会同时释放该管理器，之后不要再使用它。

## Next Steps / 下一步

- [Auth State Machine](Auth-State-Machine) — what each manager emits / 各管理器会发出什么
- [Token Store](Token-Store) — keying persisted sessions per account / 按账号隔离持久化会话
- [Backend Strategy](Backend-Strategy) — what the contract fixes / 契约固定了什么
