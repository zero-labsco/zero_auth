# Network Integration / 网络集成

`AuthManager` implements `AuthTokenSource`, so HTTP clients can read the current access token **without depending on the manager object**. This keeps your Dio setup decoupled from `zero_auth`.

`AuthManager` 实现了 `AuthTokenSource`，因此 HTTP 客户端可在**不依赖管理器对象**的前提下读取当前访问令牌，使 Dio 配置与 `zero_auth` 解耦。

## `AuthTokenSource` / 令牌源

```dart
abstract class AuthTokenSource {
  String? get accessToken;                                // may be expired / 可能已过期
  Future<String?> validAccessToken({Duration? leeway});    // renewed first / 先续期
}
```

`AuthManager.accessToken` returns the current token, or `null` when unauthenticated — and it may already be expired.

`AuthManager.accessToken` 返回当前令牌；未认证时返回 `null` —— 而且它可能已经过期。

`validAccessToken()` is the one to use before a request: it renews first (reusing
the single-flight refresh) and returns `null` only when there is nothing to send.
`leeway` is how long the token must stay valid for, defaulting to the manager's
`clockSkew` (30s), so a token that would die mid-request is renewed first.

请求之前应当用 `validAccessToken()`：它会在必要时先续期（复用单飞刷新），只有真的无令牌
可发时才返回 `null`。`leeway` 表示令牌必须还能维持有效的时长，默认取管理器的
`clockSkew`（30 秒），因此会在请求途中失效的令牌会被提前续期。

## Dio interceptor / Dio 拦截器

`example/lib/dio_interceptor.dart` ships three ready-to-use interceptors, all of
which accept the `AuthTokenSource` **interface** rather than an `AuthManager`:

`example/lib/dio_interceptor.dart` 提供了三个开箱即用的拦截器，它们都接受
`AuthTokenSource` **接口**而非 `AuthManager`：

| Interceptor | Reads | Use when / 适用场景 |
|---|---|---|
| `RefreshingAuthInterceptor` | `validAccessToken()` | The default choice — never sends an expired token / 默认选择，绝不发送过期令牌 |
| `AuthInterceptor` | `accessToken` | You only need the synchronous read / 只需同步读取 |
| `AuthRetryInterceptor` | `refresh()` then replay | The backend returns 401 for token issues / 后端对令牌问题返回 401 |

`RefreshingAuthInterceptor` and `AuthRetryInterceptor` extend `QueuedInterceptor`,
so concurrent requests share one refresh instead of each triggering its own.

`RefreshingAuthInterceptor` 与 `AuthRetryInterceptor` 继承 `QueuedInterceptor`，
因此并发请求会共享同一次刷新，而不是各自触发一次。

```dart
final dio = Dio()
  ..interceptors.add(RefreshingAuthInterceptor(authManager));
```

> `AuthInterceptor` reads the synchronous `accessToken`, which may already be
> expired. Prefer `RefreshingAuthInterceptor` whenever the token reaches a server.
>
> `AuthInterceptor` 读取同步的 `accessToken`，它可能已经过期。只要令牌要发往服务端，
> 就应优先使用 `RefreshingAuthInterceptor`。

### Handling `401` / 处理 401

When a `401` comes back, refresh the session and replay the request once. A failed
refresh always emits `AuthError`, but it does **not** necessarily end the session:
`refreshFailurePolicy` decides whether the failure is terminal (clear the session,
route back to login) or transient (keep the session and retry later).

当返回 `401` 时，刷新会话并把请求重放一次。刷新失败总会发出 `AuthError`，但**不一定**
终止会话：由 `refreshFailurePolicy` 判定失败是终局的（清空会话、跳转登录）还是瞬时的
（保留会话、稍后重试）。

`AuthRetryInterceptor` does exactly that, and guards against a retry loop with a
per-request `retried` flag:

`AuthRetryInterceptor` 正是做这件事，并用 per-request 的 `retried` 标记防止重试风暴：

```dart
final dio = Dio()
  ..interceptors.add(
    AuthRetryInterceptor(manager: authManager, dio: dio),
  );
```

## Other HTTP clients / 其它客户端

Because `AuthTokenSource` is a plain interface, the same pattern works for `package:http`, `chopper`, or any client that lets you mutate request headers.

由于 `AuthTokenSource` 是普通接口，同样的模式适用于 `package:http`、`chopper` 或任何允许修改请求头的客户端。

## Next Steps / 下一步

- [Usage](Usage) — Full integration walkthrough / 完整集成讲解
- [Errors](Errors) — Handling `401` and refresh failures / 处理 401 与刷新失败
