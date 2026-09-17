# Zero Auth — Usage & API Guide

> English-primary, 中文辅助（EN-primary / ZH-secondary）。
> 本文件是 `README.md` 中「Usage / API Reference」章节的展开版：按**接入顺序**讲清每一步，并给出完整的 API 签名表。

---

## Table of Contents / 目录

- [1. What it is (and is not)](#1-what-it-is-and-is-not--它做什么不做什么)
- [2. Install](#2-install--安装)
- [3. Quick start](#3-quick-start--快速上手)
- [4. Core concepts](#4-core-concepts--核心概念)
- [5. Wire your backend — `AuthStrategy`](#5-wire-your-backend--authstrategy)
- [6. Persist the session — `TokenStore`](#6-persist-the-session--tokenstore)
- [7. Consume the state — UI & stream](#7-consume-the-state--ui--stream)
- [8. Tokens & network layer — `AuthTokenSource`](#8-tokens--network-layer--authtokensource)
- [9. Refresh & expiry](#9-refresh--expiry--刷新与过期)
- [10. Error model](#10-error-model--错误模型)
- [11. API reference](#11-api-reference--api-参考)
- [12. Lifecycle best practices](#12-lifecycle-best-practices--生命周期最佳实践)
- [13. Pitfalls](#13-pitfalls--常见坑)
- [14. Testing](#14-testing--测试)

---

## 1. What it is (and is not) / 它做什么、不做什么

`zero_auth` is a **pure-Dart, headless auth state machine**: it answers *"is the user logged in, who are they, and how did they log in / out / recover"*, and it owns the session lifecycle (restore → login → refresh → logout).
`zero_auth` 是一个**纯 Dart、无头（headless）的认证状态机**：负责回答「用户是否登录、是谁、如何登录 / 登出 / 恢复」，并托管会话生命周期。

| It does / 负责 | It does **not** do / **不**负责 |
|---|---|
| 状态机 `Unauthenticated → Authenticating → Authenticated → AuthError` | 不发 HTTP 请求（无内置 client、无 `dart:io`） |
| 会话模型 `AuthSession`（token / 过期 / 身份） | 不做持久化实现（只定义 `TokenStore` 接口） |
| 启动恢复 `restore()`、单飞刷新 `refresh()` | 不内置定时/自动刷新（见 [§9](#9-refresh--expiry--刷新与过期)） |
| 统一错误（`AppException` / `AuthException`） | 不提供 UI、路由、状态管理框架绑定 |
| 令牌出口 `AuthTokenSource`（给拦截器用） | 不解析 JWT、不校验签名 |

Two boundaries you must fill in / 你只需填两个边界：

```
your backend  ──▶  AuthStrategy   ──▶  AuthManager  ──▶  AuthState stream  ──▶  your UI
your storage  ──▶  TokenStore     ──▶               ──▶  accessToken       ──▶  your network layer
```

---

## 2. Install / 安装

```yaml
dependencies:
  zero_auth: ^0.1.0
```

```dart
import 'package:zero_auth/zero_auth.dart';   // 唯一公共入口，勿导入 lib/src/
```

Requirements / 要求：Dart `^3.4.0`（sealed class）。运行时只依赖 `meta`。

---

## 3. Quick start / 快速上手

A complete, runnable flow / 一段完整可运行的流程：

```dart
import 'package:zero_auth/zero_auth.dart';

Future<void> main() async {
  // 1) Create one manager per app (or per scope). 一个应用创建一个管理器实例。
  final auth = AuthManager(
    strategy: MyAuthStrategy(),      // your backend / 你的后端
    tokenStore: InMemoryTokenStore(),// default when omitted / 省略时默认
  );

  // 2) Subscribe before acting: the stream replays the current state.
  //    先订阅再操作：该流会对新订阅者重放最近状态。
  auth.state.listen((state) {
    switch (state) {
      case Unauthenticated():
        print('show login / 显示登录页');
      case Authenticating():
        print('show spinner / 显示加载');
      case Authenticated(:final session):
        print('hi ${session.displayName}, token=${session.accessToken}');
      case Refreshing(:final session):
        // Still signed in: only the token is being renewed.
        // 仍处于登录态：只是令牌在续期。
        print('renewing ${session.displayName} / 续期中');
      case LoggingOut():
        print('signing out / 登出中');
      case AuthError(:final error):
        print('failed: ${error.message} (${error.code})');
    }
  });

  // 3) Silent restore at startup. 启动时静默恢复。
  await auth.restore();

  // 4) Log in. Emits Authenticating → Authenticated, or AuthError + rethrow.
  //    登录：发 Authenticating → Authenticated；失败发 AuthError 并再次抛出。
  try {
    final authed = await auth.login(
      Credentials(username: 'me', password: '••••'),
    );
    print('session: ${authed.session.userId}');
  } on AuthException catch (e) {
    // The UI already got AuthError; catch here only if you must react in-line.
    // UI 已收到 AuthError；仅在需要就地响应时才 catch。
    print(e.message);
  }

  // 5) Read the token anywhere (network layer, headers…). 任意处读取令牌。
  print(auth.accessToken);

  // 6) Log out (best-effort backend call, always clears locally). 登出。
  await auth.logout();

  // 7) Release the stream controller when the scope dies. 销毁时释放。
  await auth.dispose();
}
```

---

## 4. Core concepts / 核心概念

### 4.1 State machine / 状态机

```
   login()/register()            success                  refresh() ok
 ┌──────────────────┐   ┌──────────────────┐   ┌────────────────────┐
 │ Unauthenticated  │──▶│  Authenticating  │──▶│    Authenticated   │
 └──────────────────┘   └──────────────────┘   └────────────────────┘
          ▲                       │                    │      │
          │                       │ failure            │      │
          │                       ▼                    │      ▼
          │              ┌──────────────────┐          │   refresh() fails
          │              │    AuthError     │          │   (state unchanged,
          │              └──────────────────┘          │    only the Future
          │                                            │    completes with an
          └────────────── logout() ◀───────────────────┘    error)
```

- `AuthError` is **terminal**: the manager does not auto-return to `Unauthenticated`. Call `logout()` or start a new `login()`.
  `AuthError` 是**终结态**：不会自动回到 `Unauthenticated`，请调用 `logout()` 或重新 `login()`。
- `refresh()` failures do **not** emit `AuthError` — only the returned `Future` errors. Decide yourself whether to force a logout.
  `refresh()` 失败**不会**发 `AuthError`，只让返回的 `Future` 报错；是否强制登出由你决定。

### 4.2 The two boundaries / 两个边界

| Boundary | You implement | Called by the manager when |
|---|---|---|
| `AuthStrategy` | `login` `register` `logout` `refresh` | user acts / token needs renewal |
| `TokenStore` | `save` `load` `clear` | after login/register/refresh / on `restore()` / on `logout()` |

---

## 5. Wire your backend / 接入后端 — `AuthStrategy`

### 5.1 The contract / 接口

```dart
abstract class AuthStrategy {
  Future<AuthSession> login(Credentials credentials);
  Future<AuthSession> register(RegistrationInput input);
  Future<void> logout(SessionHandle handle);
  Future<AuthSession> refresh(RefreshToken token);
}
```

Inputs / 入参：

| Type | Fields |
|---|---|
| `Credentials` | `username`, `password` |
| `RegistrationInput` | `username`, `password`, `displayName?`, `email?` |
| `SessionHandle` | `userId` |
| `RefreshToken` | `value` |

Rules / 规则：
- Return a **fully-formed `AuthSession`**; the manager persists it as-is.
  返回**完整的 `AuthSession`**，管理器会原样持久化。
- Throw anything you like — the manager wraps non-`AppException` errors into `AuthException('Unexpected auth failure', cause: e)`. **Prefer throwing `AuthException` yourself** with a stable `code`, so the UI can branch.
  抛什么都行，但非 `AppException` 会被包成 `AuthException('Unexpected auth failure', cause: e)`。**建议自己抛 `AuthException`** 并带上稳定的 `code`。
- `logout()` failures are swallowed by the manager (best-effort): local logout always succeeds.
  `logout()` 的失败会被管理器吞掉（尽力而为）：本地登出必定完成。

### 5.2 A realistic HTTP strategy / 一个真实的 HTTP 实现

```dart
import 'package:dio/dio.dart';
import 'package:zero_auth/zero_auth.dart';

final class HttpAuthStrategy implements AuthStrategy {
  HttpAuthStrategy(this.baseUrl);

  final String baseUrl;
  final Dio _dio = Dio();

  AuthSession _toSession(Map<String, dynamic> data) => AuthSession(
        accessToken: data['accessToken'] as String,
        refreshToken: RefreshToken(data['refreshToken'] as String),
        expiresAt: data['expiresIn'] != null
            ? DateTime.now().add(Duration(seconds: data['expiresIn'] as int))
            : null,
        userId: data['userId'] as String?,
        displayName: data['displayName'] as String?,
        claims: data, // 原始 claims 可选保留
      );

  @override
  Future<AuthSession> login(Credentials c) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$baseUrl/login',
        data: {'username': c.username, 'password': c.password},
      );
      return _toSession(res.data!);
    } catch (e) {
      throw _map(e);
    }
  }

  @override
  Future<AuthSession> register(RegistrationInput i) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$baseUrl/register',
        data: {
          'username': i.username,
          'password': i.password,
          if (i.email != null) 'email': i.email,
          if (i.displayName != null) 'displayName': i.displayName,
        },
      );
      return _toSession(res.data!);
    } catch (e) {
      throw _map(e);
    }
  }

  @override
  Future<void> logout(SessionHandle h) async {
    try {
      await _dio.post('$baseUrl/logout', data: {'userId': h.userId});
    } catch (e) {
      throw _map(e);
    }
  }

  @override
  Future<AuthSession> refresh(RefreshToken t) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$baseUrl/refresh',
        data: {'refreshToken': t.value},
      );
      return _toSession(res.data!);
    } catch (e) {
      throw _map(e);
    }
  }

  /// Map transport/HTTP failures into the shared error vocabulary.
  /// 把传输 / HTTP 失败映射为统一错误词汇。
  AuthException _map(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] is String) {
        return AuthException(
          data['message'] as String,
          code: (data['code'] as String?) ?? 'http_error',
          cause: e,
        );
      }
      return AuthException(
        e.message ?? 'Request failed',
        code: 'network_unreachable',
        cause: e,
      );
    }
    return AuthException('Unexpected auth failure', cause: e);
  }
}
```

> The example app ships the same pattern (`example/lib/main.dart`, `_HttpAuthStrategy`) plus an offline double (`_DemoStrategy`) for tests and demos.
> 示例应用中包含同样写法，另有一个离线替身 `_DemoStrategy` 便于测试演示。

---

## 6. Persist the session / 持久化 — `TokenStore`

```dart
abstract class TokenStore {
  Future<void> save(AuthSession session);
  Future<AuthSession?> load();
  Future<void> clear();
}
```

- Default: `InMemoryTokenStore` — **not durable** across restarts (tests / demos only).
  默认 `InMemoryTokenStore`，**重启即失**，仅用于测试/演示。
- Production: implement `TokenStore` over `flutter_secure_storage` / `shared_preferences` / Keychain / file. A copy-paste reference lives in `example/lib/secure_token_store.dart`.
  生产环境请基于 `flutter_secure_storage` / Keychain / 文件实现；参考实现见 `example/lib/secure_token_store.dart`。

```dart
final auth = AuthManager(
  strategy: HttpAuthStrategy('https://api.example.com'),
  tokenStore: SecureTokenStore(),   // survive app restarts
);
```

Minimal file-based sketch / 最小自定义示例：

```dart
final class PrefsTokenStore implements TokenStore {
  PrefsTokenStore(this._read, this._write, this._delete);

  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String value) _write;
  final Future<void> Function(String key) _delete;

  @override
  Future<void> save(AuthSession s) async {
    await _write('access', s.accessToken);
    if (s.refreshToken != null) await _write('refresh', s.refreshToken!.value);
    if (s.expiresAt != null) {
      await _write('expiry', s.expiresAt!.toIso8601String());
    }
    if (s.userId != null) await _write('uid', s.userId!);
  }

  @override
  Future<AuthSession?> load() async {
    final access = await _read('access');
    if (access == null) return null;
    final refresh = await _read('refresh');
    final expiry = await _read('expiry');
    return AuthSession(
      accessToken: access,
      refreshToken: refresh == null ? null : RefreshToken(refresh),
      expiresAt: expiry == null ? null : DateTime.tryParse(expiry),
      userId: await _read('uid'),
    );
  }

  @override
  Future<void> clear() async {
    for (final k in ['access', 'refresh', 'expiry', 'uid']) {
      await _delete(k);
    }
  }
}
```

> `load()` returning `null` simply means "not signed in" — `restore()` then emits `Unauthenticated`.
> `load()` 返回 `null` 即代表未登录，`restore()` 会发出 `Unauthenticated`。

---

## 7. Consume the state / 消费状态 — UI & stream

`AuthManager.state` is a broadcast stream that **replays the last value** to every new listener, so UI code can subscribe at any time.
`AuthManager.state` 是**对新订阅者重放最近值**的广播流，UI 可随时订阅。

### 7.1 Flutter: `StreamBuilder`

```dart
StreamBuilder<AuthState>(
  initialData: auth.current,
  stream: auth.state,
  builder: (context, snap) => switch (snap.data) {
    Unauthenticated() => const LoginPage(),
    Authenticating() || LoggingOut() =>
      const Center(child: CircularProgressIndicator()),
    // Keep the user signed in while the token renews, otherwise a routine
    // refresh would flash the login page (or a blank "_" fallback).
    // 令牌续期期间保持登录态，否则一次例行刷新会闪回登录页（或落到 `_` 兜底分支）。
    Authenticated(:final session) || Refreshing(:final session) =>
      HomePage(session: session),
    AuthError(:final error) => ErrorView(message: error.message),
    _ => const SizedBox.shrink(),
  },
);
```

### 7.2 Bridge to any state-management / 对接任意状态管理

```dart
// Riverpod
final authManagerProvider = Provider<AuthManager>((ref) {
  final auth = AuthManager(strategy: HttpAuthStrategy(baseUrl));
  ref.onDispose(auth.dispose);
  unawaited(auth.restore());
  return auth;
});

final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(authManagerProvider).state,
);

// ChangeNotifier / ValueListenable
final class AuthController {
  AuthController(this._auth) {
    _sub = _auth.state.listen((s) {
      value = s;
      notifyListeners();
    });
  }
  // …expose login()/logout()/refresh() that call through to _auth…
}
```

The manager is framework-agnostic: anything that can listen to a `Stream<AuthState>` works.
管理器与框架无关：任何能监听 `Stream<AuthState>` 的方案都可以。

---

## 8. Tokens & network layer / 令牌与网络层 — `AuthTokenSource`

```dart
abstract class AuthTokenSource {
  String? get accessToken;   // null when unauthenticated
}
```

`AuthManager` **implements** `AuthTokenSource`, so hand the manager to your interceptor and it always reads the live token (no copying, no stale closures).
`AuthManager` **本身即** `AuthTokenSource`，把管理器交给拦截器即可，永远读到最新令牌。

### 8.1 Attach the bearer header / 附加 Bearer 头

```dart
final class AuthInterceptor extends Interceptor {
  AuthInterceptor(this.source);
  final AuthTokenSource source;

  @override
  void onRequest(RequestOptions o, RequestInterceptorHandler h) {
    final token = source.accessToken;
    if (token != null) o.headers['Authorization'] = 'Bearer $token';
    h.next(o);
  }
}

final dio = Dio()..interceptors.add(AuthInterceptor(auth));
```

### 8.2 Auto-refresh on 401 (single-flight safe) / 401 自动刷新并重试

```dart
final class RefreshInterceptor extends QueuedInterceptor {
  RefreshInterceptor(this._auth);
  final AuthManager _auth;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode != 401) return handler.next(err);

    try {
      final session = await _auth.refresh();   // concurrent callers share one call
      final token = session.accessToken;
      err.requestOptions.headers['Authorization'] = 'Bearer $token';
      final res = await Dio().fetch(err.requestOptions);
      handler.resolve(res);
    } on AuthException {
      await _auth.logout();                    // refresh token dead → force sign-out
      handler.next(err);
    }
  }
}
```

> Because `refresh()` is single-flight, a burst of parallel 401s triggers **one** backend call and all retry with the same new token.
> 因为 `refresh()` 是单飞的，并发的多个 401 只会触发**一次**后端调用，并共用同一个新令牌重试。

---

## 9. Refresh & expiry / 刷新与过期

```dart
Future<AuthSession> refresh();
```

| Behaviour / 行为 | Detail / 说明 |
|---|---|
| Single-flight / 单飞 | Concurrent callers share one `Future`; the guard resets in `finally`. 并发调用共享同一个 `Future`，守卫在 `finally` 中释放。 |
| Preconditions | Needs an active session **and** a non-null `refreshToken`; otherwise throws `NoActiveSessionException` / `RefreshTokenMissingException`. 需要活动会话且 `refreshToken` 非空，否则抛出这两个异常。 |
| In flight | Emits `Refreshing(session)`; the previous session stays usable meanwhile / 期间发出 `Refreshing(session)`，旧会话仍可用。 |
| On success | Persists via `TokenStore.save`, emits `Authenticated(newSession)`. 经 `TokenStore.save` 持久化并发出 `Authenticated(newSession)`。 |
| On failure | Emits `AuthError`, then either `Unauthenticated` (unrecoverable) or back to the previous `Authenticated` (transient) per `refreshFailurePolicy`; the returned `Future` also completes with the typed error. 先发 `AuthError`，再按策略转为 `Unauthenticated`（不可恢复）或回到上一个 `Authenticated`（瞬时）；返回的 `Future` 同时以类型化错误完成。 |
| Expiry | `AuthSession.isExpired` is `false` when `expiresAt == null` (expiry unknown ⇒ assume valid). Use `isExpiredAt(now)` to evaluate against your own clock. |

> **0.3.0 note / 说明：** passing `autoRefreshAhead` to `AuthManager` lets the core
> schedule the renewal for you (still single-flight, failures handled internally).
> Everything below still applies if you prefer to drive refreshes yourself.

> **0.3.0 说明：** 给 `AuthManager` 传入 `autoRefreshAhead` 即可让内核替你排程续期
> （依然单飞，失败在内部处理）。如果你偏好自己驱动刷新，下面的内容仍然适用。

No built-in timer unless asked / **默认不内置定时器**：`zero_auth` 默认不自动排程刷新（除非传入 `autoRefreshAhead`）。Choose one / 任选其一：

```dart
// A) Refresh lazily, right before a call that needs a fresh token / 惰性刷新
if (auth.currentSession?.isExpired ?? false) {
  await auth.refresh();
}

// B) Refresh near expiry / 提前刷新（例如剩余 < 60s）
final s = auth.currentSession;
if (s?.expiresAt != null &&
    s!.expiresAt!.difference(DateTime.now()) < const Duration(seconds: 60)) {
  unawaited(auth.refresh());
}

// C) Schedule your own timer / 自行定时（Timer.periodic + refresh()）
```

---

## 10. Error model / 错误模型

```
Exception (dart:core)
└── AppException            { message, code?, cause? }   // 唯一公共错误类型
    └── AuthException       { fail: AuthFail }           // zero_auth 的认证错误

AuthFail  { message, code?, cause? }   // 领域失败，映射为 AuthException 前的载体
Result<T> : Ok<T>(value) | Err<T>(error)
```

Every public failure is an `AppException` — raw `Exception`s never cross the surface.
对外失败**一律**是 `AppException`，裸 `Exception` 不会越界。

### 10.1 Two channels for one failure / 一次失败，两个通道

```dart
try {
  await auth.login(Credentials(username: 'a', password: 'wrong'));
} on AuthException catch (e) {
  // 1) rethrown here …
}
// 2) … and already emitted as AuthError on auth.state
```

This is deliberate: the stream drives the UI, the rethrow lets imperative code react. Pick one and be consistent — the example app swallows the rethrow and lets `AuthError` drive everything.
这是有意为之：流驱动 UI，rethrow 便于命令式代码响应。示例应用选择吞掉 rethrow，完全由 `AuthError` 驱动。

```dart
Future<void> invoke(Future<dynamic> Function() action) async {
  try {
    await action();
  } catch (_) {} // state stream already reported it
}
```

### 10.2 Suggested `code` values / 建议的 code 取值

`invalid_credentials` · `invalid_refresh_token` · `network_unreachable` · `http_error` · `unauthorized` · `unknown`

```dart
throw AuthException('Wrong password', code: 'invalid_credentials');
```

### 10.3 `Result<T>` (optional) / 可选的显式结果

```dart
Result<AuthSession> trySession() {
  final s = auth.currentSession;
  return s == null ? Err(AuthException('No session')) : Ok(s);
}

final r = trySession();
if (r.isOk) print(r.getOrThrow.userId);   // or r.map((s) => s.userId)
```

---

## 11. API reference / API 参考

### 11.1 `AuthManager`

```dart
final class AuthManager implements AuthTokenSource {
  AuthManager({required AuthStrategy strategy, TokenStore? tokenStore});
}
```

| Member | Signature | Notes |
|---|---|---|
| `strategy` | `final AuthStrategy` | Your backend boundary / 后端边界 |
| `tokenStore` | `final TokenStore` | Defaults to `InMemoryTokenStore` |
| `current` | `AuthState get current` | Current state, always available / 当前状态，始终可读 |
| `state` | `Stream<AuthState> get state` | Broadcast, replays last value / 广播且重放最近值 |
| `autoRefreshAhead` | `Duration?` | Proactive renewal lead time; `null` disables it / 主动续期提前量，`null` 为关闭 |
| `refreshFailurePolicy` | `RefreshFailurePolicy` | Whether a failed refresh signs out / 刷新失败是否登出 |
| `clock` | `DateTime Function()` | Time source; defaults to the system clock / 时间源，默认系统时钟 |
| `currentSession` | `AuthSession? get currentSession` | `null` unless `Authenticated` / `Refreshing` |
| `accessToken` | `String? get accessToken` | From `AuthTokenSource`; may already be expired — see `validAccessToken` / 可能已过期，见 `validAccessToken` |
| `restore()` | `Future<void> restore({bool refreshIfExpired = true})` | Loads from `TokenStore`; an expired session is refreshed first, or dropped when it cannot renew / 载入持久化会话；过期会话先续期，无法续期则丢弃 |
| `login()` | `Future<Authenticated> login(Credentials)` | Emits `Authenticating → Authenticated`; on failure emits `AuthError` **and rethrows** |
| `register()` | `Future<Authenticated> register(RegistrationInput)` | Same semantics as `login` |
| `loginWith()` | `Future<Authenticated> loginWith(Future<AuthSession> Function(AuthStrategy))` | Adopts a session from any flow (OAuth, magic link, passkey) / 接纳任意流程的会话 |
| `logout()` | `Future<void>` | Emits `LoggingOut`, best-effort `strategy.logout`, then `clear()`, then `Unauthenticated` |
| `refresh()` | `Future<AuthSession>` | Emits `Refreshing`; single-flight; on failure applies `refreshFailurePolicy` / 发出 `Refreshing`；单飞；失败时按策略处理 |
| `validAccessToken()` | `Future<String?>` | Never returns an expired token; refreshes first when needed / 绝不返回过期令牌，必要时先续期 |
| `dispose()` | `Future<void>` | Closes the internal stream controller and cancels proactive refresh |

### 11.2 `AuthState` (sealed)

| Subtype | Payload | Meaning |
|---|---|---|
| `Unauthenticated` | – | No session |
| `Authenticating` | – | login / register in flight |
| `Authenticated` | `AuthSession session` | Session active |
| `Refreshing` | `AuthSession session` | Renewal in flight; the previous session stays usable |
| `LoggingOut` | `AuthSession session` | Logout in flight; that session is being discarded |
| `AuthError` | `AppException error` | Terminal failure |

`bool get isAuthenticated` — `true` for `Authenticated` **and** `Refreshing`, so a
token renewal never unmounts signed-in UI. `bool get isBusy` covers
`Authenticating`, `Refreshing` and `LoggingOut`.

`isAuthenticated` 在 `Authenticated` 与 `Refreshing` 下均为 `true`，令牌续期不会卸载
已登录界面；`isBusy` 覆盖 `Authenticating`、`Refreshing`、`LoggingOut`。

Prefer those two getters over `state is Authenticated` and over exhaustive
`switch` when you do not need per-case payloads — they keep compiling as states
evolve. Exhaustive `switch` is still enforced by the compiler; note that `0.3.0`
added two subtypes, so existing switches may need the new cases.

不需要按 case 取负载时，优先使用这两个属性而不是 `state is Authenticated` 或穷举
`switch`，这样状态演进也不会编译失败。穷举 `switch` 依然由编译器保证；注意 `0.3.0`
新增了两个子类，已有 switch 可能需要补上新分支。

### 11.3 `AuthSession`

```dart
const AuthSession({
  required String accessToken,
  RefreshToken? refreshToken,
  DateTime? expiresAt,
  String? userId,
  String? displayName,
  Map<String, Object?>? claims,
});
```

| Member | Type | Notes |
|---|---|---|
| `accessToken` | `String` | Bearer value |
| `refreshToken` | `RefreshToken?` | `RefreshToken.value` holds the raw string |
| `expiresAt` | `DateTime?` | `null` ⇒ treated as valid |
| `userId` / `displayName` | `String?` | Identity for UI / backend calls |
| `claims` | `Map<String, Object?>?` | Raw claims, untouched |
| `isExpired` | `bool` | `false` when `expiresAt == null` |

Value equality on `accessToken`, `refreshToken`, `expiresAt`, `userId`, `displayName`.

### 11.4 `AuthStrategy`

```dart
Future<AuthSession> login(Credentials credentials);
Future<AuthSession> register(RegistrationInput input);
Future<void> logout(SessionHandle handle);
Future<AuthSession> refresh(RefreshToken token);
```

### 11.5 `TokenStore`

```dart
Future<void> save(AuthSession session);
Future<AuthSession?> load();
Future<void> clear();
```

Ships `InMemoryTokenStore` (non-durable).

### 11.6 `AuthTokenSource`

```dart
String? get accessToken;
```

### 11.7 Value objects / 值对象

| Type | Constructor |
|---|---|
| `Credentials` | `Credentials({required String username, required String password})` |
| `RegistrationInput` | `RegistrationInput({required String username, required String password, String? displayName, String? email})` |
| `SessionHandle` | `SessionHandle({required String userId})` |
| `RefreshToken` | `RefreshToken(String value)` |

### 11.8 Errors / 错误

| Type | Members |
|---|---|
| `AppException` (abstract) | `String message`, `String? code`, `Object? cause`, `toString()` → `AppException(code): message` |
| `AuthException extends AppException` | `AuthFail fail`；`AuthException(String message, {String? code, Object? cause})`；`AuthException.fromFail(AuthFail)` |
| `AuthFail` | `String message`, `String? code`, `Object? cause` |
| `Result<T>` (sealed) | `bool isOk`, `bool isErr`, `T getOrThrow`, `Result<R> map<R>(R Function(T))` |
| `Ok<T>` / `Err<T>` | `T value` / `Object error` |

---

## 12. Lifecycle best practices / 生命周期最佳实践

1. **One manager per app scope.** Create it above the widget tree (or in DI), not inside `build()`.
   每个作用域一个管理器；放在 widget 树之上或 DI 容器里，别在 `build()` 中创建。
2. **Subscribe first, then `restore()`** so no state is missed.
   先订阅、再 `restore()`，避免丢状态。
3. **`await auth.restore()` once at startup**, before routing decisions.
   启动阶段在路由判断之前 `await auth.restore()` 一次。
4. **`await auth.dispose()`** when the scope dies (app teardown, hot-recreate, test `tearDown`).
   作用域销毁时 `dispose()`；`dispose()` 后再调用 `login()` 不会再发出事件。
5. **Keep the strategy stateless w.r.t. tokens** — never cache the token in the strategy; read `auth.accessToken`.
   strategy 内不要缓存令牌，始终读 `auth.accessToken`。
6. **Force logout after an unrecoverable refresh failure** (`invalid_refresh_token`).
   刷新令牌失效后强制登出。
7. **Never import `lib/src/`** — only `package:zero_auth/zero_auth.dart`.
   只导入公共 barrel。

---

## 13. Pitfalls / 常见坑

| Symptom / 现象 | Cause / 原因 | Fix / 处理 |
|---|---|---|
| `AuthException: Unexpected auth failure` | Strategy threw a non-`AppException` (e.g. raw `DioException`) | Map errors in your strategy; throw `AuthException` with a `code` |
| UI stuck on `AuthError` | It is a terminal state | Call `logout()` or start a new `login()` |
| `login()` throws even though UI shows the error | By design: emit **and** rethrow | Swallow it, or handle once — not both |
| `refresh()` throws immediately | No session, or `refreshToken == null` | Check `currentSession?.refreshToken`; re-login |
| Session lost after restart | Using `InMemoryTokenStore` | Inject a durable `TokenStore` |
| Token never renewed automatically | No built-in timer | Refresh lazily / near expiry / with your own timer ([§9](#9-refresh--expiry--刷新与过期)) |
| Duplicate refresh calls | Bypassing `refresh()` (e.g. calling strategy directly) | Always go through `AuthManager.refresh()` |
| `isExpired` always `false` | `expiresAt` was never set | Populate `expiresAt` when building `AuthSession` |

---

## 14. Testing / 测试

Swap in a fake `AuthStrategy` — no mocks package required:
用假的 `AuthStrategy` 即可，无需 mock 框架：

```dart
class FakeStrategy implements AuthStrategy {
  FakeStrategy({this.failLogin = false});
  final bool failLogin;

  @override
  Future<AuthSession> login(Credentials c) async {
    if (failLogin) throw AuthException('nope', code: 'invalid_credentials');
    return const AuthSession(
      accessToken: 'a',
      refreshToken: RefreshToken('r'),
      userId: 'u1',
      displayName: 'User One',
    );
  }

  @override
  Future<AuthSession> register(RegistrationInput i) =>
      login(Credentials(username: i.username, password: i.password));

  @override
  Future<void> logout(SessionHandle h) async {}

  @override
  Future<AuthSession> refresh(RefreshToken t) async => const AuthSession(
        accessToken: 'a2',
        refreshToken: RefreshToken('r2'),
        userId: 'u1',
      );
}

test('login emits Authenticated and persists', () async {
  final auth = AuthManager(strategy: FakeStrategy());
  addTearDown(auth.dispose);

  await auth.login(Credentials(username: 'a', password: 'b'));

  expect(auth.current, isA<Authenticated>());
  expect(auth.accessToken, 'a');
  expect((await auth.tokenStore.load())?.accessToken, 'a');
});
```

---

## See also / 相关

- `README.md` / `README_zh.md` — overview, install, demo backend endpoints.
- `example/lib/main.dart` — full Flutter app (real backend + offline double).
- `example/lib/dio_interceptor.dart`, `example/lib/secure_token_store.dart` — copy-paste integrations.
- `server/` — zero-dependency demo backend (`dart run bin/server.dart`).
