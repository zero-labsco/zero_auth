import 'dart:async';

import 'auth_manager.dart';
import 'auth_session.dart';
import 'auth_state.dart';
import 'auth_strategy.dart';
import 'auth_token_source.dart';
import 'exceptions.dart';
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
  ///
  /// Every [AuthManager] tuning knob — `autoRefreshAhead`, `clockSkew`,
  /// `refreshFailurePolicy`, `onStateChanged`… — is applied to the managers this
  /// group creates, so a multi-account session behaves exactly like a standalone
  /// one. Pass [managerFactory] to build them yourself instead.
  /// 创建分组。两个工厂方法按账号惰性调用一次。
  ///
  /// 请为每个账号提供独立的 [TokenStore] 实例（例如按账号 id 命名的安全存储），
  /// 以保证持久化会话彼此隔离。
  ///
  /// 所有 [AuthManager] 的调参项 —— `autoRefreshAhead`、`clockSkew`、
  /// `refreshFailurePolicy`、`onStateChanged`…… —— 都会应用到分组创建的管理器上，
  /// 因此多账号会话的行为与单账号完全一致。也可传 [managerFactory] 自行构建。
  AuthManagerGroup({
    required AuthStrategy Function(String accountId) strategyFactory,
    required TokenStore Function(String accountId) storeFactory,
    this.managerFactory,
    this.autoRefreshAhead,
    this.autoRefreshRetryDelay,
    this.autoRefreshMaxRetries,
    this.autoRefreshMinInterval,
    this.refreshFailurePolicy,
    this.clock,
    this.clockSkew,
    this.preserveSessionDetails = true,
    this.onStateChanged,
    this.onObserverError,
  })  : _strategyFactory = strategyFactory,
        _storeFactory = storeFactory;

  /// Called once per account. Returning the same instance for every account is
  /// fine — and typical — since a strategy usually just talks to one backend.
  /// 每个账号调用一次。各账号返回同一个实例也没问题（而且常见），因为策略通常只是
  /// 与同一个后端通信。
  final AuthStrategy Function(String accountId) _strategyFactory;
  final TokenStore Function(String accountId) _storeFactory;

  /// Optional override for how each account's [AuthManager] is built. It receives
  /// the account id plus the strategy and store the factories produced, and wins
  /// over the individual knobs below.
  /// 可选的构建覆盖：自行创建每个账号的 [AuthManager]。它收到账号 id 以及工厂产出的
  /// strategy 与 store，并优先于下面的各项参数。
  final AuthManager Function(
    String accountId,
    AuthStrategy strategy,
    TokenStore store,
  )? managerFactory;

  /// Forwarded to every manager this group creates — see [AuthManager.new].
  /// 转发给分组创建的每个管理器 —— 参见 [AuthManager.new]。
  final Duration? autoRefreshAhead;
  final Duration? autoRefreshRetryDelay;
  final int? autoRefreshMaxRetries;
  final Duration? autoRefreshMinInterval;
  final RefreshFailurePolicy? refreshFailurePolicy;
  final DateTime Function()? clock;
  final Duration? clockSkew;
  final bool preserveSessionDetails;

  /// Invoked for every state emitted by **any** account's manager, tagged with
  /// the account it came from. Handy for logging or analytics across accounts.
  /// 任一账号的管理器发出状态时调用，并带上来源账号。便于跨账号做日志或埋点。
  final void Function(String accountId, AuthState state)? onStateChanged;

  /// Called when that observer throws, tagged with the account whose observer it
  /// was. Forwarded to every manager the group creates, so a failing sink is
  /// reported instead of failing silently. Silent when omitted.
  /// 当该观察者抛异常时调用，并带上观察者所属的账号。它会转发给分组创建的每个管理器，
  /// 因此坏掉的日志 / 埋点会被上报而不是静默失败；不传则保持静默。
  final void Function(String accountId, Object error, StackTrace stack)?
      onObserverError;

  final Map<String, AuthManager> _managers = {};
  final StreamController<AuthState> _controller =
      StreamController<AuthState>.broadcast();
  final StreamController<String?> _activeIdController =
      StreamController<String?>.broadcast();

  StreamSubscription<AuthState>? _activeSubscription;
  String? _activeId;
  bool _closed = false;

  /// Rejects usage after [disposeAll], mirroring the single-manager
  /// `manager_disposed` contract.
  /// 在 [disposeAll] 之后拒绝使用，与单管理器的 `manager_disposed` 约定一致。
  void _checkUsable() {
    if (_closed) {
      throw AuthException(
        'AuthManagerGroup has been disposed',
        code: 'group_disposed',
      );
    }
  }

  /// Ids currently owned by the group.
  ///
  /// Like every other read here, this rejects use after [disposeAll] with
  /// `AuthException(code: 'group_disposed')`, so a released group never answers
  /// with stale data.
  /// 分组当前持有的账号 id。
  ///
  /// 与这里的其它读取一样，[disposeAll] 之后会以
  /// `AuthException(code: 'group_disposed')` 拒绝使用，已释放的分组不会再用过期数据作答。
  Iterable<String> get accountIds {
    _checkUsable();
    return _managers.keys;
  }

  /// The active account id, or `null` when none is active.
  /// 当前激活的账号 id；没有激活账号时为 `null`。
  String? get activeId {
    _checkUsable();
    return _activeId;
  }

  /// The active account's manager, or `null` when none is active.
  /// 激活账号的管理器；没有激活账号时为 `null`。
  AuthManager? get active {
    _checkUsable();
    return _activeId == null ? null : _managers[_activeId];
  }

  /// Returns the manager for [accountId], creating it on first use.
  /// 返回 [accountId] 对应的管理器，首次使用时创建。
  AuthManager forAccount(String accountId) {
    _checkUsable();
    return _managers.putIfAbsent(accountId, () => _createManager(accountId));
  }

  AuthManager _createManager(String accountId) {
    final strategy = _strategyFactory(accountId);
    final store = _storeFactory(accountId);
    final factory = managerFactory;
    if (factory != null) return factory(accountId, strategy, store);

    final observer = onStateChanged;
    final report = onObserverError;
    return AuthManager(
      strategy: strategy,
      tokenStore: store,
      autoRefreshAhead: autoRefreshAhead,
      autoRefreshRetryDelay: autoRefreshRetryDelay,
      autoRefreshMaxRetries: autoRefreshMaxRetries,
      autoRefreshMinInterval: autoRefreshMinInterval,
      refreshFailurePolicy: refreshFailurePolicy,
      clock: clock,
      clockSkew: clockSkew,
      preserveSessionDetails: preserveSessionDetails,
      onStateChanged:
          observer == null ? null : (state) => observer(accountId, state),
      onObserverError: report == null
          ? null
          : (error, stack) => report(accountId, error, stack),
    );
  }

  /// Explicitly registers an account and returns its manager.
  ///
  /// Identical to [forAccount]; it exists so call sites that *mean* "add" read
  /// that way.
  /// 显式注册一个账号并返回其管理器。
  ///
  /// 与 [forAccount] 等价；存在它是为了让「新增」这种意图在调用点读起来更明确。
  AuthManager addAccount(String accountId) => forAccount(accountId);

  /// Signs every account out and forgets them all.
  /// 登出所有账号并全部遗忘。
  Future<void> logoutAll() async {
    _checkUsable();
    Object? firstError;
    for (final id in _managers.keys.toList()) {
      try {
        await remove(id);
      } catch (e) {
        // Keep going: one failing account must not leave the others signed in.
        // 继续处理：某个账号失败不应让其它账号保持登录。
        firstError ??= e;
      }
    }
    if (firstError != null) throw firstError;
  }

  /// Makes [accountId] the active account.
  ///
  /// The group's [state] stream switches to that manager and replays its
  /// current state, and [activeIdChanges] emits the new id; nothing is signed in
  /// or out by this call.
  /// 把 [accountId] 设为激活账号。
  ///
  /// 分组的 [state] 流会切到该管理器并重放其当前状态，[activeIdChanges] 也会发出新的
  /// id；此调用不会登录或登出任何账号。
  void switchTo(String accountId) {
    _checkUsable();
    if (_activeId == accountId && _activeSubscription != null) return;
    _activeId = accountId;
    forAccount(accountId);
    _rebind();
    _emitActiveId();
  }

  void _emitActiveId() {
    if (!_activeIdController.isClosed) _activeIdController.add(_activeId);
  }

  /// The active account's state, or [Unauthenticated] when none is active.
  /// 激活账号的状态；没有激活账号时为 [Unauthenticated]。
  AuthState get current {
    _checkUsable();
    return active?.current ?? const Unauthenticated();
  }

  /// The active account's session, or `null`.
  /// 激活账号的会话；无则为 `null`。
  AuthSession? get currentSession {
    _checkUsable();
    return active?.currentSession;
  }

  @override
  String? get accessToken {
    _checkUsable();
    return active?.accessToken;
  }

  /// The active account's guaranteed-valid token, or `null` when none is active
  /// (or renewal failed and the session was dropped).
  /// 激活账号「保证有效」的令牌；无激活账号（或续期失败导致会话被丢弃）时为 `null`。
  @override
  Future<String?> validAccessToken({Duration? leeway}) async {
    _checkUsable();
    final manager = active;
    if (manager == null) return null;
    return manager.validAccessToken(leeway: leeway);
  }

  /// State of the active account. Replays the latest value to new listeners,
  /// exactly like [AuthManager.state].
  /// 激活账号的状态流。与 [AuthManager.state] 一样，对新订阅者重放最近值。
  Stream<AuthState> get state {
    _checkUsable();
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

  /// Emits every change of [activeId], including `null` when the group becomes
  /// inactive. Complements [state], which only mirrors the active account.
  /// 每次 [activeId] 变化时发出新值（分组转为无激活时发 `null`）。它补充 [state]，
  /// 后者只反映激活账号的状态。
  Stream<String?> get activeIdChanges {
    _checkUsable();
    return _activeIdController.stream;
  }

  /// Restores every account in [accountIds], then activates [activeId] (or the
  /// first restored account when omitted).
  ///
  /// One account failing to restore does not abandon the rest: they are all
  /// attempted and the first error is reported at the end.
  ///
  /// [parallel] (default `false`) restores them concurrently instead of one
  /// after another. Startup cost becomes the slowest store rather than the sum
  /// of them, which matters once a slow store (Keychain, encrypted storage) is
  /// involved — the trade-off is that several `refresh` calls can then be in
  /// flight at once. Error reporting is unchanged: the first failure, in
  /// [accountIds] order, is thrown at the end.
  /// 依次恢复 [accountIds] 中的所有账号，然后激活 [activeId]（省略时激活第一个）。
  ///
  /// 某个账号恢复失败不会连累其余账号：所有账号都会被尝试，最后统一上报第一个错误。
  ///
  /// [parallel]（默认 `false`）改为并发恢复而非逐个恢复。启动耗时从「各存储耗时之和」
  /// 变为「最慢的那个」，当存储较慢（Keychain、加密存储）时差别明显 —— 代价是可能同时
  /// 有多个 `refresh` 在飞行中。错误上报不变：最后抛出 [accountIds] 顺序上的第一个失败。
  Future<void> restoreAll(
    Iterable<String> accountIds, {
    String? activeId,
    bool dropOthers = false,
    bool parallel = false,
  }) async {
    _checkUsable();

    if (dropOthers) {
      final keep = accountIds.toSet();
      for (final id in _managers.keys.toList()) {
        if (keep.contains(id)) continue;
        final stale = _managers.remove(id);
        await stale?.dispose();
        if (_activeId == id) {
          _activeId = null;
          _emitActiveId();
        }
      }
    }

    Object? firstError;
    Future<Object?> restoreOne(String id) async {
      try {
        await forAccount(id).restore();
        return null;
      } catch (e) {
        // Keep going: one unreadable store must not leave the others unrestored.
        // 继续处理：某个存储读不出来不应让其余账号无法恢复。
        return e;
      }
    }

    if (parallel) {
      // `Future.wait` preserves input order, so `firstError` is still the
      // earliest failure in `accountIds`.
      // `Future.wait` 保持输入顺序，因此 `firstError` 仍是 `accountIds` 中最靠前的失败。
      for (final error in await Future.wait(accountIds.map(restoreOne))) {
        firstError ??= error;
      }
    } else {
      for (final id in accountIds) {
        // Not `??=`: that would short-circuit and skip the remaining accounts.
        // 不能用 `??=`：它会短路，导致其余账号被跳过。
        final error = await restoreOne(id);
        firstError ??= error;
      }
    }
    final target = activeId ?? (accountIds.isEmpty ? null : accountIds.first);
    if (target != null) switchTo(target);
    if (firstError != null) throw firstError;
  }

  /// Signs an account out and forgets it. When it was active, the group becomes
  /// inactive and emits [Unauthenticated].
  /// 登出并移除某个账号。若它正处于激活状态，分组会转为无激活并发 [Unauthenticated]。
  Future<void> remove(String accountId) async {
    _checkUsable();
    final manager = _managers.remove(accountId);
    if (manager == null) return;

    // `logout()` may throw (for instance when the store cannot be cleared). Even
    // then the manager must not leak, so disposal happens in a `finally`.
    // `logout()` 可能抛异常（例如存储无法清空）。即便如此管理器也不该泄漏，
    // 因此释放放在 `finally` 中。
    try {
      await manager.logout();
    } finally {
      await manager.dispose();
    }

    if (_activeId == accountId) {
      _activeId = null;
      _rebind();
      if (!_controller.isClosed) _controller.add(const Unauthenticated());
      _emitActiveId();
    }
  }

  /// Disposes every manager and closes the group's streams.
  /// 释放所有管理器并关闭分组的各个流。
  Future<void> disposeAll() async {
    if (_closed) return;
    _closed = true;
    await _activeSubscription?.cancel();
    _activeSubscription = null;

    for (final manager in _managers.values) {
      await manager.dispose();
    }
    _managers.clear();
    _activeId = null;

    await _controller.close();
    await _activeIdController.close();
  }

  void _rebind() {
    unawaited(_activeSubscription?.cancel());
    _activeSubscription = active?.state.listen(
      _controller.add,
      onError: _controller.addError,
      onDone: _onActiveClosed,
    );
  }

  /// The active manager's stream closed — it was disposed outside the group.
  /// Forget it instead of holding on to a released manager, and tell listeners
  /// the group is no longer active.
  /// 激活账号的流已关闭 —— 它在分组之外被释放了。此时应将其遗忘，而不是继续持有已
  /// 释放的管理器，同时通知监听者分组已无激活账号。
  void _onActiveClosed() {
    final id = _activeId;
    if (id == null) return;
    _managers.remove(id);
    _activeId = null;
    _activeSubscription = null;
    if (!_controller.isClosed) _controller.add(const Unauthenticated());
    _emitActiveId();
  }
}
