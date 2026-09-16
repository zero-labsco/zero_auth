# Network Integration / 网络集成

`AuthManager` implements `AuthTokenSource`, so HTTP clients can read the current access token **without depending on the manager object**. This keeps your Dio setup decoupled from `zero_auth`.

`AuthManager` 实现了 `AuthTokenSource`，因此 HTTP 客户端可在**不依赖管理器对象**的前提下读取当前访问令牌，使 Dio 配置与 `zero_auth` 解耦。

## `AuthTokenSource` / 令牌源

```dart
abstract class AuthTokenSource {
  Future<String?> get accessToken;
}
```

`AuthManager.accessToken` returns the current token, or `null` when unauthenticated. It can also trigger a transparent refresh when the token is near expiry (implementation-dependent).

`AuthManager.accessToken` 返回当前令牌；未认证时返回 `null`。在令牌接近过期时，它还可触发一次透明的刷新（取决于实现）。

## Dio interceptor / Dio 拦截器

`example/lib/dio_interceptor.dart` ships a ready-to-use interceptor:

`example/lib/dio_interceptor.dart` 提供了一个开箱即用的拦截器：

```dart
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this.tokens); // an AuthTokenSource
  final AuthTokenSource tokens;

  @override
  void onRequest(RequestOptions o, RequestInterceptorHandler h) async {
    final t = await tokens.accessToken;
    if (t != null) o.headers['Authorization'] = 'Bearer $t';
    h.next(o);
  }
}
```

```dart
final dio = Dio()
  ..interceptors.add(AuthInterceptor(authManager));
```

When a `401` is returned, refresh the session and retry; if refresh fails, the manager emits `AuthError` and your app routes back to login.

当返回 `401` 时，刷新会话并重试；若刷新失败，管理器会发出 `AuthError`，应用随之跳转登录。

## Other HTTP clients / 其它客户端

Because `AuthTokenSource` is a plain interface, the same pattern works for `package:http`, `chopper`, or any client that lets you mutate request headers.

由于 `AuthTokenSource` 是普通接口，同样的模式适用于 `package:http`、`chopper` 或任何允许修改请求头的客户端。

## Next Steps / 下一步

- [Usage](Usage) — Full integration walkthrough / 完整集成讲解
- [Errors](Errors) — Handling `401` and refresh failures / 处理 401 与刷新失败
