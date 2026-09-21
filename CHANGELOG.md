# Changelog

## 1.0.0

**First stable release / 首个稳定版本.** From here on the public surface follows
strict semver: a `1.x` release never breaks it, and every new symbol is additive.
从本版本起，公共 API 严格遵循语义化版本：`1.x` 绝不做破坏性变更，新增能力一律以
追加方式提供。

### Fixed / 修复

- **`restore()` no longer signs the user out on a transient renewal failure.**
  An expired persisted session plus a network hiccup used to clear the store and
  land on `Unauthenticated` — the opposite of what `refreshFailurePolicy` promises.
  A transient failure now keeps the persisted session so the next call can retry;
  only a terminal one clears it.
  - **`restore()` 不再因瞬时续期失败而让用户登出。** 过去「持久化会话已过期 + 网络抖动」
    会清空存储并落到 `Unauthenticated`，与 `refreshFailurePolicy` 的承诺正好相反。现在
    瞬时失败会保留持久化会话以便下次重试，只有终局失败才会清空。
- **A late refresh can no longer overwrite a newer session.** `login`, `register`,
  `loginWith` and `updateSession` now join the epoch guard, so a renewal started
  before them is aborted instead of replacing the session they just installed (or
  writing a token minted from an already-rotated refresh token).
  - **迟到的刷新再也无法覆盖更新的会话。** `login`、`register`、`loginWith` 与
    `updateSession` 现在都参与 epoch 守卫：在它们之前启动的续期会被中止，而不是替换
    刚安装的会话（也不会写回由已轮换的刷新令牌换来的令牌）。
- **A renewal no longer erases who is signed in.** Backends that return tokens only
  used to drop `userId` / `displayName` / `claims` — which also emptied the
  `SessionHandle.userId` sent on logout. The identity now carries over.
  - **续期不再抹掉「谁在登录」。** 只返回令牌的后端过去会丢失 `userId` / `displayName` /
    `claims`，连带让登出时发送的 `SessionHandle.userId` 变空。现在身份字段会被保留。
- **`mapAuthFailure` honours the `code` of a bare `AuthFail`.** Throwing the
  documented domain failure type no longer flattens every case into
  `UnexpectedAuthException`.
  - **`mapAuthFailure` 现在认得裸 `AuthFail` 的 `code`。** 抛出文档推荐的领域失败类型，
    不再把所有情况都压成 `UnexpectedAuthException`。
- **`claims` are compared structurally.** Nested maps and lists participate in
  equality (and hashing), so a change buried inside `claims` is no longer swallowed
  by the duplicate-emission filter.
  - **`claims` 改为结构化比较。** 嵌套的 Map / List 参与相等性与哈希比较，藏在
    `claims` 内部的变化不再被去重逻辑吞掉。
- **An already-due proactive renewal is throttled** by `autoRefreshMinInterval`
  (default 5s), so a backend handing out very short-lived tokens cannot turn
  renewal into a tight loop.
  - **「已到期」的主动续期现在有节流**（`autoRefreshMinInterval`，默认 5 秒），后端持续
    发放极短寿命的令牌时不会把续期变成紧密循环。
- **Concurrent `restore()` calls share one attempt**, instead of racing to load and
  activate two sessions.
  - **并发的 `restore()` 共享同一次尝试**，不再争抢读取并激活两个会话。
- **Dropping an unrenewable session completes even when the store fails**: the
  sign-out happens first and the store error is reported afterwards.
  - **丢弃无法续期的会话在存储出错时也能完成**：先完成登出，再上报存储错误。
- **A throwing `onStateChanged` observer can no longer corrupt the state machine.**
  The observer is a side channel, so its error is swallowed after the state has
  already been emitted to the stream.
  - **抛异常的 `onStateChanged` 观察者再也不会破坏状态机。** 观察者只是旁路，状态已发
    到流上之后，它的异常会被吞掉。
