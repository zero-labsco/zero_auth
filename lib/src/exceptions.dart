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
