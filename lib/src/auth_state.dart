import 'error/app_exception.dart';

import 'auth_session.dart';

/// Sealed auth lifecycle state, broadcast as a replay-last stream by [AuthManager].
/// 密封的认证生命周期状态，由 [AuthManager] 以「重放最近值」的流对外广播。
sealed class AuthState {
  const AuthState();

  /// Whether a session is currently active.
  ///
  /// [Refreshing] counts as authenticated: the previous session stays usable
  /// while a refresh is in flight, so UIs must not fall back to a login screen
  /// mid-refresh. Prefer this getter over `state is Authenticated`.
  /// 当前是否已有活动会话。
  ///
  /// [Refreshing] 同样算作已认证：刷新进行中时旧会话仍然可用，因此 UI 不应在刷新
  /// 途中退回登录页。请优先使用此属性，而不是 `state is Authenticated`。
  bool get isAuthenticated => this is Authenticated || this is Refreshing;

  /// Whether an operation is still in flight (login / register / refresh /
  /// logout). Handy for disabling buttons and showing spinners.
  /// 是否仍有操作在进行中（登录 / 注册 / 刷新 / 登出），可用于禁用按钮或显示加载态。
  bool get isBusy =>
      this is Authenticating || this is Refreshing || this is LoggingOut;

  /// The session this state carries, or `null` when it carries none.
  ///
  /// [Authenticated], [Refreshing] and [LoggingOut] all carry one; prefer this
  /// over pattern-matching the three subtypes when all a UI needs is the session.
  /// 该状态携带的会话；不携带时为 `null`。
  ///
  /// [Authenticated]、[Refreshing] 与 [LoggingOut] 都携带会话；当界面只需要会话时，
  /// 请优先使用此属性，而不是对三个子类分别做模式匹配。
  AuthSession? get session => switch (this) {
    Authenticated(:final session) => session,
    Refreshing(:final session) => session,
    LoggingOut(:final session) => session,
    _ => null,
  };
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
  @override
  final AuthSession session;

  const Authenticated(this.session);

  @override
  bool operator ==(Object other) =>
      other is Authenticated && other.session == session;

  @override
  int get hashCode => session.hashCode;
}

/// A refresh is in flight while [session] — the previous, still usable session —
/// is retained. Kept separate from [Authenticated] so UIs can show a subtle
/// "renewing…" indicator without unmounting the signed-in experience.
/// 刷新进行中，同时保留旧的、仍然可用的 [session]。与 [Authenticated] 区分，便于 UI
/// 显示「续期中…」提示，而不必卸载已登录界面。
final class Refreshing extends AuthState {
  @override
  final AuthSession session;

  const Refreshing(this.session);

  @override
  bool operator ==(Object other) =>
      other is Refreshing && other.session == session;

  @override
  int get hashCode => session.hashCode;
}

/// A logout is in flight; [session] is the one being discarded.
/// 登出进行中；[session] 是即将被丢弃的会话。
final class LoggingOut extends AuthState {
  @override
  final AuthSession session;

  const LoggingOut(this.session);

  @override
  bool operator ==(Object other) =>
      other is LoggingOut && other.session == session;

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