- **`AuthManagerGroup` forgets a manager disposed outside the group**, instead of
  silently keeping a released manager as the active one.
  - **`AuthManagerGroup` 会遗忘在分组之外被释放的管理器**，不再把已释放的管理器悄悄
    当作激活账号。

### Changed / 变更

- **BREAKING: `AuthTokenSource` gained `validAccessToken({Duration? leeway})`.**
  Implementations that only declare `accessToken` must add one line:
  `@override Future<String?> validAccessToken({Duration? leeway}) async => accessToken;`.
  `AuthManager` (and `AuthManagerGroup`) override it with a renewing version, so
  network layers can now guarantee an unexpired token through the interface alone.
  - **破坏性：`AuthTokenSource` 新增 `validAccessToken({Duration? leeway})`。** 只声明
    `accessToken` 的实现需补一行：`@override Future<String?> validAccessToken({Duration? leeway}) async => accessToken;`。
    `AuthManager`（与 `AuthManagerGroup`）会覆写为会续期的版本，因此网络层仅凭接口就能
    拿到保证未过期的令牌。
- **`clockSkew` defaults to 30 seconds.** Tokens are treated as expired that much
  earlier, so a device clock running ahead (or a slow request) cannot hand out a
  token that dies in flight. Pass `Duration.zero` for the old behaviour.
  - **`clockSkew` 默认为 30 秒。** 令牌会提前这么多被视为过期，避免设备时钟偏快（或请求
    较慢）时发出一个途中失效的令牌。传 `Duration.zero` 可恢复旧行为。
- **A single-flight refresh is only joined within the same epoch.** Concurrent
  callers still share one backend call, but never one that started before the
  session was replaced.
  - **单飞刷新只在同一 epoch 内被共享。** 并发调用方仍共享同一次后端调用，但不会共享
    会话被替换之前启动的那一次。
- `logout()` invalidates in-flight work **before** calling the backend, so a
  renewal that lands mid-logout can no longer flash `Authenticated`.
  - `logout()` 在调用后端**之前**就让进行中的工作失效，登出途中落地的续期不会再闪一下
    `Authenticated`。

### Added / 新增

- **`clockSkew`** — how much earlier a token counts as expired (default 30s), plus
  **`validAccessToken(leeway:)`** for a per-call override.
  - **`clockSkew`** —— 提前多久把令牌视为过期（默认 30 秒）；另有
    **`validAccessToken(leeway:)`** 供单次调用覆盖。
- **`autoRefreshMinInterval`** — floor for a proactive renewal that is already due
  (default 5s).
  - **`autoRefreshMinInterval`** —— 「已到期」主动续期的最小等待（默认 5 秒）。
- **`preserveSessionDetails`** — carry identity fields across a renewal that only
  returns tokens (default `true`; set `false` to keep the backend answer verbatim).
  - **`preserveSessionDetails`** —— 在只返回令牌的续期中保留身份字段（默认 `true`；
    设为 `false` 则原样使用后端响应）。
- **`AuthSession.tryFromJson`** — deserialize without throwing on malformed input;
  returns `null` instead. Use it for anything read from disk or secure storage.
  - **`AuthSession.tryFromJson`** —— 反序列化畸形数据时不抛异常，而是返回 `null`。
    凡是从磁盘或安全存储读出的内容都建议用它。
- **`AuthState.session`** — the session carried by `Authenticated` / `Refreshing` /
  `LoggingOut`, or `null`; no pattern-matching needed for the common case.
  - **`AuthState.session`** —— `Authenticated` / `Refreshing` / `LoggingOut` 携带的
    会话（无则为 `null`），常见场景无需再做模式匹配。
