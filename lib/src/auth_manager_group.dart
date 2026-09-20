import 'dart:async';

import 'auth_manager.dart';
import 'auth_session.dart';
import 'auth_state.dart';
import 'auth_strategy.dart';
import 'auth_token_source.dart';
import 'token_store.dart';

/// Coordinates several signed-in accounts at once.
///
/// Each account gets its own [AuthManager] — and therefore its own session,
/// state machine, refresh scheduling and persistence — while the group tracks
/// which one is currently active.
/// 同时协调多个已登录账号。每个账号拥有自己的 [AuthManager]，因而拥有独立的会话、
/// 状态机、刷新调度与持久化；分组只负责记录当前激活的是哪一个。
///
/// This is an **optional layer**: [AuthManager] stays deliberately single-session
/// ("who is logged in?"). Multi-account is a different question ("of these
/// signed-in identities, which one is active?"), so it lives here instead of
/// complicating the core. If you only need to *switch* between accounts, a
/// logout + login flow is usually simpler than this class.
/// 这是**可选层**：[AuthManager] 刻意保持单会话（回答「谁登录了？」）。多账号是另一个
/// 问题（「这些已登录身份中，哪个是激活的？」），因此放在这里，以免核心变复杂。
/// 若你只需要在账号间切换，登出再登录通常比用这个类更简单。
///
/// The group also implements [AuthTokenSource], so network layers keep depending
/// on one narrow interface and always read the active account's token.
/// 分组同样实现 [AuthTokenSource]，网络层仍只依赖这一个窄接口，读到的始终是激活
/// 账号的令牌。
final class AuthManagerGroup implements AuthTokenSource {
  /// Creates a group. Both factories are called once per account, lazily.
  ///
  /// Give every account its own [TokenStore] instance (for example a secure
  /// store keyed by account id) so persisted sessions stay isolated.
  /// 创建分组。两个工厂方法按账号惰性调用一次。
  ///
  /// 请为每个账号提供独立的 [TokenStore] 实例（例如按账号 id 命名的安全存储），
  /// 以保证持久化会话彼此隔离。
  AuthManagerGroup({
    required AuthStrategy Function(String accountId) strategyFactory,
    required TokenStore Function(String accountId) storeFactory,
  })  : _strategyFactory = strategyFactory,
        _storeFactory = storeFactory;

  /// Called once per account. Returning the same instance for every account is
  /// fine — and typical — since a strategy usually just talks to one backend.
  /// 每个账号调用一次。各账号返回同一个实例也没问题（而且常见），因为策略通常只是
  /// 与同一个后端通信。
  final AuthStrategy Function(String accountId) _strategyFactory;
  final TokenStore Function(String accountId) _storeFactory;

  final Map<String, AuthManager> _managers = {};
  final StreamController<AuthState> _controller =
      StreamController<AuthState>.broadcast();

  StreamSubscription<AuthState>? _activeSubscription;
  String? _activeId;

  /// Ids currently owned by the group.
  /// 分组当前持有的账号 id。
  Iterable<String> get accountIds => _managers.keys;

  /// The active account id, or `null` when none is active.
  /// 当前激活的账号 id；没有激活账号时为 `null`。
  String? get activeId => _activeId;

  /// The active account's manager, or `null` when none is active.
  /// 激活账号的管理器；没有激活账号时为 `null`。
  AuthManager? get active => _activeId == null ? null : _managers[_activeId];

  /// Returns the manager for [accountId], creating it on first use.
  /// 返回 [accountId] 对应的管理器，首次使用时创建。
  AuthManager forAccount(String accountId) => _managers.putIfAbsent(
        accountId,
        () => AuthManager(
          strategy: _strategyFactory(accountId),
          tokenStore: _storeFactory(accountId),
        ),
      );

  /// Makes [accountId] the active account.
  ///
  /// The group's [state] stream switches to that manager and replays its
  /// current state; nothing is signed in or out by this call.
  /// 把 [accountId] 设为激活账号。
  ///
  /// 分组的 [state] 流会切到该管理器并重放其当前状态；此调用不会登录或登出任何账号。
  void switchTo(String accountId) {
    if (_activeId == accountId && _activeSubscription != null) return;
    _activeId = accountId;
    forAccount(accountId);
    _rebind();
  }

  /// The active account's state, or [Unauthenticated] when none is active.
  /// 激活账号的状态；没有激活账号时为 [Unauthenticated]。
  AuthState get current => active?.current ?? const Unauthenticated();

  /// The active account's session, or `null`.
  /// 激活账号的会话；无则为 `null`。
  AuthSession? get currentSession => active?.currentSession;

  @override
  String? get accessToken => active?.accessToken;

  /// State of the active account. Replays the latest value to new listeners,
  /// exactly like [AuthManager.state].
  /// 激活账号的状态流。与 [AuthManager.state] 一样，对新订阅者重放最近值。
  Stream<AuthState> get state {
    final sc = StreamController<AuthState>();
    sc.add(current);
    final sub = _controller.stream.listen(
      sc.add,
      onError: sc.addError,
      onDone: sc.close,
    );
    sc.onCancel = sub.cancel;
    return sc.stream;
  }

  /// Restores every account in [accountIds], then activates [activeId] (or the
  /// first restored account when omitted).
  /// 依次恢复 [accountIds] 中的所有账号，然后激活 [activeId]（省略时激活第一个）。
  Future<void> restoreAll(
    Iterable<String> accountIds, {
    String? activeId,
  }) async {
    for (final id in accountIds) {
      await forAccount(id).restore();
    }
    final target = activeId ?? (accountIds.isEmpty ? null : accountIds.first);
    if (target != null) switchTo(target);
  }

  /// Signs an account out and forgets it. When it was active, the group becomes
  /// inactive and emits [Unauthenticated].
  /// 登出并移除某个账号。若它正处于激活状态，分组会转为无激活并发 [Unauthenticated]。
  Future<void> remove(String accountId) async {
    final manager = _managers.remove(accountId);
    if (manager == null) return;

    await manager.logout();
    await manager.dispose();

    if (_activeId == accountId) {
      _activeId = null;
      _rebind();
      if (!_controller.isClosed) _controller.add(const Unauthenticated());
    }
  }

  /// Disposes every manager and closes the group's stream.
  /// 释放所有管理器并关闭分组的状态流。
  Future<void> disposeAll() async {
    await _activeSubscription?.cancel();
    _activeSubscription = null;

    for (final manager in _managers.values) {
      await manager.dispose();
    }
    _managers.clear();
    _activeId = null;

    await _controller.close();
  }

  void _rebind() {
    _activeSubscription?.cancel();
    _activeSubscription = active?.state.listen(
      _controller.add,
      onError: _controller.addError,
    );
  }
}
