# Configuration / 配置

`zero_auth` is deliberately minimal: there is no global config object. Behavior is composed from the two boundaries you pass to `AuthManager`.

`zero_auth` 刻意保持精简：没有全局配置对象。行为由你传给 `AuthManager` 的两个边界组合而成。

## Composing `AuthManager` / 组合管理器

```dart
final auth = AuthManager(
  strategy: MyAuthStrategy(),     // how to talk to the backend / 如何与后端通信
  tokenStore: SecureTokenStore(), // where to persist tokens / 令牌持久化位置
  autoRefreshAhead: const Duration(minutes: 5), // proactive renewal / 主动续期
  autoRefreshRetryDelay: const Duration(seconds: 30), // re-arm after a failed renewal / 续期失败后重新排程
  refreshFailurePolicy: defaultRefreshFailurePolicy, // sign-out rule / 登出规则
  clock: () => DateTime.now(),    // time source (tests, skew) / 时间源（测试、时钟偏移）
  onStateChanged: (state) => debugPrint('$state'), // observe every emission / 观察每次状态
);
```

| Knob | Where | Effect |
|------|-------|--------|
| Backend endpoints & auth scheme | `AuthStrategy` | What `login`/`refresh`/… actually do / `login`/`refresh` 等的实际行为 |
| Token persistence | `TokenStore` | Disk / secure storage / in-memory / 磁盘/安全存储/内存 |
| Refresh timing | `AuthSession.expiresAt` + `autoRefreshAhead` | Proactive renewal is scheduled that far before expiry / 在过期前该时长调度主动续期 |
| Renewal retry | `autoRefreshRetryDelay` | After a *proactive* renewal fails, it is re-armed this much later (default 30s) while a session still exists / 主动续期失败后按此时长重新排程（默认 30 秒），会话仍在才重试 |
| Observation | `onStateChanged` | Optional callback for every emitted state, for logging or analytics / 可选回调，每次发出状态时触发，便于日志或埋点 |
| Refresh failure handling | `refreshFailurePolicy` | Whether a failed refresh signs the user out / 刷新失败是否让用户登出 |
| Time source | `clock` | Drives expiry maths and proactive scheduling; inject one for deterministic tests or to tolerate device clock skew / 驱动过期计算与主动刷新调度；注入时钟可实现确定性测试或容忍设备时钟偏移 |
| Token injection | `AuthTokenSource` / `validAccessToken()` | How the bearer token reaches HTTP clients, optionally renewing an expired token first / 令牌如何到达 HTTP 客户端，必要时先续期过期令牌 |

## Refresh strategy / 刷新策略

`refresh()` is **single-flight** by construction: concurrent callers share one in-flight request. You decide *when* to refresh:

`refresh()` 天生**单飞**：并发调用方共享同一次进行中的请求。*何时*刷新由你决定：

- Proactively, when `session.isExpired` is approaching, before a request. / 在请求前、当 `session.isExpired` 临近时主动刷新。
- Reactively, on a `401` from your API (see [Network Integration](Network-Integration)). / 响应式地，在 API 返回 `401` 时刷新。

A failed refresh is always reported through `AuthError` (and the rethrown future),
but whether it **ends the session** is decided by `refreshFailurePolicy`. See
**Refresh failure policy** below.

刷新失败总会通过 `AuthError`（以及重新抛出的 future）上报，但是否**终止会话**由
`refreshFailurePolicy` 决定，详见下方「刷新失败策略」。

## Refresh failure policy / 刷新失败策略

The default policy signs the user out only for failures that can never succeed
again, keeping the session when the failure looks transient (so a network blip
does not log people out):

默认策略仅在失败「注定无法重试成功」时让用户登出；看起来像瞬时故障时保留会话（避免一次
网络抖动就把人踢下线）：

| Failure / 失败类型 | Default outcome / 默认结果 |
|---|---|
| `SessionExpiredException`, `InvalidCredentialsException` | Store cleared → `Unauthenticated` / 清空存储 → `Unauthenticated` |
| Anything else (network, 5xx…) / 其它（网络、5xx 等） | Session kept → back to `Authenticated` / 保留会话 → 回到 `Authenticated` |

```dart
// Never sign out on a failed refresh — useful when refresh tokens are
// long-lived and your backend is occasionally flaky.
// 刷新失败也绝不登出——适用于刷新令牌长期有效、后端偶尔不稳定的场景。
final auth = AuthManager(
  strategy: strategy,
  refreshFailurePolicy: (AppException error) => false,
);
```

Proactive (background) refresh failures are handled internally, so a scheduled
renewal can never surface as an unhandled async error.

主动（后台）刷新的失败会在内部处理，因此定时续期永远不会以未处理异步错误的形式泄漏。

## No global singletons / 没有全局单例

`AuthManager` is a plain object — create one per app, hold it in your DI container or a top-level variable. The core has no static mutable state.

`AuthManager` 是一个普通对象——每个应用创建一个，放在 DI 容器或顶层变量中即可。内核没有静态可变状态。

## Next Steps / 下一步

- [Usage](Usage) — Putting it together / 综合使用
- [FAQ](FAQ) — Common questions / 常见问题
