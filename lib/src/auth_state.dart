import 'error/app_exception.dart';

import 'auth_session.dart';

/// Sealed auth lifecycle state, broadcast as a replay-last stream by [AuthManager].
/// 密封的认证生命周期状态，由 [AuthManager] 以「重放最近值」的流对外广播。
sealed class AuthState {
  const AuthState();

  /// Whether a session is currently active.
  /// 当前是否已有活动会话。
  bool get isAuthenticated => this is Authenticated;
}

/// No active session.
/// 无活动会话。
final class Unauthenticated extends AuthState {
  const Unauthenticated();

  @override
  bool operator ==(Object other) => other is Unauthenticated;

  @override
  int get hashCode => 0;
}

/// A login / register / refresh is in flight.
/// 登录 / 注册 / 刷新进行中。
final class Authenticating extends AuthState {
  const Authenticating();

  @override
  bool operator ==(Object other) => other is Authenticating;

  @override
  int get hashCode => 1;
}

/// A session is active.
/// 会话处于活动状态。
final class Authenticated extends AuthState {
  final AuthSession session;

  const Authenticated(this.session);

  @override
  bool operator ==(Object other) =>
      other is Authenticated && other.session == session;

  @override
  int get hashCode => session.hashCode;
}

/// Terminal error state; the manager surfaces [AppException]s through this.
/// 终结错误态；管理器通过它暴露 [AppException]。
final class AuthError extends AuthState {
  final AppException error;

  const AuthError(this.error);

  @override
  bool operator ==(Object other) => other is AuthError && other.error == error;

  @override
  int get hashCode => error.hashCode;
}

/// Domain failure before it is mapped into [AuthException].
/// 在映射为 [AuthException] 之前的领域失败。
final class AuthFail {
  final String message;
  final String? code;
  final Object? cause;

  const AuthFail(this.message, {this.code, this.cause});
}