- **`AuthManagerGroup`**: `managerFactory`, full forwarding of the manager knobs
  (`autoRefreshAhead`, `clockSkew`, `refreshFailurePolicy`, `clock`…), an
  account-tagged `onStateChanged`, **`activeIdChanges`** (a stream of the active
  account id), `validAccessToken()` and a `restoreAll()` that keeps going when one
  account fails.
  - **`AuthManagerGroup`**：新增 `managerFactory`、完整转发管理器调参（`autoRefreshAhead`、
    `clockSkew`、`refreshFailurePolicy`、`clock`……）、带账号标记的 `onStateChanged`、
    **`activeIdChanges`**（激活账号 id 流）、`validAccessToken()`，以及某个账号失败也会
    继续的 `restoreAll()`。

### Stability / 稳定性

- The public surface is now frozen under semver: `AuthState` stays sealed with its
  current six subtypes, `AuthStrategy` stays at four methods, and new capabilities
  arrive as additive symbols (or optional interfaces detected with `supports<T>()`).
  - 公共 API 自此按 semver 冻结：`AuthState` 保持当前六个子类的密封层级，`AuthStrategy`
    保持四个方法，新能力以追加符号（或可用 `supports<T>()` 检测的可选接口）的形式提供。

## 0.5.0

### Fixed / 修复

- **`validAccessToken()` no longer returns an expired token.** When the token had
  expired *and* the session carried no refresh token, it returned the expired
  value — the exact case the method exists to prevent. It now returns `null`.
  - **`validAccessToken()` 不再返回过期令牌。** 当令牌已过期且会话没有刷新令牌时，
    它会返回那个过期值 —— 正是该方法本该防止的情况。现在返回 `null`。
- **`AuthManagerGroup.remove()` cannot leak a manager.** `logout()` may throw (for
  example when the store cannot be cleared), which previously skipped `dispose()`.
  Disposal now happens in a `finally`.
  - **`AuthManagerGroup.remove()` 不再泄漏管理器。** `logout()` 可能抛异常（例如存储
    无法清空），过去会让 `dispose()` 被跳过；现在释放放在 `finally` 中。
- **Using a group after `disposeAll()` is rejected** with
  `AuthException(code: 'group_disposed')` instead of throwing
  `Bad state: Cannot add event after closing` from the closed stream controller.
  `disposeAll()` is also idempotent now.
  - **`disposeAll()` 之后使用分组会被拒绝**（`AuthException(code: 'group_disposed')`），
    不再由已关闭的 stream controller 抛出 `Bad state`。`disposeAll()` 现可重复调用。
- **`restore(refreshIfExpired: false)` no longer triggers a renewal behind the
  caller's back.** An expired session restored verbatim is activated without the
  proactive scheduler immediately refreshing it.
  - **`restore(refreshIfExpired: false)` 不再背着调用方触发续期。** 原样恢复的过期
    会话被激活时，主动调度不会立刻去刷新它。
- **`updateSession()` closes a save race**: it re-checks the session on both sides
  of the (now possibly async) update, and clears the store again if the session was
  invalidated while saving, so a logout cannot leave a session behind.
  - **`updateSession()` 补上保存竞态**：在（现在可能是异步的）更新前后都重新校验，
    若保存期间会话失效则再次清空存储，登出后不会残留会话。

### Changed / 变更

- **Proactive renewal retries are bounded.** A failed renewal is re-armed with a
  linear backoff (30s, 60s, 90s…) up to `autoRefreshMaxRetries` (default 3), instead
  of retrying forever. Failures remain visible as `AuthError` on the stream.
  - **主动续期重试有上限。** 失败后按线性退避（30s、60s、90s…）重新排程，最多
    `autoRefreshMaxRetries` 次（默认 3），不再无限重试。失败仍以 `AuthError` 可见。
- `updateSession()` accepts a `FutureOr<AuthSession>` update, so the new session can
  be fetched over the network first. Sync callers are unaffected.
  - `updateSession()` 接受 `FutureOr<AuthSession>`，可先联网再取新会话；同步调用方不受影响。
- `logoutAll()` signs out every account even if one of them fails, then reports the
  first error.
  - `logoutAll()` 即使某个账号失败也会继续登出其余账号，最后上报第一个错误。

### Added / 新增

