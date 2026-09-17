# Backend Strategy / 后端策略

`AuthStrategy` is the **only** boundary the core needs from a backend. Implement four methods and `zero_auth` works with REST, gRPC, Firebase, or a private RPC.

`AuthStrategy` 是内核向后台要求的**唯一**边界。实现四个方法后，`zero_auth` 即可对接 REST、gRPC、Firebase 或私有 RPC。

## The contract / 契约

```dart
abstract class AuthStrategy {
  Future<AuthSession> login(String username, String password);
  Future<AuthSession> register(String username, String password);
  Future<void> logout(AuthSession session);
  Future<AuthSession> refresh(AuthSession session);
}
```

| Method | When called | Must return |
|--------|-----------|-------------|
| `login` | `AuthManager.login` | A fresh `AuthSession` |
| `register` | `AuthManager.register` | A fresh `AuthSession` |
| `logout` | `AuthManager.logout` | `void` (revoke server-side if applicable) |
| `refresh` | `AuthManager.refresh` | A new `AuthSession` (new tokens) |

## Mapping failures / 映射失败

Every thrown error should be mapped to `AppException` (or `AuthException` for auth-specific cases). Raw `Exception`s must never cross the public surface — the manager wraps unknowns.

所有抛出的错误都应映射为 `AppException`（认证相关场景用 `AuthException`）。裸 `Exception` 不得越过公共边界——管理器会包裹未知异常。

```dart
Future<AuthSession> login(String u, String p) async {
  try {
    final json = await myApi.post('/login', {'u': u, 'p': p});
    return AuthSession.fromJson(json);
  } on MyApiAuthError catch (e) {
    throw AuthException(code: 'invalid_credentials', message: e.message);
  }
}
```

## Building the session / 构造会话

Return an `AuthSession` carrying at least the access token, the refresh token, and an expiry:

返回 `AuthSession`，至少包含访问令牌、刷新令牌与过期时间：

```dart
AuthSession(
  accessToken: json['access'],
  refreshToken: json['refresh'],
  expiresAt: DateTime.parse(json['expiresAt']),
  userId: json['userId'],
  displayName: json['displayName'],
  claims: json, // optional raw claims / 可选的原始 claims
)
```

## Example backend / 演示后端

`server/` is a layered `dart:io` demo backend exercising `/login`, `/refresh`, `/logout`, `/me` and `/health`. Run it with `dart run bin/server.dart` on port `8080`. It issues real HMAC-SHA256 JWTs with refresh-token rotation and replay detection, and logs every request with its status and duration. The demo account is `user` / `user`.

`server/` 是一个分层的 `dart:io` 演示后端，提供 `/login`、`/refresh`、`/logout`、`/me` 与 `/health`。用 `dart run bin/server.dart` 在 `8080` 端口启动。它签发真实的 HMAC-SHA256 JWT，带刷新令牌轮换与重放检测，并记录每条请求的状态码与耗时。演示账号为 `user` / `user`。

## Next Steps / 下一步

- [Token Store](Token-Store) — Where sessions are persisted / 会话持久化到何处
- [Network Integration](Network-Integration) — Attaching the bearer token / 附加 Bearer 令牌
