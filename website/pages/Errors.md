# Errors / 错误

`zero_auth` never lets a raw `Exception` cross its public surface. Every failure is expressed through one of two mechanisms.

`zero_auth` 绝不允许裸 `Exception` 越过公共边界。每个失败都通过下面两种机制之一表达。

## `AppException` / 异常类型

All domain failures extend `AppException`:

所有领域失败都继承 `AppException`：

```dart
abstract class AppException implements Exception {
  final String? code;      // stable, machine-readable / 稳定、机器可读
  final String message;    // human-readable / 人类可读
  final Object? cause;     // original error, if any / 原始错误，如有
}

class AuthException extends AppException {
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
`AuthException` — or the bare `AuthFail` domain type — carrying the matching
`code`; `mapAuthFailure` performs the mapping, preserving any vocabulary it does
not recognise.

`AuthStrategy` 实现者只需抛出携带对应 `code` 的 `AuthException` —— 或裸的领域类型
`AuthFail` —— 即可参与映射；`mapAuthFailure` 负责转换，并保留它无法识别的自定义错误类型。

```dart
// Both of these map to InvalidCredentialsException / 两者都会映射为 InvalidCredentialsException
throw AuthException('Wrong password', code: 'invalid_credentials');
throw const AuthFail('Wrong password', code: 'invalid_credentials');
```

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
| `session_persist_failed` | The session could not be written to the `TokenStore` (retried once first) / 会话无法写入 `TokenStore`（已先重试一次） |
| `manager_disposed` | An operation is called after `dispose()` / `dispose()` 后又调用操作 |

> Overlapping authentication flows are rejected rather than racing: a second
> `login()` while one is in flight throws `auth_flow_in_progress`.
>
> 重叠的登录流程会被拒绝而非争抢：进行中再次 `login()` 会抛 `auth_flow_in_progress`。

`AuthStrategy` implementations should map transport/API errors into `AuthException` (or a custom `AppException` subclass) so callers get a stable `code`.

`AuthStrategy` 实现方应将传输层/API 错误映射为 `AuthException`（或自定义 `AppException` 子类），让调用方拿到稳定的 `code`。

## `Result<T>` / 结果类型

For explicit, exception-free handling, use `Result` — a sealed `Ok` / `Err` pair you construct directly:

如需显式、无异常的处理，可使用 `Result` —— 直接构造的密封 `Ok` / `Err` 组合：

```dart
sealed class Result<T> {
  const Result();
  T get getOrThrow;                    // value, or throws the failure / 取值，或抛出失败
  Result<R> map<R>(R Function(T value) transform);
  bool get isOk;
  bool get isErr;
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.error);
  final Object error;                  // usually an AppException / 通常是 AppException
  AppException? get appException;      // the mapped domain error / 映射后的领域错误
}
```

Three operations return one out of the box — `tryLogin()`, `tryRefresh()` and
`tryRestore()` are the same code paths as their throwing twins, with the outcome
delivered as a `Result` instead of an exception:

三个操作开箱即用地返回 `Result` —— `tryLogin()`、`tryRefresh()` 与 `tryRestore()`
与各自的抛异常版本共用同一条代码路径，只是把结果以 `Result` 交付而非异常：

```dart
// Ok carries the Authenticated state that was installed.
// Ok 携带被安装的 Authenticated 状态。
final result = await auth.tryLogin(credentials);

switch (result) {
  case Ok(:final value):
    // value is the Authenticated state; value.session is the AuthSession
    // value 即 Authenticated 状态；value.session 是 AuthSession
    print('signed in as ${value.session.userId}');
  case Err(:final error):
    // inspect error.code — the same AppException AuthError carries
    // 读取 error.code —— 与 AuthError 携带的是同一个 AppException
    print('failed: $error');
}
```

Both styles share one path: the failure is emitted as `AuthError` **and**
rethrown by the throwing variant, so mixing them is safe.
两种风格共用一条路径：失败会以 `AuthError` 发出，**并且**由抛异常版本重新抛出，
因此混用两者是安全的。

## How failures surface / 失败如何呈现

| Situation | Surfaced as |
|-----------|-------------|
| `login`/`register` fails | `AuthState` becomes `AuthError(error)` **and** the future throws `AppException` / 状态变为 `AuthError`，且 future 抛出 `AppException` |
| `refresh` fails | `AuthError(error)` emitted, then `Unauthenticated` (unrecoverable) or back to `Authenticated` (transient) per the [failure policy](Configuration#refresh-failure-policy) / 发出 `AuthError`，随后按[失败策略](Configuration#refresh-failure-policy)转为 `Unauthenticated`（不可恢复）或回到 `Authenticated`（瞬时） |
| `restore()` finds nothing | Stays `Unauthenticated` (not an error) / 保持 `Unauthenticated`（不算错误） |
| `restore()` renewal fails transiently | Session **kept** (the next `validAccessToken()` retries); only a terminal failure clears the store / **保留**会话（下次 `validAccessToken()` 会重试）；只有终局失败才清空存储 |
| `TokenStore.load()` throws | Mapped to `AppException`, treated as "no session" / 映射为 `AppException`，按"无会话"处理 |

## Next Steps / 下一步

- [Backend Strategy](Backend-Strategy) — Map your API errors / 映射你的 API 错误
- [Configuration](Configuration) — Tuning refresh & retry / 调优刷新与重试