- **`AuthSession.copyWith()`** — replace only the fields you pass. Passing `null`
  keeps the current value, as with most hand-written `copyWith`; build a new session
  to clear a field.
  - **`AuthSession.copyWith()`**——只替换传入的字段。与多数手写实现一样，传 `null`
    表示保留原值；要清空字段请新建会话。
- **`AuthSession.timeUntilExpiry()`** and **`isExpiringWithin(window)`** — renew a
  little before the token actually dies.
  - **`AuthSession.timeUntilExpiry()`** 与 **`isExpiringWithin(window)`**——便于在
    令牌真正失效前提前续期。
- **`autoRefreshMaxRetries`** — constructor knob for how many failed proactive
  renewals to retry (default 3).
  - **`autoRefreshMaxRetries`**——构造参数，主动续期失败后最多重试几次（默认 3）。
- **`AuthManagerGroup.restoreAll(dropOthers:)`** — drop managers for accounts that
  are no longer known.
  - **`AuthManagerGroup.restoreAll(dropOthers:)`**——释放不再已知的账号管理器。

## 0.4.0

### Fixed / 修复

- **`restore()` no longer resurrects a session after a logout.** It now takes part
  in the same epoch guard as `login` / `refresh`, so a session loaded from a slow
  `TokenStore` cannot be activated after the user signed out.
  - **`restore()` 不再在登出后「复活」会话。** 它现在与 `login` / `refresh` 一样参与
    epoch 守卫，慢速 `TokenStore` 读出的会话无法在用户登出后被激活。
- **Local logout always completes.** A failing `TokenStore.clear()` used to leave
  the manager stuck in `LoggingOut`; the store error is now reported *after*
  `Unauthenticated` is emitted.
  - **本地登出必定完成。** 过去 `TokenStore.clear()` 出错会让管理器卡在 `LoggingOut`；
    现在先发出 `Unauthenticated`，再上报存储错误。
- **A `TokenStore.load()` failure is treated as "no session"**, matching the
  documented behaviour, instead of escaping without any state change.
  - **`TokenStore.load()` 失败按「无会话」处理**（与文档一致），不再无声抛出。
- **Dropping an unrenewable session now reports why**: `AuthError` is emitted
  before `Unauthenticated`, so a UI can tell "never signed in" apart from
  "session expired".
  - **丢弃无法续期的会话会先说明原因**：先发 `AuthError` 再发 `Unauthenticated`，
    界面可区分「从未登录」与「会话过期」。
- **`AuthSession` equality now includes `claims`**, so a session whose only change
  is in `claims` is no longer swallowed by the duplicate-emission filter.
  - **`AuthSession` 相等性现在包含 `claims`**，仅 claims 变化的会话不再被去重逻辑吞掉。
- **Overlapping authentication flows are rejected** (`auth_flow_in_progress`)
  instead of racing to overwrite the session.
  - **重叠的登录流程会被拒绝**（`auth_flow_in_progress`），不再争抢覆盖会话。
- **`Err.appException`** exposes the mapped domain error; the `error` field stays
  `Object` and its docs no longer over-promise `AppException`.
  - **新增 `Err.appException`** 暴露映射后的领域错误；`error` 仍为 `Object`，文档不再
    过度承诺。
- Docs: the `AuthStrategy` contract shown on the site used pre-0.3.0 signatures
  (`login(String, String)`). It now matches the real API.
  - 文档：站上展示的 `AuthStrategy` 契约仍是 0.3.0 之前的签名（`login(String, String)`），
    现已与真实 API 一致。

### Changed / 变更

- **Operations after `dispose()` throw** `AuthException(code: 'manager_disposed')`
  instead of silently doing nothing.
  - **`dispose()` 之后的操作会抛出** `AuthException(code: 'manager_disposed')`，
    而非静默无作为。
- **A failed proactive refresh is re-armed** after `autoRefreshRetryDelay`
  (default 30s) while a session still exists, so a transient error no longer stops
  renewal silently.
  - **主动刷新失败后会重新排程**（`autoRefreshRetryDelay`，默认 30 秒），只要会话仍在，
    瞬时错误就不会让续期默默停止。
