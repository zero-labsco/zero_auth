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

`example/lib/dio_interceptor.dart` ships a ready-to-use interceptor:

`example/lib/dio_interceptor.dart` 提供了一个开箱即用的拦截器：

```dart
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this.tokens); // an AuthTokenSource / 一个令牌源
  final AuthTokenSource tokens;

  @override
  void onRequest(RequestOptions o, RequestInterceptorHandler h) async {
    final t = await tokens.validAccessToken(); // renews first / 先续期
    if (t != null) o.headers['Authorization'] = 'Bearer $t';
    h.next(o);
  }
}
```

> If you only want the synchronous read, use `tokens.accessToken` — but remember
> it may hand you a token that has already expired.
> 若只需要同步读取，可用 `tokens.accessToken` —— 但请记住它可能返回一个已过期的令牌。

```dart
final dio = Dio()
  ..interceptors.add(AuthInterceptor(authManager));
```

When a `401` is returned, refresh the session and retry; if refresh fails, the manager emits `AuthError` and your app routes back to login.

当返回 `401` 时，刷新会话并重试；若刷新失败，管理器会发出 `AuthError`，应用随之跳转登录。

`example/lib/dio_interceptor.dart` also ships `AuthRetryInterceptor`, which does
exactly that — refreshes through the manager (single-flight) and replays the
request **once**, so a retry loop cannot form:

`example/lib/dio_interceptor.dart` 里还提供了 `AuthRetryInterceptor`，正是做这件事 ——
通过管理器刷新（单飞）并把请求**重试一次**，因此不会形成重试风暴：

```dart
final dio = Dio()
  ..interceptors.add(
    AuthRetryInterceptor(manager: authManager, dio: dio),
  );
```

Two more interceptor variants there / 那里还有另外两种拦截器：

- `RefreshingAuthInterceptor` — never sends an expired token: it renews first via
  `validAccessToken()` / 绝不发送过期令牌，先用 `validAccessToken()` 续期。
- `AuthInterceptor` — the plain `AuthTokenSource` version / 基础的令牌源版本。

## Other HTTP clients / 其它客户端

Because `AuthTokenSource` is a plain interface, the same pattern works for `package:http`, `chopper`, or any client that lets you mutate request headers.

由于 `AuthTokenSource` 是普通接口，同样的模式适用于 `package:http`、`chopper` 或任何允许修改请求头的客户端。

## Next Steps / 下一步

- [Usage](Usage) — Full integration walkthrough / 完整集成讲解
- [Errors](Errors) — Handling `401` and refresh failures / 处理 401 与刷新失败
