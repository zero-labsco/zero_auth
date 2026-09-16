import 'dart:async';

import 'auth_session.dart';
import 'auth_state.dart';
import 'auth_strategy.dart';
import 'auth_token_source.dart';
import 'error/app_exception.dart';
import 'exceptions.dart';
import 'token_store.dart';

/// Orchestrates the auth state machine and session lifecycle.
///
/// A pure-Dart, headless core: wire your backend via [AuthStrategy] and your
/// persistence via [TokenStore]. It also *is* an [AuthTokenSource], so network
/// layers can attach bearer tokens directly.
/// 编排认证状态机与会话生命周期。纯 Dart 无头内核：通过 [AuthStrategy] 接入后端，
/// 通过 [TokenStore] 接入持久化；本身即 [AuthTokenSource]，便于网络层附加令牌。
final class AuthManager implements AuthTokenSource {
  final AuthStrategy strategy;
  final TokenStore tokenStore;

  AuthState _state = const Unauthenticated();
  final StreamController<AuthState> _controller =
      StreamController<AuthState>.broadcast();

  Completer<AuthSession>? _refreshCompleter;
  Timer? _autoRefreshTimer;

  /// Creates a manager. Defaults to [InMemoryTokenStore].
  ///
  /// Pass [autoRefreshAhead] to enable proactive refresh: when a session carries
  /// both an [AuthSession.expiresAt] and a refresh token, the manager schedules a
  /// single [refresh] call that many minutes before expiry, so callers rarely hit
  /// an expired access token. Defaults to `null` (disabled).
  /// 创建管理器，默认使用 [InMemoryTokenStore]。
  ///
  /// 传入 [autoRefreshAhead] 可开启「临近过期自动刷新」：当会话同时带有
  /// [AuthSession.expiresAt] 与刷新令牌时，管理器会在过期前该时长调度一次
  /// [refresh]，从而让调用方几乎不会撞上过期的访问令牌。默认 `null`（关闭）。
  AuthManager({
    required this.strategy,
    TokenStore? tokenStore,
    Duration? autoRefreshAhead,
  })  : tokenStore = tokenStore ?? InMemoryTokenStore(),
        _autoRefreshAhead = autoRefreshAhead;

  final Duration? _autoRefreshAhead;

  /// The current state (always available, replay-last).
  /// 当前状态（始终可用，重放最近值）。
  AuthState get current => _state;

  /// State stream that replays the last value to every new listener.
  /// 状态流，对每个新订阅者重放最近值。
  Stream<AuthState> get state {
    final sc = StreamController<AuthState>();
    sc.add(_state);
    final sub = _controller.stream.listen(
      sc.add,
      onError: sc.addError,
      onDone: sc.close,
    );
    sc.onCancel = sub.cancel;
    return sc.stream;
  }

  /// The active session, or `null` when not authenticated.
  /// 当前活动会话；未认证时为 `null`。
  AuthSession? get currentSession =>
      _state is Authenticated ? (_state as Authenticated).session : null;

  @override
  String? get accessToken => currentSession?.accessToken;

  /// Restore a persisted session at startup.
  /// 启动时恢复持久化会话。
  Future<void> restore() async {
    final session = await tokenStore.load();
    if (session == null) {
      _emit(const Unauthenticated());
    } else {
      _activate(session);
    }
  }

  /// Log in: emits [Authenticating] → [Authenticated] (or [AuthError] on failure).
  /// 登录：先发 [Authenticating]，成功发 [Authenticated]，失败发 [AuthError]。
  Future<Authenticated> login(Credentials credentials) async {
    _emit(const Authenticating());
    try {
      final session = await strategy.login(credentials);
      await tokenStore.save(session);
      final next = Authenticated(session);
      _activate(session);
      return next;
    } catch (e, st) {
      final err = _toAppException(e, st);
      _emit(AuthError(err));
      throw err;
    }
  }

  /// Register a new account and return its first session.
  /// 注册新账户并返回首个会话。
  Future<Authenticated> register(RegistrationInput input) async {
    _emit(const Authenticating());
    try {
      final session = await strategy.register(input);
      await tokenStore.save(session);
      final next = Authenticated(session);
      _activate(session);
      return next;
    } catch (e, st) {
      final err = _toAppException(e, st);
      _emit(AuthError(err));
      throw err;
    }
  }

  /// Log out: notify the backend, clear storage, emit [Unauthenticated].
  /// 登出：通知后端、清空存储、发 [Unauthenticated]。
  Future<void> logout() async {
    _autoRefreshTimer?.cancel();
    final session = currentSession;
    if (session != null) {
      try {
        await strategy.logout(SessionHandle(userId: session.userId ?? ''));
      } catch (_) {
        // Best-effort: a backend logout failure must not block local logout.
        // 尽力而为：后端登出失败不应阻断本地登出。
      }
    }
    await tokenStore.clear();
    _emit(const Unauthenticated());
  }

  /// Refresh the session. Concurrent callers share a single backend call
  /// (single-flight).
  /// 刷新会话。并发调用方共享同一次后端调用（单飞）。
  Future<AuthSession> refresh() {
    if (_refreshCompleter != null) return _refreshCompleter!.future;
    final completer = Completer<AuthSession>();
    _refreshCompleter = completer;
    () async {
      try {
        final session = currentSession;
        if (session == null) {
          throw AuthException('Cannot refresh without a session');
        }
        if (session.refreshToken == null) {
          throw AuthException('Session has no refresh token');
        }
        final refreshed = await strategy.refresh(session.refreshToken!);
        await tokenStore.save(refreshed);
        _activate(refreshed);
        completer.complete(refreshed);
      } catch (e, st) {
        completer.completeError(_toAppException(e, st));
      } finally {
        _refreshCompleter = null;
      }
    }();
    return completer.future;
  }

  /// Release internal resources. Call when the manager is no longer used.
  /// 释放内部资源。不再使用时调用。
  Future<void> dispose() {
    _autoRefreshTimer?.cancel();
    return _controller.close();
  }

  void _activate(AuthSession session) {
    _emit(Authenticated(session));
    _scheduleAutoRefresh(session);
  }

  /// Schedule a one-shot [refresh] [autoRefreshAhead] before [AuthSession.expiresAt].
  /// No-op when proactive refresh is disabled, or the session lacks an expiry or
  /// a refresh token.
  /// 在 [AuthSession.expiresAt] 之前 [autoRefreshAhead] 调度一次 [refresh]。
  /// 当未开启主动刷新、或会话缺少过期时间 / 刷新令牌时为空操作。
  void _scheduleAutoRefresh(AuthSession session) {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    final ahead = _autoRefreshAhead;
    if (ahead == null ||
        session.expiresAt == null ||
        session.refreshToken == null) {
      return;
    }
    final delay = session.expiresAt!.difference(DateTime.now()) - ahead;
    if (delay <= Duration.zero) {
      unawaited(refresh());
      return;
    }
    _autoRefreshTimer = Timer(delay, () => unawaited(refresh()));
  }

  void _emit(AuthState state) {
    _state = state;
    if (!_controller.isClosed) _controller.add(state);
  }

  AppException _toAppException(Object e, StackTrace? st) => e is AppException
      ? e
      : AuthException('Unexpected auth failure', cause: e);
}
