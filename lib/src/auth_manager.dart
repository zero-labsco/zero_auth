import 'dart:async';

import 'auth_session.dart';
import 'auth_state.dart';
import 'auth_strategy.dart';
import 'auth_token_source.dart';
import 'error/app_exception.dart';
import 'exceptions.dart';
import 'token_store.dart';

/// Decides whether a failed [AuthManager.refresh] must sign the user out.
/// 决定一次失败的 [AuthManager.refresh] 是否必须让用户登出。
///
/// Returning `true` clears the persisted session and lands the manager on
/// [Unauthenticated]; returning `false` keeps the session so a later attempt can
/// retry (the failure is still reported through the state stream).
/// 返回 `true` 会清空持久化会话并使管理器落到 [Unauthenticated]；返回 `false` 保留会话
/// 以便稍后重试（该失败仍会通过状态流上报）。
typedef RefreshFailurePolicy = bool Function(AppException error);

/// Default policy: failures that can never succeed again (expired or revoked
/// grants, rejected credentials) sign the user out, while transient failures
/// (network hiccups, 5xx) keep the session so it can be retried.
/// 默认策略：注定无法重试成功的失败（授权过期 / 被吊销、凭据被拒）会让用户登出，
/// 而瞬时失败（网络抖动、5xx）保留会话以供重试。
bool defaultRefreshFailurePolicy(AppException error) =>
    error is SessionExpiredException || error is InvalidCredentialsException;

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

  /// Epoch the in-flight refresh was started in. A refresh started before the
  /// session was replaced (by a login, for instance) must not be joined, or the
  /// caller would receive a session that is already stale.
  /// 进行中刷新启动时所处的 epoch。若会话在其启动后被替换（例如重新登录），则不能再
  /// 加入该次刷新，否则调用方会拿到已经过期的会话。
  int _refreshCompleterEpoch = 0;

  Timer? _autoRefreshTimer;

  /// When the last proactive renewal started, used to throttle a run of
  /// already-due renewals.
  /// 上一次主动续期的开始时刻，用于节流一连串「已到期」的续期。
  DateTime? _lastProactiveRefreshAt;

  bool _disposed = false;

  /// Guards concurrent [restore] calls: they share one attempt instead of
  /// activating two sessions.
  /// 守卫并发的 [restore] 调用：它们共享同一次尝试，而不会激活两个会话。
  Future<void>? _restoreInFlight;

  /// Bumped on [logout] / [dispose]. Work started before a bump is dropped, so a
  /// late refresh can never resurrect a session the user already left.
  /// 在 [logout] / [dispose] 时递增。自增之前启动的工作会被丢弃，因此迟到的刷新永远
  /// 无法「复活」用户已退出的会话。
  int _epoch = 0;

  /// Creates a manager. Defaults to [InMemoryTokenStore].
  ///
  /// Pass [autoRefreshAhead] to enable proactive refresh: when a session carries
  /// both an [AuthSession.expiresAt] and a refresh token, the manager schedules a
  /// single [refresh] call that many minutes before expiry, so callers rarely hit
  /// an expired access token. Defaults to `null` (disabled).
  ///
  /// [refreshFailurePolicy] decides whether a failed refresh signs the user out;
  /// it defaults to [defaultRefreshFailurePolicy]. [clock] overrides the time
  /// source used for expiry maths and proactive scheduling (tests, clock skew),
  /// while [clockSkew] is how much *earlier* a token counts as expired, so a
  /// device clock that runs ahead cannot hand out a token that dies in flight.
  /// 创建管理器，默认使用 [InMemoryTokenStore]。
  ///
  /// 传入 [autoRefreshAhead] 可开启「临近过期自动刷新」：当会话同时带有
  /// [AuthSession.expiresAt] 与刷新令牌时，管理器会在过期前该时长调度一次
  /// [refresh]，从而让调用方几乎不会撞上过期的访问令牌。默认 `null`（关闭）。
  ///
  /// [refreshFailurePolicy] 决定刷新失败是否让用户登出，默认为
  /// [defaultRefreshFailurePolicy]；[clock] 可覆盖过期计算与主动刷新调度所用的时间源
  /// （便于测试与应对时钟偏移），[clockSkew] 则表示提前多久把令牌视为过期，以免设备
  /// 时钟偏快时发出一个途中就会失效的令牌。
  /// [autoRefreshAhead] enables proactive renewal; when such a renewal fails,
  /// [autoRefreshRetryDelay] re-arms it instead of silently stopping.
  ///
  /// [onStateChanged] is an optional sink invoked for every emitted state — handy
  /// for logging or analytics without subscribing to [state].
  /// [autoRefreshAhead] 开启主动续期；若该次续期失败，则按 [autoRefreshRetryDelay]
  /// 重新排程，而不是默默停止。
  ///
  /// [onStateChanged] 是可选回调，每次发出状态时被调用，便于在不订阅 [state] 的情况下
  /// 做日志或埋点。
  ///
  /// [preserveSessionDetails] (default `true`) carries the identity fields — user
  /// id, display name, claims — over to a refreshed session when the backend only
  /// returns tokens. [autoRefreshMinInterval] floors the delay of a proactive
  /// renewal that is already due, so a backend handing out very short-lived
  /// tokens cannot turn renewal into a tight loop.
  /// [preserveSessionDetails]（默认 `true`）在后端刷新只返回令牌时，把身份字段
  /// （用户 id、显示名、claims）带到新会话上；[autoRefreshMinInterval] 为「已到期」
  /// 的主动续期设置最小等待，避免后端发放极短寿命令牌时把续期变成紧密循环。
  AuthManager({
    required this.strategy,
    TokenStore? tokenStore,
    Duration? autoRefreshAhead,
    Duration? autoRefreshRetryDelay,
    int? autoRefreshMaxRetries,
    Duration? autoRefreshMinInterval,
    RefreshFailurePolicy? refreshFailurePolicy,
    DateTime Function()? clock,
    Duration? clockSkew,
    this.preserveSessionDetails = true,
    this.onStateChanged,
  }) : tokenStore = tokenStore ?? InMemoryTokenStore(),
       _autoRefreshAhead = autoRefreshAhead,
       _autoRefreshRetryDelay =
           autoRefreshRetryDelay ?? const Duration(seconds: 30),
       _autoRefreshMaxRetries = autoRefreshMaxRetries ?? 3,
       _autoRefreshMinInterval =
           autoRefreshMinInterval ?? const Duration(seconds: 5),
       refreshFailurePolicy =
           refreshFailurePolicy ?? defaultRefreshFailurePolicy,
       clock = clock ?? _systemClock,
       clockSkew = clockSkew ?? const Duration(seconds: 30);

  final Duration? _autoRefreshAhead;

  /// Delay before re-arming a proactive refresh that failed. Each further
  /// attempt waits one more multiple of this, giving a linear backoff.
  /// 主动续期失败后重新排程的等待时长；每多失败一次就多等一个该时长（线性退避）。
  final Duration _autoRefreshRetryDelay;

  /// How many failed proactive renewals to retry before giving up.
  /// 主动续期失败多少次后放弃重试。
  final int _autoRefreshMaxRetries;

  /// Floor for a proactive renewal that is already due, so a backend handing out
  /// very short-lived tokens cannot turn renewal into a tight loop.
  /// 「已到期」主动续期的最小等待，避免后端发放极短寿命令牌时把续期变成紧密循环。
  final Duration _autoRefreshMinInterval;

  /// How much earlier a token counts as expired. Absorbs a device clock that runs
  /// ahead of the server's, and the network latency of the request the token is
  /// about to be attached to. Defaults to 30 seconds.
  /// 提前多久把令牌视为过期。用于吸收设备时钟快于服务端的情况，以及令牌即将附着的
  /// 那次请求自身的网络延迟。默认 30 秒。
  final Duration clockSkew;

  /// Whether identity fields survive a refresh that only returns tokens.
  /// Defaults to `true`.
  /// 身份字段是否在「只返回令牌」的刷新中保留。默认 `true`。
  final bool preserveSessionDetails;

  /// Consecutive proactive renewal failures; reset once one succeeds.
  /// 连续主动续期失败次数；成功后归零。
  int _proactiveFailures = 0;

  /// Optional observer of every state change.
  /// 可选的状态变化观察者。
  final void Function(AuthState state)? onStateChanged;

  /// Guards against overlapping login / register / loginWith calls.
  /// 防止 login / register / loginWith 重叠调用。
  bool _authFlowInFlight = false;

  /// Decides what to do when a refresh fails. Defaults to
  /// [defaultRefreshFailurePolicy].
  /// 刷新失败的处理策略，默认为 [defaultRefreshFailurePolicy]。
  final RefreshFailurePolicy refreshFailurePolicy;

  /// Time source for expiry maths and proactive scheduling. Defaults to the
  /// system clock.
  /// 过期计算与主动刷新调度所用的时间源，默认为系统时钟。
  final DateTime Function() clock;

  static DateTime _systemClock() => DateTime.now();

  /// `now` shifted forward by [clockSkew] — the instant a token must still be
  /// valid at to be handed out.
  /// 把 `now` 前移 [clockSkew] 后的时刻；令牌要能发出，就必须在该时刻仍然有效。
  DateTime _expiryNow() => clock().add(clockSkew);

  /// Whether [session] must be considered expired, tolerating [clockSkew].
  /// [session] 是否应被视为已过期（计入 [clockSkew]）。
  bool _isExpired(AuthSession session) => session.isExpiredAt(_expiryNow());

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

  /// The active session, or `null` when not authenticated. Available in both
  /// [Authenticated] and [Refreshing] — a session stays usable while it renews —
  /// but not in [LoggingOut].
  /// 当前活动会话；未认证时为 `null`。在 [Authenticated] 与 [Refreshing] 下均可用
  /// （续期中会话依然有效），但 [LoggingOut] 下为空。
  AuthSession? get currentSession => switch (_state) {
    Authenticated(:final session) => session,
    Refreshing(:final session) => session,
    _ => null,
  };

  @override
  String? get accessToken => currentSession?.accessToken;

  /// Restore a persisted session at startup.
  ///
  /// When [refreshIfExpired] is `true` (default) and the persisted session is
  /// already expired, a refresh is attempted before falling back to
  /// [Unauthenticated]; pass `false` to restore the session as-is.
  ///
  /// A renewal that fails *transiently* (network hiccup, 5xx) keeps the persisted
  /// session: the user stays signed in and the next [validAccessToken] call
  /// retries. Only a failure that [refreshFailurePolicy] calls terminal clears
  /// the store.
  ///
  /// Concurrent callers share a single attempt instead of racing to activate two
  /// sessions; the arguments of the first call win.
  /// 启动时恢复持久化会话。
  ///
  /// 当 [refreshIfExpired] 为 `true`（默认）且持久化会话已过期时，会先尝试刷新，失败
  /// 才降级为 [Unauthenticated]；传 `false` 则原样恢复会话。
  ///
  /// **瞬时**失败（网络抖动、5xx）会保留持久化会话：用户仍处于登录态，下次
  /// [validAccessToken] 会重试。只有被 [refreshFailurePolicy] 判定为终局的失败才会
  /// 清空存储。
  ///
  /// 并发调用方共享同一次尝试，不会争抢激活两个会话；以首次调用的参数为准。
  Future<void> restore({bool refreshIfExpired = true}) async {
    _checkUsable();
    final inFlight = _restoreInFlight;
    if (inFlight != null) return inFlight;
    final attempt = _restore(
      refreshIfExpired,
    ).whenComplete(() => _restoreInFlight = null);
    _restoreInFlight = attempt;
    return attempt;
  }

  Future<void> _restore(bool refreshIfExpired) async {
    final epoch = _epoch;

    final AuthSession? session;
    try {
      session = await tokenStore.load();
    } catch (e) {
      // A store that cannot be read is treated as "no session": the user is
      // signed out and the cause is surfaced to the caller.
      // 无法读取的存储按「无会话」处理：用户被登出，原因抛给调用方。
      if (_isCurrent(epoch)) _emit(const Unauthenticated());
      throw UnexpectedAuthException(
        message: 'Failed to load the persisted session',
        cause: e,
      );
    }

    // A logout (or dispose) may have happened while the store was loading.
    // 存储读取期间可能发生了登出（或释放）。
    if (!_isCurrent(epoch)) return;

    if (session == null) {
      _emit(const Unauthenticated());
      return;
    }

    final expired = _isExpired(session);
    // Only reconsider an expired session when the caller opted in; otherwise the
    // session is restored verbatim, exactly as persisted.
    // 仅在调用方开启时才对过期会话做再处理；否则原样恢复会话，与持久化内容一致。
    if (expired && refreshIfExpired) {
      if (session.refreshToken == null) {
        await _dropSession(
          SessionExpiredException(
            message: 'Persisted session expired and has no refresh token',
          ),
        );
        return;
      }

      final attempt = await _tryRefresh(session);
      if (!_isCurrent(epoch)) return;

      final failure = attempt.failure;
      if (failure != null) {
        // Transient: keep the persisted session so a later call can retry. Only a
        // terminal failure (per the policy) is allowed to destroy it.
        // 瞬时失败：保留持久化会话以便稍后重试；只有策略判定的终局失败才能销毁它。
        if (!refreshFailurePolicy(failure)) {
          _emit(AuthError(failure));
          // Activated without an immediate renewal — it has just failed — but
          // proactive renewal, when configured, is re-armed with its backoff so
          // the session does not stay stale forever.
          // 激活时不立即续期（刚刚才失败过），但若配置了主动续期，则按其退避策略
          // 重新排程，避免会话一直停留在过期状态。
          _activate(session, scheduleProactive: false);
          if (_autoRefreshAhead != null) _scheduleProactiveRetry();
          return;
        }
        await _dropSession(failure);
        return;
      }

      final renewed = attempt.session;
      if (renewed == null || _isExpired(renewed)) {
        await _dropSession(
          SessionExpiredException(
            message: 'Persisted session expired and could not be renewed',
            cause: failure,
          ),
        );
        return;
      }
      return;
    }

    // Restoring verbatim must honour "do not renew": an expired session is
    // activated as-is, without the proactive scheduler refreshing it behind the
    // caller's back the moment it is activated.
    // 原样恢复必须尊重「不要续期」的意图：已过期会话按原样激活，
    // 不会在激活的瞬间被主动调度偷偷刷新。
    _activate(session, scheduleProactive: !expired);
  }

  /// Clears the persisted session and lands on [Unauthenticated], reporting why
  /// so the UI can tell "never signed in" apart from "session expired".
  /// 清空持久化会话并落到 [Unauthenticated]，同时上报原因，以便界面区分
  /// 「从未登录」与「会话过期」。
  Future<void> _dropSession(AppException failure) async {
    Object? clearError;
    try {
      await tokenStore.clear();
    } catch (e) {
      // A store that cannot be cleared must not block the sign-out itself; the
      // cause is reported after the state has settled.
      // 无法清空的存储不应阻断登出本身；状态落定后再上报原因。
      clearError = e;
    }
    _emit(AuthError(failure));
    _emit(const Unauthenticated());
    if (clearError != null) {
      throw UnexpectedAuthException(
        message:
            'The session was dropped, but the stored session could not be cleared',
        cause: clearError,
      );
    }
  }

  /// Log in: emits [Authenticating] → [Authenticated] (or [AuthError] on failure).
  /// 登录：先发 [Authenticating]，成功发 [Authenticated]，失败发 [AuthError]。
  Future<Authenticated> login(Credentials credentials) async {
    _beginAuthFlow();
    // A refresh started before this flow must not overwrite the session it is
    // about to install with a token from the previous one.
    // 本次流程之前启动的刷新，不能用旧会话的令牌覆盖即将安装的会话。
    _invalidateInFlight();
    _emit(const Authenticating());
    final epoch = _epoch;
    try {
      final session = await strategy.login(credentials);
      _ensureCurrent(epoch);
      await tokenStore.save(session);
      final next = Authenticated(session);
      _activate(session);
      return next;
    } catch (e) {
      final failure = mapAuthFailure(e);
      if (_isCurrent(epoch)) _emit(AuthError(failure));
      throw failure;
    } finally {
      _endAuthFlow();
    }
  }

  /// Register a new account and return its first session.
  /// 注册新账户并返回首个会话。
  Future<Authenticated> register(RegistrationInput input) async {
    _beginAuthFlow();
    // A refresh started before this flow must not overwrite the session it is
    // about to install with a token from the previous one.
    // 本次流程之前启动的刷新，不能用旧会话的令牌覆盖即将安装的会话。
    _invalidateInFlight();
    _emit(const Authenticating());
    final epoch = _epoch;
    try {
      final session = await strategy.register(input);
      _ensureCurrent(epoch);
      await tokenStore.save(session);
      final next = Authenticated(session);
      _activate(session);
      return next;
    } catch (e) {
      final failure = mapAuthFailure(e);
      if (_isCurrent(epoch)) _emit(AuthError(failure));
      throw failure;
    } finally {
      _endAuthFlow();
    }
  }

  /// Adopt a session produced by any flow you drive yourself — third-party
  /// OAuth, magic links, passkeys, biometric unlock — and emit it as the active
  /// session.
  ///
  /// This is the escape hatch for logins that do not fit [login] / [register]:
  /// the manager still owns persistence, the state machine and scheduling, while
  /// you keep control over how the tokens are obtained.
  /// 接纳由你自行驱动的任意流程所产生的会话——第三方 OAuth、魔法链接、Passkey、
  /// 生物识别解锁——并将其作为活动会话发出。
  ///
  /// 这是 [login] / [register] 之外的逃生口：令牌如何获取由你掌控，而持久化、状态机
  /// 与调度仍由管理器负责。
  Future<Authenticated> loginWith(
    Future<AuthSession> Function(AuthStrategy strategy) flow,
  ) async {
    _beginAuthFlow();
    // A refresh started before this flow must not overwrite the session it is
    // about to install with a token from the previous one.
    // 本次流程之前启动的刷新，不能用旧会话的令牌覆盖即将安装的会话。
    _invalidateInFlight();
    _emit(const Authenticating());
    final epoch = _epoch;
    try {
      final session = await flow(strategy);
      _ensureCurrent(epoch);
      await tokenStore.save(session);
      final next = Authenticated(session);
      _activate(session);
      return next;
    } catch (e) {
      final failure = mapAuthFailure(e);
      if (_isCurrent(epoch)) _emit(AuthError(failure));
      throw failure;
    } finally {
      _endAuthFlow();
    }
  }

  /// Replaces the active session without a re-login — for example after a
  /// profile update, or when refreshed claims must reach the UI.
  ///
  /// Throws [NoActiveSessionException] when nothing is signed in.
  /// 在不重新登录的情况下替换活动会话 —— 例如资料更新后，或刷新后的 claims 需要
  /// 反映到界面时。
  ///
  /// 未登录时抛出 [NoActiveSessionException]。
  Future<Authenticated> updateSession(
    FutureOr<AuthSession> Function(AuthSession current) update,
  ) async {
    _checkUsable();
    final current = currentSession;
    if (current == null) {
      throw NoActiveSessionException(
        message: 'Cannot update the session when none is active',
      );
    }

    // `update` may be async (a round trip to fetch fresh profile data), so the
    // session is re-checked on both sides of it.
    // `update` 可以是异步的（例如先请求最新资料），因此前后都要重新校验。
    final startEpoch = _epoch;
    _ensureCurrent(startEpoch);
    final updated = await update(current);
    _ensureCurrent(startEpoch);

    // A refresh started before the update would overwrite it with a token from
    // the previous session, so it is invalidated here.
    // 更新前启动的刷新会用旧会话的令牌覆盖本次结果，因此在此令其失效。
    _invalidateInFlight();
    final epoch = _epoch;

    try {
      await tokenStore.save(updated);
    } catch (e) {
      // Persistence is part of the contract: a store failure must leave through
      // the same AppException doorway as everything else.
      // 持久化属于契约的一部分：存储失败必须和其它失败一样，从 AppException 这道门出去。
      throw UnexpectedAuthException(
        message: 'Failed to persist the updated session',
        cause: e,
      );
    }

    // The session could have been invalidated while saving; do not leave a
    // session behind after a logout.
    // 保存期间也可能失效；登出之后不应残留会话。
    if (!_isCurrent(epoch)) {
      try {
        await tokenStore.clear();
      } catch (_) {
        // Nothing more we can do; the caller still gets the exception below.
        // 已无能为力，调用方仍会收到下面的异常。
      }
      throw NoActiveSessionException(
        message: 'Operation aborted: session invalidated meanwhile',
      );
    }

    final next = Authenticated(updated);
    _activate(updated);
    return next;
  }

  /// Whether the strategy implements [T], letting optional capabilities be used
  /// without widening the [AuthStrategy] contract.
  ///
  /// 策略是否实现了 [T]，从而无需扩大 [AuthStrategy] 契约即可使用可选能力。
  ///
  /// ```dart
  /// if (auth.supports<SupportsPasswordReset>()) {
  ///   await (auth.strategy as SupportsPasswordReset).requestPasswordReset(id);
  /// }
  /// ```
  bool supports<T>() => strategy is T;

  /// Log out: emits [LoggingOut], notifies the backend, clears storage, then
  /// emits [Unauthenticated].
  /// 登出：发 [LoggingOut]、通知后端、清空存储，最后发 [Unauthenticated]。
  Future<void> logout() async {
    _checkUsable();
    // Invalidated first: a renewal that lands while the backend logout is in
    // flight must not emit `Authenticated` after the sign-out has begun.
    // 先令旧工作失效：后端登出期间落地的续期，不应在登出开始后又发出 `Authenticated`。
    _invalidateInFlight();
    _cancelProactiveRefresh();
    final session = _activeSession;
    if (session != null) {
      _emit(LoggingOut(session));
      try {
        await strategy.logout(
          SessionHandle(
            userId: session.userId ?? '',
            refreshToken: session.refreshToken,
          ),
        );
      } catch (_) {
        // Best-effort: a backend logout failure must not block local logout.
        // 尽力而为：后端登出失败不应阻断本地登出。
      }
    }
    // Local logout must always complete, even when the store itself fails.
    // 即使存储本身出错，本地登出也必须完成。
    Object? clearError;
    try {
      await tokenStore.clear();
    } catch (e) {
      clearError = e;
    }
    _emit(const Unauthenticated());

    if (clearError != null) {
      throw UnexpectedAuthException(
        message:
            'Signed out locally, but the stored session could not be cleared',
        cause: clearError,
      );
    }
  }

  /// Refresh the session. Concurrent callers share a single backend call
  /// (single-flight). Emits [Refreshing] while in flight.
  /// 刷新会话。并发调用方共享同一次后端调用（单飞），期间发出 [Refreshing]。
  Future<AuthSession> refresh() {
    _checkUsable();
    final session = _activeSession;
    if (session == null) {
      return Future<AuthSession>.error(NoActiveSessionException());
    }
    if (session.refreshToken == null) {
      return Future<AuthSession>.error(RefreshTokenMissingException());
    }
    return _startRefresh(session);
  }

  /// An access token that is guaranteed not to be expired, refreshing first when
  /// needed. Returns `null` when unauthenticated, or when the refresh failed and
  /// the session was dropped. Ideal for HTTP interceptors.
  ///
  /// [leeway] is how long the token must stay valid for (defaults to
  /// [clockSkew]), so a token that would die while the request is in flight is
  /// renewed first.
  /// 保证未过期的访问令牌，必要时先刷新。未认证、或刷新失败导致会话被丢弃时返回
  /// `null`。非常适合用在 HTTP 拦截器里。
  ///
  /// [leeway] 表示令牌必须还能维持有效的时长（默认取 [clockSkew]），因此会在请求
  /// 途中失效的令牌会被提前续期。
  @override
  Future<String?> validAccessToken({Duration? leeway}) async {
    _checkUsable();
    final session = currentSession;
    if (session == null) return null;
    if (!session.isExpiredAt(clock().add(leeway ?? clockSkew))) {
      return session.accessToken;
    }

    // Expired (or expiring within the leeway). Without a refresh token there is
    // no way to make it valid again, so an expired token must never be handed to
    // the network layer.
    // 已过期（或在容差内即将过期）。没有刷新令牌就无法恢复有效性，因此绝不能把过期
    // 令牌交给网络层。
    if (session.refreshToken == null) return null;

    try {
      return (await refresh()).accessToken;
    } on AuthException {
      return null;
    }
  }

  /// Release internal resources. Call when the manager is no longer used.
  /// 释放内部资源。不再使用时调用。
  Future<void> dispose() {
    _disposed = true;
    _invalidateInFlight();
    _cancelProactiveRefresh();
    _restoreInFlight?.ignore();
    _restoreInFlight = null;
    return _controller.close();
  }

  /// The session driving any in-flight or established auth, including the one
  /// being discarded during [LoggingOut].
  /// 驱动进行中操作或已建立认证的会话，包含在 [LoggingOut] 期间正被丢弃的那个。
  AuthSession? get _activeSession => switch (_state) {
    Authenticated(:final session) => session,
    Refreshing(:final session) => session,
    LoggingOut(:final session) => session,
    _ => null,
  };

  bool _isCurrent(int epoch) => !_disposed && epoch == _epoch;

  /// Invalidates every piece of work started before now — an in-flight refresh
  /// above all — so a late result can never overwrite the session a newer
  /// operation installed.
  /// 让此刻之前启动的所有工作失效（尤其是进行中的刷新），迟到的结果永远不会覆盖更新
  /// 的操作所安装的会话。
  void _invalidateInFlight() => _epoch++;

  void _ensureCurrent(int epoch) {
    if (!_isCurrent(epoch)) {
      throw NoActiveSessionException(
        message: 'Operation aborted: session invalidated meanwhile',
      );
    }
  }

  /// Rejects operations once the manager has been disposed, instead of silently
  /// doing nothing.
  /// 管理器释放后拒绝操作，而不是静默无作为。
  void _checkUsable() {
    if (_disposed) {
      throw AuthException(
        'AuthManager has been disposed',
        code: 'manager_disposed',
      );
    }
  }

  /// Serialises login / register / loginWith so overlapping calls cannot race to
  /// overwrite the session.
  /// 串行化 login / register / loginWith，避免重叠调用争抢覆盖会话。
  void _beginAuthFlow() {
    _checkUsable();
    if (_authFlowInFlight) {
      throw AuthException(
        'An authentication flow is already in progress',
        code: 'auth_flow_in_progress',
      );
    }
    _authFlowInFlight = true;
  }

  void _endAuthFlow() => _authFlowInFlight = false;

  /// Attempts to renew [session].
  ///
  /// Returns the resulting session (the renewed one, or the previous one when the
  /// failure policy kept it) plus the failure when the attempt did not succeed.
  /// 尝试续期 [session]。
  ///
  /// 返回结果会话（续期后的；失败策略选择保留时则为上一个会话），并在未成功时一并返回
  /// 失败原因。
  Future<({AuthSession? session, AuthException? failure})> _tryRefresh(
    AuthSession session,
  ) async {
    try {
      return (session: await _startRefresh(session), failure: null);
    } on AuthException catch (e) {
      return (session: currentSession, failure: e);
    }
  }

  Future<AuthSession> _startRefresh(AuthSession session) {
    final inFlight = _refreshCompleter;
    // Only join a refresh started within the current epoch: one started before
    // the session was replaced (by a login, for instance) would hand back a
    // session that is already stale — or worse, one minted from a refresh token
    // that a rotation has since retired.
    // 只加入在当前 epoch 内启动的刷新：会话被替换（例如重新登录）之前启动的那次会
    // 返回已经过期的会话 —— 更糟的情况是返回由已被轮换退役的刷新令牌换来的会话。
    if (inFlight != null && _refreshCompleterEpoch == _epoch) {
      return inFlight.future;
    }

    final epoch = _epoch;
    _emit(Refreshing(session));
    final completer = Completer<AuthSession>();
    _refreshCompleter = completer;
    _refreshCompleterEpoch = epoch;
    unawaited(_runRefresh(session, epoch, completer));
    return completer.future;
  }

  /// Carries the identity fields of [previous] over to [refreshed] when the
  /// backend renewed tokens only, so a renewal cannot silently erase who is
  /// signed in (and, with it, the `SessionHandle.userId` sent on logout).
  /// 当后端只续期令牌时，把 [previous] 的身份字段带到 [refreshed] 上，避免续期悄悄
  /// 抹掉「谁在登录」（连带抹掉登出时发送的 `SessionHandle.userId`）。
  AuthSession _mergeRefreshed(AuthSession previous, AuthSession refreshed) {
    if (!preserveSessionDetails) return refreshed;
    return refreshed.copyWith(
      userId: refreshed.userId ?? previous.userId,
      displayName: refreshed.displayName ?? previous.displayName,
      claims: refreshed.claims ?? previous.claims,
    );
  }

  Future<void> _runRefresh(
    AuthSession session,
    int epoch,
    Completer<AuthSession> completer,
  ) async {
    try {
      final renewed = await strategy.refresh(session.refreshToken!);
      if (!_isCurrent(epoch)) {
        completer.completeError(
          NoActiveSessionException(
            message: 'Refresh aborted: session invalidated meanwhile',
          ),
        );
        return;
      }
      final refreshed = _mergeRefreshed(session, renewed);
      await tokenStore.save(refreshed);
      _activate(refreshed);
      completer.complete(refreshed);
    } catch (e) {
      final failure = mapAuthFailure(e);
      if (_isCurrent(epoch)) {
        _emit(AuthError(failure));
        if (refreshFailurePolicy(failure)) {
          try {
            await tokenStore.clear();
          } catch (_) {
            // A store that cannot be cleared must neither strand the completer
            // nor surface as an unhandled async error: local sign-out wins.
            // 无法清空的存储既不能让 completer 悬挂，也不能变成未处理的异步错误：
            // 本地登出优先。
          }
          _emit(const Unauthenticated());
        } else {
          // Transient failure: keep the previous session usable.
          // 瞬时失败：保留上一个可用会话。
          _emit(Authenticated(session));
        }
      }
      completer.completeError(failure);
    } finally {
      if (_refreshCompleter == completer) _refreshCompleter = null;
    }
  }

  /// Proactive refresh runner. Errors are already reflected on the state stream,
  /// so they are swallowed here to avoid leaking an unhandled async error.
  /// 主动刷新的执行入口。错误已体现在状态流上，故在此吞掉，避免泄漏未处理的异步错误。
  Future<void> _refreshQuietly() async {
    try {
      await refresh();
      _proactiveFailures = 0;
    } on AuthException {
      // Intentionally ignored — see the doc comment above. A transient failure
      // must not silently stop proactive renewal, so it is re-armed.
      // 有意忽略——参见上方文档注释。瞬时故障不应让主动续期默默停止，因此重新排程。
      _scheduleProactiveRetry();
    }
  }

  /// Re-arms the proactive refresh after a failed attempt.
  /// 主动续期失败后重新排程。
  void _scheduleProactiveRetry() {
    _cancelProactiveRefresh();
    if (_disposed) return;
    // A policy-driven sign-out leaves no session; nothing left to renew.
    // 策略导致的登出已无会话，没有可续期的内容。
    if (currentSession == null) return;

    _proactiveFailures++;
    // Give up eventually: a permanently broken session should not keep a timer
    // alive forever. Failures are already visible as AuthError on the stream.
    // 最终放弃：彻底坏掉的会话不该让定时器永远活着。失败本身已通过 AuthError 可见。
    if (_proactiveFailures > _autoRefreshMaxRetries) return;

    final delay = _autoRefreshRetryDelay * _proactiveFailures;
    _autoRefreshTimer = Timer(delay, () {
      unawaited(_refreshQuietly());
    });
  }

  void _activate(AuthSession session, {bool scheduleProactive = true}) {
    _emit(Authenticated(session));
    if (scheduleProactive) _scheduleAutoRefresh(session);
  }

  /// Schedule a one-shot [refresh] [autoRefreshAhead] before [AuthSession.expiresAt].
  /// No-op when proactive refresh is disabled, or the session lacks an expiry or
  /// a refresh token.
  ///
  /// A session that is already due is renewed after [autoRefreshMinInterval]
  /// rather than immediately, so a backend that keeps handing out very
  /// short-lived tokens cannot turn renewal into a tight loop.
  /// 在 [AuthSession.expiresAt] 之前 [autoRefreshAhead] 调度一次 [refresh]。
  /// 当未开启主动刷新、或会话缺少过期时间 / 刷新令牌时为空操作。
  ///
  /// 已经到期的会话会在 [autoRefreshMinInterval] 后续期，而不是立刻续期，以免后端
  /// 持续发放极短寿命的令牌时把续期变成紧密循环。
  void _scheduleAutoRefresh(AuthSession session) {
    _cancelProactiveRefresh();
    final ahead = _autoRefreshAhead;
    if (ahead == null ||
        session.expiresAt == null ||
        session.refreshToken == null) {
      return;
    }
    final delay = session.expiresAt!.difference(clock()) - ahead - clockSkew;
    if (delay <= Duration.zero) {
      // Already due, so renew at once — unless a renewal only just ran: then the
      // next one waits its turn instead of spinning.
      // 已经到期，于是立刻续期 —— 除非刚刚才续过一次：那时下一轮会稍等，而不是连轴转。
      final wait = _throttleWait();
      if (wait <= Duration.zero) {
        _renewNow();
      } else {
        _autoRefreshTimer = Timer(wait, _renewNow);
      }
      return;
    }
    _autoRefreshTimer = Timer(delay, _renewNow);
  }

  /// Starts a proactive renewal and remembers when it began, so a series of
  /// already-due renewals is throttled by [_throttleWait].
  /// 启动一次主动续期并记下开始时刻，使一连串「已到期」的续期能被 [_throttleWait] 节流。
  void _renewNow() {
    _lastProactiveRefreshAt = clock();
    unawaited(_refreshQuietly());
  }

  /// How long an already-due renewal must still wait under
  /// [autoRefreshMinInterval].
  /// 在 [autoRefreshMinInterval] 之下，一次「已到期」的续期还需等待多久。
  Duration _throttleWait() {
    final last = _lastProactiveRefreshAt;
    if (last == null) return Duration.zero;
    final since = clock().difference(last);
    return since >= _autoRefreshMinInterval
        ? Duration.zero
        : _autoRefreshMinInterval - since;
  }

  void _cancelProactiveRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  void _emit(AuthState state) {
    // Suppress consecutive duplicates so UIs do not rebuild for a no-op change.
    // 抑制连续重复值，避免 UI 因无变化的通知而重建。
    if (_state == state) return;
    _state = state;
    if (!_controller.isClosed) _controller.add(state);
    _notifyObserver(state);
  }

  /// Observers are a side channel: the state has already been emitted by the time
  /// this runs, so a throwing callback must not corrupt the state machine.
  /// 观察者是旁路：执行到这里时状态已经发出，因此回调抛出的异常不能破坏状态机。
  void _notifyObserver(AuthState state) {
    final observer = onStateChanged;
    if (observer == null) return;
    try {
      observer(state);
    } catch (_) {
      // Deliberately swallowed — logging or analytics must never break auth.
      // 有意吞掉 —— 日志或埋点绝不能破坏认证流程。
    }
  }
}
