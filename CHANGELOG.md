# Changelog

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