- `SessionHandle` carries an optional `refreshToken` in addition to `userId`.
  - `SessionHandle` 除 `userId` 外还携带可选的 `refreshToken`。

### Added / 新增

- **`AuthManagerGroup`** — an optional coordination layer that keeps one
  [AuthManager] per account, so several accounts can stay signed in at once and
  you can switch between them. It exposes `forAccount`, `switchTo`,
  `restoreAll`, `remove` and `disposeAll`, mirrors the active account through
  `current` / `state` / `currentSession`, and implements `AuthTokenSource` so
  interceptors always read the active account's token.
  - **`AuthManagerGroup`**——可选的协调层，为每个账号持有一个 [AuthManager]，从而让多
    个账号同时保持登录并可切换。它提供 `forAccount`、`switchTo`、`restoreAll`、
    `remove`、`disposeAll`，通过 `current` / `state` / `currentSession` 反映激活账号，
    并实现 `AuthTokenSource`，使拦截器始终读到激活账号的令牌。

- Multi-account is deliberately **opt-in**: `AuthManager` remains single-session,
  because "who is logged in?" and "which of these accounts is active?" are
  different questions. Existing code keeps working unchanged; nothing to migrate.
  - 多账号被刻意设计为**可选**：`AuthManager` 仍是单会话，因为「谁登录了？」与
    「这些账号里哪个是激活的？」是两个不同的问题。现有代码无需任何改动。

- **`updateSession(...)`** — replaces the active session without a re-login, for
  profile updates or refreshed claims. Throws `NoActiveSessionException` when
  nothing is signed in.
  - **`updateSession(...)`**——在不重新登录的情况下替换活动会话，用于资料更新或刷新
    claims。未登录时抛出 `NoActiveSessionException`。
- **Optional capability interfaces** — `SupportsPasswordReset`,
  `SupportsPasswordChange` and `SupportsReauthentication`, detected with
  `AuthManager.supports<T>()` so the four-method contract stays intact.
  - **可选能力接口**——`SupportsPasswordReset`、`SupportsPasswordChange`、
    `SupportsReauthentication`，可用 `AuthManager.supports<T>()` 检测，从而保持
    四方法契约不变。
- **`onStateChanged`** — optional callback invoked for every emitted state, for
  logging or analytics without subscribing to the stream.
  - **`onStateChanged`**——可选回调，每次发出状态时触发，便于无需订阅流即可做日志或埋点。
- **`autoRefreshRetryDelay`** — constructor knob controlling how soon a failed
  proactive renewal is re-armed (default 30s).
  - **`autoRefreshRetryDelay`**——构造参数，控制主动续期失败后多久重新排程（默认 30 秒）。
- **`AuthManagerGroup.addAccount`** and **`logoutAll()`** — explicit registration
  and signing out every account at once.
  - **`AuthManagerGroup.addAccount`** 与 **`logoutAll()`**——显式注册账号，以及一次性
    登出所有账号。
- Example: **`AuthRetryInterceptor`** — retries a request once after a transparent
  refresh, for backends that return 401 on an early-revoked token.
  - 示例：新增 **`AuthRetryInterceptor`**——在透明续期后重试一次请求，适用于令牌被提前
    吊销时返回 401 的后端。

### Docs / 文档

- New **Multi-Account** cookbook covering both shapes: switching between
  accounts (logout + login is usually enough) and genuinely concurrent accounts
  (use `AuthManagerGroup`).
  - 新增**多账号** cookbook，覆盖两种形态：账号切换（登出再登录通常足够）与真正的
    多账号并存（使用 `AuthManagerGroup`）。

## 0.3.0

### Added / 新增

