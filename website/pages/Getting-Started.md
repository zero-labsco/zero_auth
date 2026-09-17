# Getting Started / 快速开始

## Quick Start / 快速开始

`zero_auth` is a headless core: you bring the backend (`AuthStrategy`) and the persistence (`TokenStore`), and `AuthManager` drives the session lifecycle.

`zero_auth` 是一个无头内核：你提供后端（`AuthStrategy`）与持久化（`TokenStore`），`AuthManager` 负责驱动会话生命周期。

```dart
import 'package:zero_auth/zero_auth.dart';

// 1. Implement your backend (four methods only).
// 1. 实现你的后端（只需四个方法）。
final strategy = MyAuthStrategy();
// 2. Pick a token store. InMemoryTokenStore ships in-core; for production use
//    the flutter_secure_storage reference in example/lib/secure_token_store.dart.
// 2. 选择令牌存储。内核自带 InMemoryTokenStore；生产环境请用
//    example/lib/secure_token_store.dart 中的 flutter_secure_storage 实现。
final store = InMemoryTokenStore();
// 3. Create the manager and restore any persisted session.
// 3. 创建管理器并恢复已持久化的会话。
final auth = AuthManager(strategy: strategy, tokenStore: store);
await auth.restore();
```

Then drive the UI from the state stream:

随后用状态流驱动界面：

```dart
auth.state.listen((state) {
  switch (state) {
    case Unauthenticated():
      showLoginScreen();
    case Authenticating():
    case LoggingOut():
      showSpinner();
    case Authenticated(:final session):
      showHome(session.userId);
    case Refreshing(:final session):
      // Still signed in: only the token is being renewed.
      // 仍处于已登录状态：只是令牌在续期。
      showHome(session.userId, renewing: true);
    case AuthError(:final error):
      showError(error);
  }
});
```

> If you prefer `if`/`else` over exhaustiveness, use `state.isAuthenticated` and
> `state.isBusy` instead of `state is Authenticated` — `isAuthenticated` stays
> `true` during `Refreshing`, so your UI never bounces back to the login screen
> mid-refresh.
>
> 若不想用穷举匹配，请用 `state.isAuthenticated` / `state.isBusy` 代替
> `state is Authenticated`——`isAuthenticated` 在 `Refreshing` 期间仍为 `true`，
> 界面不会在刷新途中退回登录页。

## The Lifecycle / 生命周期

`AuthManager` broadcasts an explicit, sealed state machine:

`AuthManager` 广播一个显式、密封的状态机：

| State | Meaning |
|-------|---------|
| `Unauthenticated` | No session / 无会话 |
| `Authenticating` | `login`/`register` in flight / 登录/注册进行中 |
| `Authenticated` | A valid session is present / 存在有效会话 |
| `Refreshing` | Session renewal in flight; the previous session stays usable / 续期进行中，旧会话仍可用 |
| `LoggingOut` | `logout()` in flight / 登出进行中 |
| `AuthError` | The last operation failed / 上一次操作失败 |

The stream replays the latest value to new listeners, so a widget renders the correct screen on its first frame.

状态流会向新订阅者重放最近的值，因此 widget 在首帧即可渲染正确界面。

## Next Steps / 下一步

- [Installation](Installation) — Detailed installation methods / 详细安装方式
- [Usage](Usage) — Full usage guide / 完整使用指南
- [Backend Strategy](Backend-Strategy) — Implement `AuthStrategy` / 实现后端边界
