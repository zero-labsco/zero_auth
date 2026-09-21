# Auth State Machine / 认证状态机

## States / 状态

`AuthState` is a sealed class with six subtypes:

`AuthState` 是一个密封类，包含六个子类型：

| State | Fields | Meaning |
|-------|-------|---------|
| `Unauthenticated` | — | No session / 无会话 |
| `Authenticating` | — | `login`/`register` in flight / 登录/注册进行中 |
| `Authenticated` | `session: AuthSession` | A valid session / 有效会话 |
| `Refreshing` | `session: AuthSession` | Renewal in flight; the previous session is still usable / 续期进行中，旧会话仍可用 |
| `LoggingOut` | `session: AuthSession` | `logout()` in flight; that session is being discarded / 登出进行中，该会话即将被丢弃 |
| `AuthError` | `error: AppException` | Last operation failed / 上一次操作失败 |

Two helpers save you from spelling out every case:

两个辅助属性可避免你手写全部分支：

- `state.isAuthenticated` — `true` for `Authenticated` **and** `Refreshing`, so a
  renewal never unmounts your signed-in UI. / 在 `Authenticated` 与 `Refreshing`
  下均为 `true`，续期不会卸载已登录界面。
- `state.isBusy` — `true` while `Authenticating`, `Refreshing` or `LoggingOut`. /
  在 `Authenticating`、`Refreshing`、`LoggingOut` 期间为 `true`。
- `state.session` — the session the state carries (`Authenticated` / `Refreshing` /
  `LoggingOut`), or `null`; no pattern-matching needed for the common case. /
  该状态携带的会话（`Authenticated` / `Refreshing` / `LoggingOut`）或 `null`，
  常见场景无需再做模式匹配。

## The stream / 状态流

`AuthManager.state` is a `Stream<AuthState>` that **replays the latest value** to every new listener (`BehaviorSubject`-like). This means:

`AuthManager.state` 是一个 `Stream<AuthState>`，会向每个新订阅者**重放最近的值**（类似于 `BehaviorSubject`）。这意味着：

- A freshly mounted widget renders the correct screen on its first frame / 新挂载的 widget 首帧即渲染正确界面。
- You never need to read a separate "current state" field / 无需另读一个"当前状态"字段。

```dart
auth.state.listen((state) {
  switch (state) {
    case Authenticated(:final session):
      /* ... */
    case AuthError(:final error):
      /* ... */
    default:
  }
});
```

## Transitions / 状态转移

```
          login/register ──► Authenticating ──► Authenticated
                                                    │  ▲
                                        refresh     │  │ success
                                        ─────────►  ▼  │
                                                Refreshing
                                                    │
                                          failure   │
                                                    ▼
                                              AuthError ──policy: sign out──► Unauthenticated
                                                    └──policy: keep session─► Authenticated (old session)

   Authenticated ──logout──► LoggingOut ──► Unauthenticated
   Unauthenticated ──restore() finds nothing / nothing persisted──► Unauthenticated
```

- `restore()` restores a live session → `Authenticated`.
- `restore()` restores an **expired** session → attempts `Refreshing`; if the
  renewal fails *transiently* (network, 5xx) the persisted session is **kept** and
  activated as-is, so the next request can retry. Only a terminal failure — or the
  absence of a refresh token — clears the store and lands on `Unauthenticated`.
  `restore(refreshIfExpired: false)` restores it verbatim instead.
- A failed `login`/`register` → `AuthError`, and the future rethrows.
- A failed `refresh` → `AuthError`, followed by `Unauthenticated` when the
  [failure policy](#refresh-failure-policy) considers the grant unrecoverable,
  or by `Authenticated` (previous session) when it looks transient.
- Duplicate consecutive emissions are suppressed, so listeners only rebuild on a
  real change.

- `restore()` 恢复未过期会话 → `Authenticated`。
- `restore()` 恢复**已过期**会话 → 先走 `Refreshing`；若续期**瞬时**失败（网络、5xx），
  则**保留**持久化会话并按原样激活，下次请求可再试。只有终局失败（或没有刷新令牌）
  才会清空存储并落到 `Unauthenticated`。`restore(refreshIfExpired: false)` 则原样恢复。
- `login`/`register` 失败 → `AuthError`，同时 future 再次抛出错误。
- `refresh` 失败 → `AuthError`；随后由[失败策略](#refresh-failure-policy)决定：
  认为授权不可恢复则转 `Unauthenticated`，认为只是瞬时故障则回到 `Authenticated`。
- 连续重复的状态会被抑制，监听器只会在真正变化时重建。

## Next Steps / 下一步

- [Usage](Usage) — How to drive the UI from the stream / 如何用状态流驱动界面
- [Backend Strategy](Backend-Strategy) — What each operation calls / 各操作调用什么