- **`loginWith` escape hatch** — adopt a session produced by any flow you drive
  yourself (third-party OAuth, magic links, passkeys, biometric unlock) while the
  manager keeps owning persistence, the state machine and proactive refresh.
  - **`loginWith` 逃生口**——接纳由你自行驱动的任意流程（第三方 OAuth、魔法链接、
    Passkey、生物识别解锁）所产生的会话，而持久化、状态机与主动刷新仍由管理器负责。
- **`validAccessToken()`** — returns a token guaranteed not to be expired,
  refreshing first when needed (reusing the single-flight refresh). Ideal for HTTP
  interceptors; returns `null` when unauthenticated.
  - **`validAccessToken()`**——返回保证未过期的令牌，必要时先续期（复用单飞刷新）。
    非常适合 HTTP 拦截器；未认证时返回 `null`。
- **Typed auth exceptions** — `InvalidCredentialsException`,
  `SessionExpiredException`, `NoActiveSessionException`,
  `RefreshTokenMissingException` and `UnexpectedAuthException`, plus
  `mapAuthFailure`, which maps your strategy's `AuthException.code` onto them and
  preserves any vocabulary it does not recognise.
  - **类型化认证异常**——新增 `InvalidCredentialsException`、`SessionExpiredException`、
    `NoActiveSessionException`、`RefreshTokenMissingException`、`UnexpectedAuthException`，
    以及 `mapAuthFailure`：它按你策略里 `AuthException.code` 映射为具体子类，并保留
    无法识别的自定义错误类型。
- **Refresh failure policy** — `AuthManager.refreshFailurePolicy` (defaults to
  `defaultRefreshFailurePolicy`) decides whether a failed refresh ends the
  session: unrecoverable failures sign the user out, transient ones keep it.
  - **刷新失败策略**——`AuthManager.refreshFailurePolicy`（默认为
    `defaultRefreshFailurePolicy`）决定一次刷新失败是否终止会话：不可恢复的失败会让
    用户登出，瞬时故障则保留会话。
- **`clock` injection** — override the time source used for expiry maths and
  proactive scheduling, for deterministic tests and to tolerate device clock skew.
  - **`clock` 注入**——可覆盖过期计算与主动刷新调度所用的时间源，用于确定性测试与
    容忍设备时钟偏移。
- **`AuthState.isBusy`** — `true` while `Authenticating`, `Refreshing` or
  `LoggingOut`; handy for spinners and disabling buttons.
  - **`AuthState.isBusy`**——在 `Authenticating`、`Refreshing`、`LoggingOut` 期间为
    `true`，可用于加载态与禁用按钮。

### Changed / 变更

- **BREAKING: two new `AuthState` subtypes.** `Refreshing` and `LoggingOut` join
  the sealed hierarchy, so exhaustive `switch` statements must handle them.
  Prefer `state.isAuthenticated` / `state.isBusy`, which stay correct as states
  evolve.
  - **破坏性：`AuthState` 新增两个子类。**`Refreshing` 与 `LoggingOut` 加入密封层级，
    穷举 `switch` 必须处理它们。建议改用 `state.isAuthenticated` / `state.isBusy`，
    这样后续状态演进也不会失效。
- **BREAKING: `isAuthenticated` semantics.** It is now `true` for `Refreshing` as
  well, so renewing a token no longer unmounts signed-in UI mid-refresh.
  - **破坏性：`isAuthenticated` 语义变更。** 它在 `Refreshing` 期间同样为 `true`，
    令牌续期不再让已登录界面中途被卸载。
- **`restore()` heals expired sessions.** An expired persisted session now
  triggers a refresh; if it cannot be renewed (or there is no refresh token) the
  store is cleared and the manager lands on `Unauthenticated`. Pass
  `refreshIfExpired: false` to restore it verbatim as before.
  - **`restore()` 会修复过期会话。** 持久化会话若已过期会先触发刷新；若无法续期
    （或没有刷新令牌），则清空存储并落到 `Unauthenticated`。传
    `refreshIfExpired: false` 可沿用过去的原样恢复行为。
