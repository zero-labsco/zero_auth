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

> **🔔 推荐升级：** `0.4.0` 新增 **`AuthManagerGroup`** —— 一个可选层，为每个账号持有一个 `AuthManager`，从而让多个账号同时保持登录并可相互切换。`AuthManager` 本身仍刻意保持单会话，因此这是纯增量版本，无需任何迁移。请使用 `zero_auth: ^0.4.0`（Git 方式用 `ref: release/v0.4.0`）。

🌐 **[官方网站](https://www.zerolabsco.com/)** &nbsp;·&nbsp; 📦 **[在 pub.dev 查看](https://pub.dev/packages/zero_auth)** &nbsp;·&nbsp; 🔗 **[查看 GitHub 仓库](https://github.com/zero-labsco/zero_auth)**

---

## 目录

- [功能特性](#功能特性)
- [安装](#安装)
- [使用方法](#使用方法)
  - [快速开始](#快速开始)
  - [接入后端（`AuthStrategy`）](#接入后端-authstrategy)
  - [持久化会话（`TokenStore`）](#持久化会话-tokenstore)
  - [为网络附加令牌（`AuthTokenSource`）](#为网络附加令牌-authtokensource)
  - [接入自定义登录流程（`loginWith`）](#接入自定义登录流程-loginwith)
  - [绝不发送过期令牌](#绝不发送过期令牌)
  - [用类型化异常处理失败](#用类型化异常处理失败)
  - [示例 App 与演示后端](#示例-app-与演示后端)
- [API 参考](#api-参考)
- [架构](#架构)
- [文档](#文档)
- [贡献](#贡献)
- [许可证](#许可证)

---

## 功能特性

- **后端无关**：纯 Dart 内核；实现 `AuthStrategy` 即可接入任意后端（REST、gRPC、Firebase、自有 RPC……）。
- **显式状态机**：`Unauthenticated`、`Authenticating`、`Authenticated`、`Refreshing`、`LoggingOut`、`AuthError`，以「重放最近值」的广播流对外暴露。建议用 `state.isAuthenticated` / `state.isBusy` 代替 `state is Authenticated`，这样令牌续期时不会卸载已登录界面。
- **静默恢复与刷新**：启动时恢复持久化会话（会话已过期则先续期），并透明刷新令牌（单飞机制，并发调用方共享同一次刷新）。
- **自带任意登录流程**：`loginWith` 可接纳你自行驱动的流程所产生的会话——第三方 OAuth、魔法链接、Passkey 或生物识别解锁。
- **绝不发送过期令牌**：`validAccessToken()` 在令牌过期时先续期再返回，非常适合 HTTP 拦截器。
- **类型化认证异常**：`InvalidCredentialsException`、`SessionExpiredException` 等，可由你策略里的 `AuthException.code` 自动映射而来。
- **可配置的刷新失败处理**：`refreshFailurePolicy` 决定一次刷新失败是否让用户登出（默认：不可恢复的失败登出，瞬时故障保留会话）。
- **多账号（可选）**：`AuthManagerGroup` 为每个账号持有一个 `AuthManager`，可让多个账号同时保持登录；内核本身仍是单会话。
- **可插拔持久化**：`TokenStore` 是唯一的持久化边界；内核自带 `InMemoryTokenStore`，生产环境使用安全存储（见 `example/`）。
- **统一错误**：领域失败映射为 `AppException`（来自本包的错误内核）；绝不直接跨公共面抛裸 `Exception`。
- **面向网络**：`AuthTokenSource` 是扩展点，让 Dio / GraphQL 拦截器能为请求附加 `Authorization: Bearer` 头。
- **零原生代码**：无插件、无 `dart:io`-only API；可在服务端、CLI 与 Flutter 中运行。
- **强类型会话**：`AuthSession` 携带访问 / 刷新令牌、过期时间与原始 claims。
- **会话（反）序列化**：`AuthSession.toJson` / `AuthSession.fromJson` 让持久化成为一行代码；并附带面向服务端 / CLI 的基于文件的参考存储。
- **临近过期自动刷新**：给 `AuthManager` 传入 `autoRefreshAhead`，令牌会在过期前自动续期（单飞机制），调用方几乎不会撞上过期的访问令牌。

## 安装

### Pub.dev（推荐）

```yaml
dependencies:
  zero_auth: ^0.4.0
```

### Git

```yaml
dependencies:
  zero_auth:
    git:
      url: https://github.com/zero-labsco/zero_auth.git
      ref: release/v0.4.0   # 固定到 release/vX.Y.Z 分支（每个版本不可变）
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

### 接入自定义登录流程（`loginWith`）

第三方 OAuth、魔法链接、Passkey 都是**由你驱动**的流程，`zero_auth` 只负责之后的部分：提供方握手在本包之外（需要平台代码），你的后端校验提供方凭据并签发**你自己的**令牌，再由 `loginWith` 把会话交给管理器：

```dart
Future<AuthSession> signInWithGoogle() async {
  final code = await myOAuthClient.authenticate();        // 在 zero_auth 之外
  final res = await myApi.post('/auth/google', {'code': code});
  return AuthSession(
    accessToken: res['accessToken'] as String,
    refreshToken: RefreshToken(res['refreshToken'] as String),
    expiresAt: DateTime.now().add(Duration(seconds: res['expiresIn'] as int)),
    userId: res['userId'] as String,
  );
}

// 发出 Authenticating -> Authenticated；失败则发 AuthError 并重新抛出。
await auth.loginWith((strategy) => signInWithGoogle());
```

完整模式（含「登录方式对状态机透明」的原因）见
[第三方登录 cookbook](https://zero-labsco.github.io/zero_auth/Third-Party-Login)。

### 绝不发送过期令牌

`accessToken` 返回的是当前会话里的值，**可能已经过期**。网络层请用 `validAccessToken()`：它会在必要时先续期（复用单飞刷新），只有在真的无令牌可发时才返回 `null`。

```dart
final token = await auth.validAccessToken();
if (token != null) headers['Authorization'] = 'Bearer $token';
```

也可以让管理器在过期前主动续期：

```dart
final auth = AuthManager(
  strategy: strategy,
  autoRefreshAhead: const Duration(minutes: 5),
);
```

### 用类型化异常处理失败

失败绝不会以裸 `Exception` 泄漏。你的策略只要抛出带 `code` 的 `AuthException`，就能映射为精确类型：

| `code` | 映射结果 |
|--------|----------|
| `invalid_credentials` | `InvalidCredentialsException` |
| `invalid_grant` / `invalid_refresh_token` / `token_expired` / `session_expired` | `SessionExpiredException` |
| `no_active_session` | `NoActiveSessionException` |
| `refresh_token_missing` | `RefreshTokenMissingException` |
| 其它 | 原样保留，或 `UnexpectedAuthException` |

```dart
try {
  await auth.login(credentials);
} on SessionExpiredException {
  // 授权已失效：只能重新登录
} on InvalidCredentialsException {
  // 显示表单错误
} on AuthException catch (e) {
  // 其它认证失败，仍带有稳定的 e.code
}
```

刷新失败同时也会以 `AuthError` 出现在状态流上。是否终止会话由 `refreshFailurePolicy` 决定：不可恢复的失败让用户登出，瞬时故障保留会话以便重试成功。

### 示例 App 与演示后端

仓库内置两个可直接运行的部分，方便端到端验证完整生命周期：

- `example/` —— 驱动 `AuthManager` 的 Flutter 示例 App（登录 / 刷新 / 登出 / 调用受保护接口）。
- `server/` —— 分层的 `dart:io` 后端，签发真实的 HMAC-SHA256 JWT，带刷新令牌轮换、家族吊销与重放检测，并记录每条请求日志。启动前需要跑一次 `dart pub get`。

**1. 启动演示后端**

```bash
cd server
dart pub get
dart run bin/server.dart        # 监听 http://localhost:8080
```

| 方法与路径 | 请求 | 响应 |
|------------|------|------|
| `POST /login` | `{ "username": "user", "password": "user" }` | `200` 真实 JWT 令牌对 + `expiresIn` · `401 invalid_credentials` |
| `POST /refresh` | `{ "refreshToken": "<轮换中的令牌>" }` | `200` 轮换后的令牌对 · `401 invalid_grant`（过期 / 吊销 / 重放） |
| `POST /logout` | `{ "refreshToken": "…" }` | `200 { "ok": true }`，并吊销该令牌家族 |
| `GET /me` | 请求头 `Authorization: Bearer <访问令牌>` | `200 { "userId", "displayName" }` · `401 invalid_token` |
| `GET /health` | – | `200 { "status": "ok", … }` |
| `POST /debug/expire-access` | – | 让目前已签发的所有访问令牌失效 |
| `POST /debug/access-ttl` | `{ "seconds": 10 }` | 修改新签发令牌的有效期 |
| `POST /debug/reset` | – | 恢复默认配置并清除模拟过期 |

使用 **`user` / `user`** 登录 —— 其它值都会返回 `401`，这是观察 `AuthError` 分支最简单的方式。后端签发的是真实的 HMAC-SHA256 JWT，带刷新令牌轮换与重放检测，并记录每条请求日志。已开启 CORS，Flutter Web 构建可直接调用。

**2. 运行示例 App**

```bash
cd example
flutter run
```

- App **默认连接真实后端**；在卡片里关掉 **Live backend** 即可回退到离线假后端（`_DemoStrategy`）。
- 用 `user` / `user` 登录，再点击 **Call /me**，即可看到拦截器附加 `Authorization: Bearer …`，后端回显用户信息。
- 登录后 **Debug** 卡片提供 *Expire now*（随后 `Call /me` 会出现 `401`）与 *Expire in 10s*（缩短令牌有效期，下一次 `Call /me` 就会走透明续期）。
- 关掉后端再登录，会看到映射后的 `network_unreachable` 错误，而不是裸的 `DioException`。

> Android 模拟器请使用 `http://10.0.2.2:8080` 代替 `localhost`（见 `example/lib/main.dart` 的 `_baseUrl`）。

## API 参考

> **从 0.2.x 升级** —— `AuthState` 新增了两个子类：`Refreshing` 与 `LoggingOut`，
> 因此穷举 `switch` 必须处理它们。建议改用 `state.isAuthenticated` 与
> `state.isBusy`，状态继续演进也不会失效。

### `AuthManager`

| 成员 | 签名 | 说明 |
|------|------|------|
| 构造函数 | `AuthManager({required strategy, TokenStore? tokenStore, Duration? autoRefreshAhead, RefreshFailurePolicy? refreshFailurePolicy, DateTime Function()? clock})` | `tokenStore` 默认为 `InMemoryTokenStore`；`autoRefreshAhead` 开启主动续期；`clock` 覆盖时间源 |
| `current` | `AuthState get current` | 最新状态，始终可读 |
| `state` | `Stream<AuthState> get state` | 广播流，对新订阅者重放最新值 |
| `currentSession` | `AuthSession? get currentSession` | 在 `Authenticated` **与** `Refreshing` 期间可用 |
| `accessToken` | `String? get accessToken` | 可能已过期，请求请用 `validAccessToken` |
| `restore()` | `Future<void> restore({bool refreshIfExpired = true})` | 修复已过期的持久化会话，无法续期则丢弃 |
| `login()` | `Future<Authenticated> login(Credentials)` | 发出 `Authenticating → Authenticated`；失败发 `AuthError` **并重新抛出** |
| `register()` | `Future<Authenticated> register(RegistrationInput)` | 语义同 `login` |
| `loginWith()` | `Future<Authenticated> loginWith(Future<AuthSession> Function(AuthStrategy))` | 接纳任意自定义流程产生的会话 |
| `refresh()` | `Future<AuthSession>` | 发出 `Refreshing`；单飞；失败时按 `refreshFailurePolicy` 处理 |
| `validAccessToken()` | `Future<String?>` | 绝不返回过期令牌，必要时先续期 |
| `logout()` | `Future<void>` | 发出 `LoggingOut`、尽力调用后端、清空存储，落到 `Unauthenticated` |
| `dispose()` | `Future<void>` | 关闭状态流并取消主动刷新 |

### `AuthManagerGroup`（可选，多账号）

为每个账号协调一个 `AuthManager`。可选：不用它，`AuthManager` 就仍是单会话，行为完全不变。

| 成员 | 说明 |
|------|------|
| 构造函数 | `AuthManagerGroup({required strategyFactory, required storeFactory})` —— 两者都会收到账号 id；请为每个账号提供独立的 `TokenStore` |
| `forAccount(id)` | 惰性创建并缓存该账号的 `AuthManager` |
| `switchTo(id)` | 激活某个账号，分组的 `state` 随之切换 |
| `current` / `state` / `currentSession` / `accessToken` | 反映激活账号 |
| `restoreAll(ids, {activeId})` | 恢复所有账号，然后激活其中一个 |
| `remove(id)` | 登出并移除某个账号 |
| `disposeAll()` | 释放所有管理器 |

若只是需要「切换账号」，简单的登出再登录通常就够了 —— 参见
[多账号 cookbook](https://zero-labsco.github.io/zero_auth/Multi-Account)。

### `AuthState`（密封）

| 子类 | 负载 | 含义 |
|------|------|------|
| `Unauthenticated` | – | 无会话 |
| `Authenticating` | – | `login` / `register` / `loginWith` 进行中 |
| `Authenticated` | `AuthSession session` | 会话有效 |
| `Refreshing` | `AuthSession session` | 续期进行中，旧会话仍可用 |
| `LoggingOut` | `AuthSession session` | 登出进行中，该会话即将被丢弃 |
| `AuthError` | `AppException error` | 上一次操作失败 |

辅助属性：`isAuthenticated` 在 `Authenticated` **与** `Refreshing` 下为 `true`；
`isBusy` 覆盖 `Authenticating`、`Refreshing`、`LoggingOut`。

### `AuthSession`

| 成员 | 说明 |
|------|------|
| `accessToken`、`refreshToken`、`expiresAt`、`userId`、`displayName`、`claims` | 令牌、过期时间、身份与原始 claims |
| `isExpired` | 按系统时钟判断是否过期 |
| `isExpiredAt(DateTime)` | 按你自己的时钟判断 |
| `toJson()` / `AuthSession.fromJson()` | 持久化用，`null` 字段会被省略 |

### 边界与值对象

| 类型 | 职责 |
|------|------|
| `AuthStrategy` | 由你实现的后端边界：`login` / `register` / `logout` / `refresh` |
| `TokenStore` | 持久化边界：`save` / `load` / `clear`；内核自带 `InMemoryTokenStore` |
| `AuthTokenSource` | 供网络层使用的只读令牌来源，`AuthManager` 即实现它 |
| `Credentials`、`RegistrationInput`、`SessionHandle`、`RefreshToken` | 跨边界传递的值对象 |

### 错误

| 类型 | 职责 |
|------|------|
| `AppException` | 唯一的公共错误类型：`message` / `code` / `cause` |
| `AuthException` | 认证失败基类，持有 `AuthFail` |
| `InvalidCredentialsException` | 凭据被拒，重试同样失败 |
| `SessionExpiredException` | 授权已过期或被吊销，只能重新登录 |
| `NoActiveSessionException` | 需要活动会话的操作却没有会话 |
| `RefreshTokenMissingException` | 会话无刷新令牌却请求了刷新 |
| `UnexpectedAuthException` | 无法归类时的兜底类型 |
| `mapAuthFailure(Object)` | 按 `code` 把捕获的错误映射为最具体的子类 |
| `defaultRefreshFailurePolicy` | 不可恢复的失败登出，瞬时故障保留会话 |
| `Result<T>` | 可选的显式 `Ok` / `Err` 包装 |

## 架构

```
   登录/注册 ──► Authenticating ──► Authenticated
                                        │
                          刷新 ─────────┤
                                        ▼
                                    Refreshing
                                   │         │
                          续期成功 ─┘         └─── 失败
                              │                    │
                              ▼                    ▼
                  Authenticated（新令牌）       AuthError
                                                 │      │
                                  不可恢复 ──────┘      └── 瞬时故障
                                        │                     │
                                        ▼                     ▼
                                 Unauthenticated         Authenticated
                                                        （保留上一个会话）

   登出 ──► LoggingOut ──► Unauthenticated
   restore() ──► Authenticated；无持久化内容或无法续期时为 Unauthenticated
```

管理器不含 UI、后端或原生代码。通过 `AuthStrategy` 接入后端，通过 `TokenStore` 接入持久化；网络层只依赖 `AuthTokenSource`。

连续重复的状态会被抑制，因此监听器只会在真正变化时重建。

## 文档

本 README 是入口，更深入的内容在这两处：

- [使用与 API 指南](USAGE.md) —— 完整参考：全部边界、错误模型、生命周期最佳实践、常见坑与测试。
- [文档站](https://zero-labsco.github.io/zero_auth/) —— 专题页与 cookbook：[认证状态机](https://zero-labsco.github.io/zero_auth/Auth-State-Machine)、[后端策略](https://zero-labsco.github.io/zero_auth/Backend-Strategy)、[令牌存储](https://zero-labsco.github.io/zero_auth/Token-Store)、[网络集成](https://zero-labsco.github.io/zero_auth/Network-Integration)、[错误](https://zero-labsco.github.io/zero_auth/Errors)、[配置](https://zero-labsco.github.io/zero_auth/Configuration)、[会话持久化](https://zero-labsco.github.io/zero_auth/Persistence)、[第三方登录](https://zero-labsco.github.io/zero_auth/Third-Party-Login) 与 [多账号](https://zero-labsco.github.io/zero_auth/Multi-Account)。

## 贡献

欢迎贡献代码！提交 issue 或 pull request 前，请先阅读[贡献指南](CONTRIBUTING.md)。

- 🐛 [报告 Bug](https://github.com/zero-labsco/zero_auth/issues/new?template=bug_report.md)
- 💡 [功能建议](https://github.com/zero-labsco/zero_auth/issues/new?template=feature_request.md)
- 💬 [参与讨论](https://github.com/zero-labsco/zero_auth/discussions)

## 许可证

版权所有 (c) 2026 Zero Labs Co. (AmisKwok)。本项目采用 **Mozilla Public License 2.0（MPL-2.0）** 授权 — 详见 [LICENSE](LICENSE) 文件。版权声明与附加声明（免责、禁止背书）见 [NOTICE](NOTICE)。

- **允许商用**：可自由使用、修改与闭源分发。
- **修改了包？** 被修改的文件必须以 MPL-2.0 公开源码；你自己的 App **无需**开源。
- **未修改直接使用？** 无需公开任何源码。
- **禁止背书**：未经书面许可，不得以 "Zero Labs Co."、"zero_auth"、项目 Logo / 吉祥物形象及作者名义（AmisKwok）为衍生品背书、宣传或暗示官方赞助 / 关联。
- **免责声明**：版权方不对任何修改版或衍生版提供担保，也不承担相应责任；修改版必须明确标注已被修改。

本包按"原样"提供，不提供任何担保。作者不对修改版或衍生项目的功能、安全性及任何使用后果承担责任。
