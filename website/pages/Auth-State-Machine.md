# Auth State Machine / 认证状态机

## States / 状态

`AuthState` is a sealed class with four subtypes:

`AuthState` 是一个密封类，包含四个子类型：

| State | Fields | Meaning |
|-------|-------|---------|
| `AuthUnauthenticated` | — | No session / 无会话 |
| `Authenticating` | — | `login`/`register`/`restore` in flight / 登录/注册/恢复进行中 |
| `Authenticated` | `session: AuthSession` | A valid session / 有效会话 |
| `AuthError` | `error: AppException` | Last operation failed / 上一次操作失败 |

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
   Unauthenticated ◄──────────────────────────────────────┘  (error)
        ▲                                                          │ logout
        │                                                          ▼
        └─────────────────────── AuthError ◄── refresh fails ── Authenticated
        └──────────────────────────── restore() finds nothing
```

- `restore()` finds a persisted session → `Authenticated`; none → stays `Unauthenticated`.
- A failed `login`/`register` → `AuthError` (the previous state is retained as the "last good" state if any).
- A failed `refresh` clears the session → `AuthError`.

- `restore()` 找到持久化会话 → `Authenticated`；找不到 → 保持 `Unauthenticated`。
- `login`/`register` 失败 → `AuthError`（若有，则保留上一个"良好"状态）。
- `refresh` 失败清空会话 → `AuthError`。

## Next Steps / 下一步

- [Usage](Usage) — How to drive the UI from the stream / 如何用状态流驱动界面
- [Backend Strategy](Backend-Strategy) — What each operation calls / 各操作调用什么
