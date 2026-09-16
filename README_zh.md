# Zero Auth

<div align="center" style="display: flex; align-items: center; justify-content: center; gap: 36px;">
<span style="font-size: 1.1em; padding: 0 8px;"><strong>简体中文</strong> &nbsp;|&nbsp; <a href="README.md">English</a></span>
</div>

一个**后端无关的认证状态机与会话生命周期**库，面向 Dart/Flutter：它描述「谁已登录、是谁、以及如何登录 / 登出 / 恢复」——纯 Dart、无头（headless）内核，**不**含任何原生代码、后端 SDK、UI 或状态管理框架。

[![License: MPL-2.0](https://img.shields.io/badge/License-MPL--2.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Dart%20%7C%20Flutter-green.svg)](https://pub.dev/packages/zero_auth)
[![Flutter](https://img.shields.io/badge/Flutter-✓-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-✓-0175C2?logo=dart)](https://dart.dev)
[![Style: effective dart](https://img.shields.io/badge/style-effective_dart-40c4ff.svg)](https://pub.dev/packages/effective_dart)

> **🔔 推荐升级：** `0.1.0` 是 `zero_auth` 的首个公开版本，也是建议锁定的版本——它提供显式的认证状态机（`Unauthenticated → Authenticating → Authenticated → AuthError`）、单飞刷新与静默恢复、后端无关的 `AuthStrategy` 边界、可插拔的 `TokenStore` 持久化、统一的 `AppException` 错误，以及可直接用于 Dio 拦截器的 `AuthTokenSource`。请使用 `zero_auth: ^0.1.0`（Git 方式用 `ref: v0.1.0`）。

🌐 **[官方网站](https://www.zerolabsco.com/)** &nbsp;·&nbsp; 📦 **[在 pub.dev 查看](https://pub.dev/packages/zero_auth)** &nbsp;·&nbsp; 🔗 **[查看 GitHub 仓库](https://github.com/zero-foundation/zero_auth)**

---

## 目录

- [功能特性](#功能特性)
- [安装](#安装)
- [使用方法](#使用方法)
  - [快速开始](#快速开始)
  - [接入后端（`AuthStrategy`）](#接入后端-authstrategy)
  - [持久化会话（`TokenStore`）](#持久化会话-tokenstore)
  - [为网络附加令牌（`AuthTokenSource`）](#为网络附加令牌-authtokensource)
  - [示例 App 与演示后端](#示例-app-与演示后端)
- [API 参考](#api-参考)
- [架构](#架构)
- [贡献](#贡献)
- [许可证](#许可证)

---

## 功能特性

- **后端无关**：纯 Dart 内核；实现 `AuthStrategy` 即可接入任意后端（REST、gRPC、Firebase、自有 RPC……）。
- **显式状态机**：`Unauthenticated → Authenticating → Authenticated → AuthError`，以「重放最近值」的广播流对外暴露。
- **静默恢复与刷新**：启动时恢复持久化会话，并透明刷新令牌（单飞机制，并发调用方共享同一次刷新）。
- **可插拔持久化**：`TokenStore` 是唯一的持久化边界；内核自带 `InMemoryTokenStore`，生产环境使用安全存储（见 `example/`）。
- **统一错误**：领域失败映射为 `AppException`（来自本包的错误内核）；绝不直接跨公共面抛裸 `Exception`。
- **面向网络**：`AuthTokenSource` 是扩展点，让 Dio / GraphQL 拦截器能为请求附加 `Authorization: Bearer` 头。
- **零原生代码**：无插件、无 `dart:io`-only API；可在服务端、CLI 与 Flutter 中运行。
- **强类型会话**：`AuthSession` 携带访问 / 刷新令牌、过期时间与原始 claims。

## 安装

### Pub.dev（推荐）

```yaml
dependencies:
  zero_auth: ^0.1.0
```

### Git

```yaml
dependencies:
  zero_auth:
    git:
      url: https://github.com/zero-foundation/zero_auth.git
      ref: v0.1.0   # 固定到发布标签，而不是会移动的分支
```

## 使用方法

### 快速开始

```dart
import 'package:zero_auth/zero_auth.dart';

final auth = AuthManager(strategy: MyAuthStrategy());

void main() async {
  await auth.restore();        // 应用启动时恢复持久化会话
  auth.state.listen((s) {      // 订阅状态变化（重放最近值）
    print(s);
  });

  await auth.login(Credentials(username: 'me', password: '••••'));
}
```

### 接入后端（`AuthStrategy`）

```dart
class MyAuthStrategy implements AuthStrategy {
  @override
  Future<AuthSession> login(Credentials c) => api.login(c.username, c.password);

  @override
  Future<AuthSession> register(RegistrationInput i) => api.register(i);

  @override
  Future<void> logout(SessionHandle h) => api.logout(h.userId);

  @override
  Future<AuthSession> refresh(RefreshToken t) => api.refresh(t.value);
}
```

### 持久化会话（`TokenStore`）

内核仅自带 `InMemoryTokenStore`。生产环境请注入安全存储 —— 基于 `flutter_secure_storage` 的参考实现位于 `example/lib/secure_token_store.dart`：

```dart
final auth = AuthManager(
  strategy: MyAuthStrategy(),
  tokenStore: SecureTokenStore(),   // 来自 example/
);
```

### 为网络附加令牌（`AuthTokenSource`）

`AuthManager` **本身就是一个** `AuthTokenSource`。把它交给 Dio 拦截器（参考实现位于 `example/lib/dio_interceptor.dart`）：

```dart
dio.interceptors.add(AuthInterceptor(auth)); // 自动添加 `Authorization: Bearer <token>`
```

### 示例 App 与演示后端

仓库内置两个可直接运行的部分，方便端到端验证完整生命周期：

- `example/` —— 驱动 `AuthManager` 的 Flutter 示例 App（登录 / 刷新 / 登出 / 调用受保护接口）。
- `server/` —— 供示例使用的零依赖 `dart:io` 后端（无需 `pub get`）。

**1. 启动演示后端**

```bash
cd server
dart run bin/server.dart        # 监听 http://localhost:8080
```

| 方法与路径 | 请求 | 响应 |
|------------|------|------|
| `POST /login` | `{ "username": "a", "password": "b" }` | `200` 令牌（`expiresIn: 3600`）· `401 invalid_credentials` |
| `POST /refresh` | `{ "refreshToken": "demo-refresh-token" }` | `200` 新令牌 · `401 invalid_refresh_token` |
| `POST /logout` | – | `200 { "ok": true }` |
| `GET /me` | 请求头 `Authorization: Bearer demo-access-token` | `200 { "userId", "displayName" }` · `401 unauthorized` |

用户名任意，但**密码必须是 `b`** —— 其它值都会返回 `401`，这是观察 `AuthError` 分支最简单的方式。已开启 CORS，Flutter Web 构建可直接调用。

**2. 运行示例 App**

```bash
cd example
flutter run
```

- App **默认连接真实后端**；拨动 AppBar 开关可回退到离线假后端（`_DemoStrategy`），无需起服务。
- 用任意用户名 + 密码 `b` 登录，再点击 **Call /me**，即可看到 `AuthInterceptor` 附加 `Authorization: Bearer …`，后端回显用户信息。
- 关掉后端再登录，会看到映射后的 `network_unreachable` 错误，而不是裸的 `DioException`。

> Android 模拟器请使用 `http://10.0.2.2:8080` 代替 `localhost`（见 `example/lib/main.dart` 的 `_baseUrl`）。

## API 参考

| 类型 | 职责 |
|------|------|
| `AuthManager` | 编排状态机与会话生命周期，主入口。 |
| `AuthState` | 密封状态：`Unauthenticated` / `Authenticating` / `Authenticated` / `AuthError`。 |
| `AuthSession` | 当前会话：访问 / 刷新令牌、过期时间、显示名、原始 claims。 |
| `AuthStrategy` | 由你实现的后端边界（login / register / logout / refresh）。 |
| `TokenStore` | 当前会话的持久化边界（`save` / `load` / `clear`）。 |
| `AuthTokenSource` | 供网络层使用的只读访问令牌来源。 |
| `AppException` | 唯一的公共错误类型（来自本包的错误内核）。 |
| `Result<T>` | 显式 `Ok` / `Err` 成功-失败包装。 |

## 架构

```
        login/register            success                refresh fails
   ┌──────────────┐ ┌───────────────┐ ┌──────────────────┐
   │ Unauthenticated │──▶│ Authenticating │──▶│  Authenticated   │
   └──────────────┘ └───────────────┘ └──────────────────┘
          ▲                              │   │   ▲
          │          AuthError ◀─────────┘   │   │ token near expiry
          │              │                   │   │ (single-flight refresh)
          │              └───────────────────┘   ▼
          └──────────────────────────────── logout / refresh failure ──┘
```

管理器不含 UI、后端或原生代码。通过 `AuthStrategy` 接入后端，通过 `TokenStore` 接入持久化；网络层只依赖 `AuthTokenSource`。

## 贡献

欢迎贡献代码！提交 issue 或 pull request 前，请先阅读[贡献指南](CONTRIBUTING.md)。

- 🐛 [报告 Bug](https://github.com/zero-foundation/zero_auth/issues/new?template=bug_report.md)
- 💡 [功能建议](https://github.com/zero-foundation/zero_auth/issues/new?template=feature_request.md)
- 💬 [参与讨论](https://github.com/zero-foundation/zero_auth/discussions)

## 许可证

版权所有 (c) 2026 Zero Labs Co. (AmisKwok)。本项目采用 **Mozilla Public License 2.0（MPL-2.0）** 授权 — 详见 [LICENSE](LICENSE) 文件。版权声明与附加声明（免责、禁止背书）见 [NOTICE](NOTICE)。

- **允许商用**：可自由使用、修改与闭源分发。
- **修改了包？** 被修改的文件必须以 MPL-2.0 公开源码；你自己的 App **无需**开源。
- **未修改直接使用？** 无需公开任何源码。
- **禁止背书**：未经书面许可，不得以 "Zero Labs Co."、"zero_auth"、项目 Logo / 吉祥物形象及作者名义（AmisKwok）为衍生品背书、宣传或暗示官方赞助 / 关联。
- **免责声明**：版权方不对任何修改版或衍生版提供担保，也不承担相应责任；修改版必须明确标注已被修改。

本包按"原样"提供，不提供任何担保。作者不对修改版或衍生项目的功能、安全性及任何使用后果承担责任。