- **`refresh()` emits `Refreshing` while in flight**, and throws the new
  `NoActiveSessionException` / `RefreshTokenMissingException` when it cannot start.
  - **`refresh()` 进行中会发出 `Refreshing`**，并在无法启动时抛出新的
    `NoActiveSessionException` / `RefreshTokenMissingException`。
- **Consecutive duplicate states are suppressed**, so listeners only rebuild on a
  real change.
  - **抑制连续重复的状态**，监听器只会在真正变化时重建。

### Fixed / 修复

- Proactive auto-refresh no longer leaks an unhandled async error when the
  background refresh fails.
  - 后台主动刷新失败时，不再泄漏未处理的异步错误。
- A `refresh()` or `login()` landing after `logout()` / `dispose()` no longer
  resurrects the session; late results are dropped by an epoch guard.
  - 迟到的 `refresh()` / `login()` 结果不再让会话「复活」；由 epoch 守卫丢弃。
- A failed `refresh()` no longer leaves the manager silently authenticated with a
  stale token: the failure policy now lands it on `Unauthenticated` or back on the
  previous session, always after reporting `AuthError`.
  - `refresh()` 失败后不再「静默保持登录并持有过期令牌」：失败策略会在上报
    `AuthError` 之后，落到 `Unauthenticated` 或回到上一个会话。
- Failures thrown by an `AuthStrategy` keep their own vocabulary when the code is
  unrecognised, instead of being flattened into a generic auth exception.
  - `AuthStrategy` 抛出的失败在 code 无法识别时会保留其原有类型，而不再被压平为
    通用的认证异常。

## 0.2.0

### Added / 新增

- **Session (de)serialization** — `AuthSession` now exposes `toJson()` /
  `AuthSession.fromJson()` (and `RefreshToken` gains matching `toJson()` /
  `fromJson()`), so a session can be persisted to disk or secure storage and
  rehydrated losslessly across app restarts. `null` fields are omitted and
  `claims` round-trips as a plain map.
  - **会话（反）序列化**——`AuthSession` 现提供 `toJson()` / `AuthSession.fromJson()`
    （`RefreshToken` 也增加对应的 `toJson()` / `fromJson()`），会话可被持久化到
    磁盘或安全存储，并在应用重启后无损恢复。`null` 字段会被省略，`claims`
    作为普通映射原样往返。
- **Proactive auto-refresh** — `AuthManager` accepts a new optional
  `autoRefreshAhead` duration. When a session carries both an `expiresAt` and a
  refresh token, the manager schedules a single-flight `refresh()` that many
  minutes before expiry, so callers rarely hit an expired access token. Disabled
  by default (backwards compatible).
  - **临近过期自动刷新**——`AuthManager` 新增可选参数 `autoRefreshAhead`。当会话同时
    带有 `expiresAt` 与刷新令牌时，管理器会在过期前该时长调度一次单飞 `refresh()`，
    调用方几乎不会撞上过期的访问令牌。默认关闭，向后兼容。

### Example / 示例

- Added `example/lib/json_token_store.dart` — a `dart:io` file-backed
  `TokenStore` built on the new serialization, for server / CLI / desktop.
  - 新增 `example/lib/json_token_store.dart`——基于新序列化、面向服务端 / CLI /
    桌面的 `dart:io` 文件型 `TokenStore`。

## 0.1.0

### Added / 新增

- **Auth state machine** — `AuthManager` drives the explicit
  `Unauthenticated → Authenticating → Authenticated → AuthError` lifecycle and
  broadcasts it on a `Stream<AuthState>` that replays the latest value to new
  listeners, so a widget can render the correct screen on its first frame.
  - **认证状态机**——`AuthManager` 驱动显式的
    `Unauthenticated → Authenticating → Authenticated → AuthError` 生命周期，
    并通过「重放最近值」的 `Stream<AuthState>` 广播，使 widget 在首帧即可渲染正确界面。
