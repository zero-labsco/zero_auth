# Zero Auth

A backend-agnostic auth state machine & session lifecycle core for Dart/Flutter. Pure Dart, headless, no HTTP/SDK/native code. Wire your own backend via `AuthStrategy` and your own persistence via `TokenStore`.

一个后端无关的认证状态机与会话生命周期内核，面向 Dart/Flutter。纯 Dart、无头（headless），不含 HTTP、SDK 或原生代码。通过 `AuthStrategy` 接入自有后端，通过 `TokenStore` 接入自有持久化层。

## ✨ Features / 功能特性

| Feature | Description |
|---------|-------------|
| **Backend-agnostic** | Implement only `login`/`register`/`logout`/`refresh`; REST, gRPC, Firebase or a private RPC are equally valid targets / 只需实现四个方法，REST、gRPC、Firebase 或私有 RPC 均可接入 |
| **Auth State Machine** | Sealed `Unauthenticated` / `Authenticating` / `Authenticated` / `Refreshing` / `LoggingOut` / `AuthError` on a `Stream<AuthState>` that replays the latest value to new listeners; use `isAuthenticated` / `isBusy` / 密封六态状态机 + 重放最近值的状态流，可用 `isAuthenticated` / `isBusy` |
| **Silent Restore** | `restore()` rehydrates the persisted session at startup / 启动时静默恢复持久化会话 |
| **Single-flight Refresh** | Concurrent `refresh()` calls share one in-flight request instead of stampeding the backend / 并发刷新共享同一次请求，避免冲击后端 |
| **Pluggable Persistence** | The only persistence surface is `TokenStore.save/load/clear`; `InMemoryTokenStore` ships in-core / 唯一的持久化接口，内核自带内存实现 |
| **Typed Session** | `AuthSession` carries access/refresh tokens, expiry (`isExpired`), user id, display name and raw claims / 强类型会话，无需手工解析令牌 |
| **Unified Errors** | Every failure maps to `AppException` (`AuthException` for auth cases) or a `Result<T>` wrapper; raw exceptions never cross the public surface / 统一异常与结果，裸异常不越界 |
| **Network Integration** | `AuthManager` itself is an `AuthTokenSource`, so a Dio interceptor can attach `Authorization: Bearer` without depending on the manager / 管理器即令牌源，Dio 拦截器零依赖附加令牌 |
| **Session Serialization** | `AuthSession.toJson` / `fromJson` make persistence a one-liner; a file-based reference store ships for server/CLI / `AuthSession.toJson` / `fromJson` 让持久化一行搞定，并附带面向服务端 / CLI 的文件参考存储 |
| **Proactive Auto-refresh** | Pass `autoRefreshAhead` to renew tokens before expiry (single-flight) / 传入 `autoRefreshAhead` 在过期前自动续期（单飞） |
| **Never an Expired Token** | `validAccessToken()` renews first when the token has expired, so interceptors never send a dead bearer token / 令牌过期时先续期，拦截器不会发出失效令牌 |
| **Bring Your Own Login** | `loginWith` adopts a session from any flow you drive: third-party OAuth, magic links, passkeys / `loginWith` 可接纳第三方 OAuth、魔法链接、Passkey 等自定义流程 |
| **Typed Auth Exceptions** | `InvalidCredentialsException`, `SessionExpiredException` and friends, mapped from your strategy's `code` / `InvalidCredentialsException`、`SessionExpiredException` 等，由策略的 `code` 映射而来 |
| **Configurable Failure Policy** | `refreshFailurePolicy` decides whether a failed refresh signs the user out / `refreshFailurePolicy` 决定刷新失败是否登出 |
| **Runnable Example** | A full Flutter demo app (Android/iOS/Web/Windows) plus a layered `dart:io` demo backend that issues real JWTs / 完整 Flutter 示例与一个签发真实 JWT 的分层演示后端 |
| **Cross-platform** | Pure Dart — runs anywhere Dart or Flutter runs / 纯 Dart，跨平台 |

## 📚 Table of Contents / 目录

| Page | Description |
|------|-------------|
| [Getting Started](Getting-Started) | Quick start guide / 快速开始 |
| [Installation](Installation) | How to install / 安装方式 |
| [Usage](Usage) | Detailed usage / 详细使用 |
| [Auth State Machine](Auth-State-Machine) | State lifecycle & stream / 状态机与状态流 |
| [Backend Strategy](Backend-Strategy) | Implement `AuthStrategy` / 实现后端边界 |
| [Token Store](Token-Store) | Persistence boundary / 持久化边界 |
| [Network Integration](Network-Integration) | Dio interceptor & token source / 网络集成与拦截器 |
| [Errors](Errors) | Exception & `Result` model / 异常与结果模型 |
| [Configuration](Configuration) | Configuration options / 配置说明 |
| [Session Persistence](Persistence) | Restoring and renewing a saved session / 会话持久化与恢复 |
| [Third-Party Login](Third-Party-Login) | OAuth / magic links via `loginWith` / 用 `loginWith` 接入第三方登录 |
| [FAQ](FAQ) | Frequently asked questions / 常见问题 |

## 🔗 Links / 链接

- [GitHub](https://github.com/zero-labsco/zero_auth)
- [Official Website](https://www.zerolabsco.com/)
- [pub.dev](https://pub.dev/packages/zero_auth)

## 📄 License / 许可证

This project is licensed under the **Mozilla Public License 2.0 (MPL-2.0)**.

本项目采用 Mozilla Public License 2.0 (MPL-2.0) 许可证。

This package is provided "as is", without warranty of any kind. The author assumes no responsibility or liability for the functionality, security, or any consequences arising from the use of modified versions or derivative projects.

本包按"原样"提供，不提供任何担保。作者不对修改版或衍生项目的功能、安全性及任何使用后果承担责任。
