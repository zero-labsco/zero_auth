# Backend Strategy / 后端策略

`AuthStrategy` is the **only** boundary the core needs from a backend. Implement four methods and `zero_auth` works with REST, gRPC, Firebase, or a private RPC.

`AuthStrategy` 是内核向后台要求的**唯一**边界。实现四个方法后，`zero_auth` 即可对接 REST、gRPC、Firebase 或私有 RPC。

## The contract / 契约

```dart
abstract class AuthStrategy {
  Future<AuthSession> login(Credentials credentials);
  Future<AuthSession> register(RegistrationInput input);
  Future<void> logout(SessionHandle handle);
  Future<AuthSession> refresh(RefreshToken token);
}
```

| Method | When called | Receives | Must return |
|--------|-----------|----------|-------------|
| `login` | `AuthManager.login` | `Credentials(username, password)` | A fresh `AuthSession` |
| `register` | `AuthManager.register` | `RegistrationInput(username, password, displayName?, email?)` | A fresh `AuthSession` |
| `logout` | `AuthManager.logout` | `SessionHandle(userId, refreshToken?)` | `void` (revoke server-side if applicable) |
| `refresh` | `AuthManager.refresh` | `RefreshToken(value)` | A new `AuthSession` (new tokens) |

`username` is just a name — it is an opaque identifier, and the core never
validates or interprets it. Put an email or a phone number in it and map it to
whatever field your API expects.

`username` 只是字段名，它是个不透明标识符，内核从不校验或解析它。把邮箱或手机号放进去，
再映射成你接口需要的字段即可。

## What is fixed, and where the escape hatches are / 哪些是固定的，逃生口在哪

The four signatures above are the only thing the contract fixes. Transport, URLs,
token format and rotation are entirely yours.

上面这四个签名是契约唯一固定的东西。传输方式、URL、令牌格式与轮换策略完全由你决定。

| You need | Do this |
|----------|---------|
| Login that is not username + password (SMS code, OAuth, passkey) | `AuthManager.loginWith` — see [Third-Party Login](Third-Party-Login) |
| Extra fixed context (tenant id, app id, device id) | Hold it as a field on your strategy; do not squeeze it into `Credentials` |
| Extra data returned by the backend (roles, tenant, permissions) | Put it in `AuthSession.claims` |
| Signalling *why* a call failed | Throw `AuthException` with a `code` — see [Errors](Errors) |

Gotchas / 注意点:

- **Always set `userId`** when building sessions. `logout` receives
  `userId: session.userId ?? ''`, so a session without one hands your backend an
  empty string (the refresh token is passed too, when present).
  **务必设置 `userId`**：登出时收到的是 `session.userId ?? ''`，没有它后端会拿到空
  字符串（有刷新令牌时会一并传入）。
- **Logging in again does not sign the previous session out.** The new session
  simply replaces it locally; revoking the old one server-side is your call — or
  use [Multiple Accounts](Multi-Account) if both must survive.
  **再次登录不会登出上一个会话**：新会话只是本地替换；是否在服务端吊销旧的由你决定；
  若两者都要保留，请用[多账号](Multi-Account)。

## Mapping failures / 映射失败

Every thrown error should be mapped to `AppException` (or `AuthException` for auth-specific cases). Raw `Exception`s must never cross the public surface — the manager wraps unknowns.

所有抛出的错误都应映射为 `AppException`（认证相关场景用 `AuthException`）。裸 `Exception` 不得越过公共边界——管理器会包裹未知异常。

```dart
@override
Future<AuthSession> login(Credentials credentials) async {
  try {
    final json = await myApi.post('/login', {
      'account': credentials.username,   // email, phone, whatever you accept
      'password': credentials.password,
    });
    return AuthSession.fromJson(json as Map<String, Object?>);
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
