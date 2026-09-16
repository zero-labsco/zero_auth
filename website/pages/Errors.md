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
  // auth-specific cases: invalid_credentials, session_expired, …
  // 认证相关场景：invalid_credentials、session_expired 等
}
```

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
| `refresh` fails | Session cleared; `AuthError(error)` emitted / 会话清空，发出 `AuthError` |
| `restore()` finds nothing | Stays `Unauthenticated` (not an error) / 保持 `Unauthenticated`（不算错误） |
| `TokenStore.load()` throws | Mapped to `AppException`, treated as "no session" / 映射为 `AppException`，按"无会话"处理 |

## Next Steps / 下一步

- [Backend Strategy](Backend-Strategy) — Map your API errors / 映射你的 API 错误
- [Configuration](Configuration) — Tuning refresh & retry / 调优刷新与重试
