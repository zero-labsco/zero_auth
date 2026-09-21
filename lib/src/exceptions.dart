import 'error/app_exception.dart';

import 'auth_state.dart';

/// The `zero_auth` mapping of a domain [AuthFail] into the unified
/// [AppException] type from this package's error kernel.
/// 将领域 [AuthFail] 映射为本包统一错误内核的 [AppException] 类型。
///
/// Always surface auth errors to the UI through this type (never a raw
/// [Exception]) so all `zero_*` packages share one error vocabulary.
/// 始终通过此类型向 UI 暴露认证错误（切勿用裸 [Exception]），使所有 `zero_*` 包共用一套错误词汇。
class AuthException extends AppException {
  /// The originating [AuthFail].
  /// 原始的 [AuthFail]。
  final AuthFail fail;

  AuthException.fromFail(this.fail)
      : super(fail.message, code: fail.code, cause: fail.cause);

  /// Convenience constructor for manager-internal failures.
  /// 供管理器内部失败使用的便捷构造。
  AuthException(String message, {String? code, Object? cause})
      : this.fromFail(AuthFail(message, code: code, cause: cause));
}

/// Credentials were rejected by the backend (wrong password, unknown user…).
/// Retrying the same credentials fails again.
/// 凭据被后端拒绝（密码错误、用户不存在……）。用相同凭据重试依然失败。
final class InvalidCredentialsException extends AuthException {
  InvalidCredentialsException({
    String message = 'Invalid credentials',
    Object? cause,
  }) : super(message, code: 'invalid_credentials', cause: cause);
}

/// The grant is no longer usable: the session, refresh token or access token
/// expired or was revoked. The only way forward is a fresh login.
/// 授权已不可用：会话 / 刷新令牌 / 访问令牌已过期或被吊销，只能重新登录。
final class SessionExpiredException extends AuthException {
  SessionExpiredException({String message = 'Session expired', Object? cause})
      : super(message, code: 'session_expired', cause: cause);
}

/// An operation that requires an active session was called with none.
/// 需要活动会话的操作被调用时没有活动会话。
final class NoActiveSessionException extends AuthException {
  NoActiveSessionException({
    String message = 'No active session',
    Object? cause,
  }) : super(message, code: 'no_active_session', cause: cause);
}

/// A refresh was requested for a session that carries no refresh token.
/// 会话未携带刷新令牌，却请求了刷新。
final class RefreshTokenMissingException extends AuthException {
  RefreshTokenMissingException({
    String message = 'Session has no refresh token',
    Object? cause,
  }) : super(message, code: 'refresh_token_missing', cause: cause);
}

/// Fallback for anything the mapping cannot classify (transport errors,
/// malformed responses, unexpected SDK failures).
/// 兜底类型，承载无法归类的错误（传输错误、响应格式错误、意料之外的 SDK 失败）。
final class UnexpectedAuthException extends AuthException {
  UnexpectedAuthException({
    String message = 'Unexpected auth failure',
    Object? cause,
  }) : super(message, code: 'unexpected_auth_failure', cause: cause);
}

/// Maps a caught failure into the most specific [AuthException] subclass.
///
/// Strategy authors opt in by throwing an [AuthException] **or** an [AuthFail]
/// carrying one of the codes below; anything unrecognised is preserved, or
/// wrapped as [UnexpectedAuthException].
/// 将捕获的失败映射为最具体的 [AuthException] 子类。
///
/// 策略实现者可抛出携带下列 code 的 [AuthException] **或** [AuthFail] 来参与映射；
/// 无法识别的错误会被原样保留，或包装为 [UnexpectedAuthException]。
///
/// | code | mapped type / 映射结果 |
/// |---|---|
/// | `invalid_credentials` | [InvalidCredentialsException] |
/// | `invalid_grant`, `invalid_refresh_token`, `token_expired`, `session_expired` | [SessionExpiredException] |
/// | `no_active_session` | [NoActiveSessionException] |
/// | `refresh_token_missing` | [RefreshTokenMissingException] |
/// | anything else / 其他 | preserved as-is, or [UnexpectedAuthException] / 原样保留或包装 |
AuthException mapAuthFailure(Object error) {
  final appError = error is AppException ? error : null;
  final fail = error is AuthFail ? error : null;
  if (appError == null && fail == null) {
    return UnexpectedAuthException(cause: error);
  }

  final code = appError?.code ?? fail?.code;
  final message = appError?.message ?? fail!.message;
  final cause = appError?.cause ?? fail?.cause ?? error;

  switch (code) {
    case 'invalid_credentials':
      return InvalidCredentialsException(message: message, cause: cause);
    case 'invalid_grant':
    case 'invalid_refresh_token':
    case 'token_expired':
    case 'session_expired':
      return SessionExpiredException(message: message, cause: cause);
    case 'no_active_session':
      return NoActiveSessionException(message: message, cause: cause);
    case 'refresh_token_missing':
      return RefreshTokenMissingException(message: message, cause: cause);
    default:
      // Unclassifiable: keep whatever vocabulary the author already threw.
      // 无法归类：保留作者原本抛出的错误类型。
      return error is AuthException
          ? error
          : UnexpectedAuthException(message: message, cause: cause);
  }
}
