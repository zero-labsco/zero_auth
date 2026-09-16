# Changelog

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
