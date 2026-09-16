# Configuration / 配置

`zero_auth` is deliberately minimal: there is no global config object. Behavior is composed from the two boundaries you pass to `AuthManager`.

`zero_auth` 刻意保持精简：没有全局配置对象。行为由你传给 `AuthManager` 的两个边界组合而成。

## Composing `AuthManager` / 组合管理器

```dart
final auth = AuthManager(
  strategy: MyAuthStrategy(),   // how to talk to the backend / 如何与后端通信
  tokenStore: SecureTokenStore(), // where to persist tokens / 令牌持久化位置
);
```

| Knob | Where | Effect |
|------|-------|--------|
| Backend endpoints & auth scheme | `AuthStrategy` | What `login`/`refresh`/… actually do / `login`/`refresh` 等的实际行为 |
| Token persistence | `TokenStore` | Disk / secure storage / in-memory / 磁盘/安全存储/内存 |
| Refresh timing | `AuthSession.expiresAt` | `isExpired` drives proactive refresh / 由 `isExpired` 驱动主动刷新 |
| Token injection | `AuthTokenSource` | How the bearer token reaches HTTP clients / 令牌如何到达 HTTP 客户端 |

## Refresh strategy / 刷新策略

`refresh()` is **single-flight** by construction: concurrent callers share one in-flight request. You decide *when* to refresh:

`refresh()` 天生**单飞**：并发调用方共享同一次进行中的请求。*何时*刷新由你决定：

- Proactively, when `session.isExpired` is approaching, before a request. / 在请求前、当 `session.isExpired` 临近时主动刷新。
- Reactively, on a `401` from your API (see [Network Integration](Network-Integration)). / 响应式地，在 API 返回 `401` 时刷新。

A failed refresh clears the session and emits `AuthError`; your app should route the user back to login.

刷新失败会清空会话并发出 `AuthError`，应用应将用户引导回登录。

## No global singletons / 没有全局单例

`AuthManager` is a plain object — create one per app, hold it in your DI container or a top-level variable. The core has no static mutable state.

`AuthManager` 是一个普通对象——每个应用创建一个，放在 DI 容器或顶层变量中即可。内核没有静态可变状态。

## Next Steps / 下一步

- [Usage](Usage) — Putting it together / 综合使用
- [FAQ](FAQ) — Common questions / 常见问题