- **Backend boundary (`AuthStrategy`)** — a single four-method interface
  (`login` / `register` / `logout` / `refresh`) is all a backend has to
  implement. The core ships no HTTP, no SDK and no native code, so REST, gRPC,
  Firebase or a private RPC are equally valid targets.
  - **后端边界（`AuthStrategy`）**——后端只需实现 `login` / `register` / `logout` /
    `refresh` 四个方法。内核不含任何 HTTP、SDK 或原生代码，因此 REST、gRPC、Firebase
    或自有 RPC 均可平等接入。
- **Silent restore & single-flight refresh** — `restore()` rehydrates the
  persisted session at startup, and concurrent `refresh()` callers share one
  in-flight request instead of stampeding the backend; a failed refresh clears
  the session and emits `AuthError`.
  - **静默恢复与单飞刷新**——`restore()` 在启动时恢复持久化会话；并发的 `refresh()`
    调用方共享同一次进行中的请求，而不会同时冲击后端；刷新失败会清空会话并发出 `AuthError`。
- **Pluggable persistence (`TokenStore`)** — the only persistence surface is
  `save` / `load` / `clear`. `InMemoryTokenStore` ships in the core; a
  `flutter_secure_storage`-backed reference implementation lives in
  `example/lib/secure_token_store.dart` for production use.
  - **可插拔持久化（`TokenStore`）**——唯一的持久化接口是 `save` / `load` / `clear`。
    内核自带 `InMemoryTokenStore`；生产可用的
    `flutter_secure_storage` 参考实现位于 `example/lib/secure_token_store.dart`。
- **Strongly-typed session (`AuthSession`)** — carries access token, refresh
  token, expiry (`isExpired`), user id, display name and raw claims, so callers
  never parse token payloads by hand.
  - **强类型会话（`AuthSession`）**——携带访问令牌、刷新令牌、过期时间（`isExpired`）、
    用户 ID、显示名与原始 claims，调用方无需手工解析令牌载荷。
- **Unified errors** — every domain failure is mapped to `AppException` from this
  package's error kernel (`AuthException` for auth-specific cases), and a
  `Result<T>` wrapper is available for explicit `Ok` / `Err` handling. Raw
  `Exception`s never cross the public surface.
  - **统一错误**——所有领域失败都映射为本包错误内核的 `AppException`（认证相关场景为
    `AuthException`），并提供 `Result<T>` 以支持显式的 `Ok` / `Err` 处理。
  裸 `Exception` 绝不会跨越公共 API 边界。
- **Network integration (`AuthTokenSource`)** — `AuthManager` itself is an
  `AuthTokenSource`, so a Dio interceptor can attach
  `Authorization: Bearer <token>` without depending on the manager. A ready-to-use
  interceptor lives in `example/lib/dio_interceptor.dart`.
  - **网络集成（`AuthTokenSource`）**——`AuthManager` 本身即是一个 `AuthTokenSource`，
    因此 Dio 拦截器可在不依赖管理器的前提下附加 `Authorization: Bearer <token>`。
    开箱可用的拦截器位于 `example/lib/dio_interceptor.dart`。
- **Runnable example & demo backend** — `example/` is a full Flutter app
  (Android / iOS / Web / Windows) that exercises login, refresh, logout and a
  protected `GET /me` call. `server/` is a zero-dependency `dart:io` backend
  (`dart run bin/server.dart`) exposing `/login`, `/refresh`, `/logout` and
  `/me`; any username works and the password must be `b`, so both the success and
  the `AuthError` path are reproducible without external infrastructure.
  - **可运行示例与演示后端**——`example/` 是完整的 Flutter App
    （Android / iOS / Web / Windows），覆盖登录、刷新、登出与受保护的 `GET /me` 调用；
    `server/` 是零依赖的 `dart:io` 后端（`dart run bin/server.dart`），提供 `/login`、
    `/refresh`、`/logout` 与 `/me`；用户名任意、密码必须是 `b`，
    因此无需外部基础设施即可复现成功与 `AuthError` 两条路径。
