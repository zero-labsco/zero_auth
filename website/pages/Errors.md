# Errors / 错误

`zero_auth` never lets a raw `Exception` cross its public surface. Every failure is expressed through one of two mechanisms.

`zero_auth` 绝不允许裸 `Exception` 越过公共边界。每个失败都通过下面两种机制之一表达。

## `AppException` / 异常类型

All domain failures extend `AppException`:

所有领域失败都继承 `AppException`：

```dart
sealed class AppException implements Exception {
  final String code;       // stable, machine-readable / 稳定、机器可读
  final String message;    // human-readable / 人类可读
  final Object? cause;     // original error, if any / 原始错误
}

final class AuthException extends AppException {
  // Base type for every auth failure / 所有认证失败的基类型
}

// Concrete subtypes — catch these to branch on what actually went wrong.
// 具体子类型——捕获它们即可按实际错误分支处理。
final class InvalidCredentialsException extends AuthException {} // invalid_credentials / 凭据无效
final class SessionExpiredException extends AuthException {}     // session_expired / 会话过期
final class NoActiveSessionException extends AuthException {}    // no_active_session / 无活动会话
final class RefreshTokenMissingException extends AuthException {} // refresh_token_missing / 缺少刷新令牌
final class UnexpectedAuthException extends AuthException {}     // unexpected_auth_failure / 意外失败
```

`AuthStrategy` authors opt into these subtypes simply by throwing an
`AuthException` carrying the matching `code`; `mapAuthFailure` performs the
mapping, preserving any vocabulary it does not recognise.

`AuthStrategy` 实现者只需抛出携带对应 `code` 的 `AuthException` 即可参与映射；
`mapAuthFailure` 负责转换，并保留它无法识别的自定义错误类型。

| code | Mapped type / 映射结果 |
|------|------------------------|
| `invalid_credentials` | `InvalidCredentialsException` |
| `invalid_grant`, `invalid_refresh_token`, `token_expired`, `session_expired` | `SessionExpiredException` |
| `no_active_session` | `NoActiveSessionException` |
| `refresh_token_missing` | `RefreshTokenMissingException` |
| anything else / 其它 | preserved as-is, or `UnexpectedAuthException` / 原样保留或包装为 `UnexpectedAuthException` |

Codes raised by the manager itself (not your strategy) / 由管理器自身产生的 code：

| code | Raised when / 何时触发 |
|------|------------------------|
| `auth_flow_in_progress` | Another `login` / `register` / `loginWith` is already running / 已有登录流程在执行 |
| `manager_disposed` | An operation is called after `dispose()` / `dispose()` 后又调用操作 |

> Overlapping authentication flows are rejected rather than racing: a second
> `login()` while one is in flight throws `auth_flow_in_progress`.
>
> 重叠的登录流程会被拒绝而非争抢：进行中再次 `login()` 会抛 `auth_flow_in_progress`。

`AuthStrategy` implementations should map transport/API errors into `AuthException` (or a custom `AppException` subclass) so callers get a stable `code`.

`AuthStrategy` 实现方应将传输层/API 错误映射为 `AuthException`（或自定义 `AppException` 子类），让调用方拿到稳定的 `code`。

## `Result<T>` / 结果类型

For explicit, exception-free handling, use `Result`:

如需显式、无异常的处理，可使用 `Result`：

```dart
sealed class Result<T> {
  const factory Result.ok(T value) = Ok<T>;
  const factory Result.err(AppException error) = Err<T>;
}
```

```dart
final result = await auth.tryLogin(user, pass); // returns Result<AuthSession>
switch (result) {
  case Ok(:final value):
    /* authenticated / 已认证 */
  case Err(:final error):
    /* inspect error.code / 读取 error.code */
}
```

## How failures surface / 失败如何呈现

| Situation | Surfaced as |
|-----------|-------------|
| `login`/`register` fails | `AuthState` becomes `AuthError(error)` **and** the future throws `AppException` / 状态变为 `AuthError`，且 future 抛出 `AppException` |
| `refresh` fails | `AuthError(error)` emitted, then `Unauthenticated` (unrecoverable) or back to `Authenticated` (transient) per the [failure policy](Configuration#refresh-failure-policy) / 发出 `AuthError`，随后按[失败策略](Configuration#refresh-failure-policy)转为 `Unauthenticated`（不可恢复）或回到 `Authenticated`（瞬时） |
| `restore()` finds nothing | Stays `Unauthenticated` (not an error) / 保持 `Unauthenticated`（不算错误） |
| `TokenStore.load()` throws | Mapped to `AppException`, treated as "no session" / 映射为 `AppException`，按"无会话"处理 |

## Next Steps / 下一步

- [Backend Strategy](Backend-Strategy) — Map your API errors / 映射你的 API 错误
- [Configuration](Configuration) — Tuning refresh & retry / 调优刷新与重试
