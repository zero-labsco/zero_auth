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
  zero_auth: ^1.1.0
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
| `SessionHandle` | `userId`, `refreshToken?` |
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
>
> **Prefer `AuthSession.tryFromJson()` in `load()`.** `fromJson()` throws a
> `FormatException` / `TypeError` on malformed data, which a schema change or a
> partial write can easily produce; `tryFromJson()` returns `null` instead, and
> `null` already means "not signed in".
> **`load()` 里请优先用 `AuthSession.tryFromJson()`。** `fromJson()` 遇到畸形数据会抛
> `FormatException` / `TypeError`，而 schema 变更或写入中断很容易造成畸形数据；
> `tryFromJson()` 则返回 `null`，而 `null` 本来就代表「未登录」。

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
  String? get accessToken;                                  // may be expired / 可能已过期
  Future<String?> validAccessToken({Duration? leeway});     // renewed first / 先续期
}
```

`AuthManager` **implements** `AuthTokenSource`, so hand the manager to your interceptor and it always reads the live token (no copying, no stale closures).
`AuthManager` **本身即** `AuthTokenSource`，把管理器交给拦截器即可，永远读到最新令牌。

> **1.0 note / 说明:** `validAccessToken()` is new on the interface. If you
> `implements AuthTokenSource` yourself, add one line:
> `@override Future<String?> validAccessToken({Duration? leeway}) async => accessToken;`.
> 若你自己 `implements AuthTokenSource`，请补一行（同上）。

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

That synchronous version attaches whatever the session currently holds, which may
already be expired. When the token actually reaches a server, read
`validAccessToken()` instead — it renews first (reusing the single-flight refresh):
同步版本附加的是会话当前持有的令牌，它可能已经过期。令牌真要发到服务端时，请改用
`validAccessToken()` —— 它会先续期（复用单飞刷新）：

```dart
final class RefreshingAuthInterceptor extends QueuedInterceptor {
  RefreshingAuthInterceptor(this.source);
  final AuthTokenSource source;

  @override
  void onRequest(RequestOptions o, RequestInterceptorHandler h) async {
    final token = await source.validAccessToken();
    if (token != null) o.headers['Authorization'] = 'Bearer $token';
    h.next(o);
  }
}
```

Both live in `example/lib/dio_interceptor.dart` (together with an
`AuthRetryInterceptor` that replays a request once after a 401).
两者都在 `example/lib/dio_interceptor.dart` 中（另有一个在 401 后重放一次请求的
`AuthRetryInterceptor`）。

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
| Single-flight / 单飞 | Concurrent callers share one `Future`, **but only within the same epoch**: a call started before the session was replaced (login / `updateSession`) is not joined, so nobody receives a stale session. 并发调用共享同一个 `Future`，**但仅限同一 epoch 内**：会话被替换（登录 / `updateSession`）之前启动的那次不会被共享，因此没人会拿到过期会话。 |
| Preconditions | Needs an active session **and** a non-null `refreshToken`; otherwise throws `NoActiveSessionException` / `RefreshTokenMissingException`. 需要活动会话且 `refreshToken` 非空，否则抛出这两个异常。 |
| In flight | Emits `Refreshing(session)`; the previous session stays usable meanwhile / 期间发出 `Refreshing(session)`，旧会话仍可用。 |
| On success | Persists via `TokenStore.save`, emits `Authenticated(newSession)`. Identity fields (`userId` / `displayName` / `claims`) carry over when the backend returned tokens only — pass `preserveSessionDetails: false` to opt out. 经 `TokenStore.save` 持久化并发出 `Authenticated(newSession)`；后端只返回令牌时身份字段会被保留，传 `preserveSessionDetails: false` 可关闭。 |
| On failure | Emits `AuthError`, then either `Unauthenticated` (unrecoverable) or back to the previous `Authenticated` (transient) per `refreshFailurePolicy`; the returned `Future` also completes with the typed error. 先发 `AuthError`，再按策略转为 `Unauthenticated`（不可恢复）或回到上一个 `Authenticated`（瞬时）；返回的 `Future` 同时以类型化错误完成。 |
| Expiry | `AuthSession.isExpired` is `false` when `expiresAt == null` (expiry unknown ⇒ assume valid). Use `isExpiredAt(now)` to evaluate against your own clock. |
| Clock skew / 时钟偏移 | `clockSkew` (default 30s) makes the manager treat a token as expired that much earlier, so a device clock running ahead cannot hand out a token that dies in flight. `validAccessToken(leeway:)` overrides it per call; `clockSkew: Duration.zero` restores the strict behaviour. `clockSkew`（默认 30 秒）让管理器提前这么多把令牌视为过期，设备时钟偏快时不会发出途中失效的令牌；`validAccessToken(leeway:)` 可按单次调用覆盖，`clockSkew: Duration.zero` 恢复严格判定。 |
| Proactive / 主动续期 | `autoRefreshAhead` schedules the renewal before expiry; a failure is re-armed with a linear backoff up to `autoRefreshMaxRetries` (default 3), and an already-due renewal waits at least `autoRefreshMinInterval` (default 5s) so a backend issuing very short-lived tokens cannot cause a tight loop. `autoRefreshAhead` 在过期前排程续期；失败按线性退避重试，上限 `autoRefreshMaxRetries`（默认 3），已到期的续期至少等待 `autoRefreshMinInterval`（默认 5 秒），避免后端发放极短寿命令牌时形成紧密循环。 |
| `restore()` | An expired persisted session is renewed first. If that renewal fails **transiently** the session is kept (the next `validAccessToken()` retries); only a terminal failure clears the store. 过期的持久化会话会先续期；续期**瞬时**失败时保留会话（下次 `validAccessToken()` 会重试），只有终局失败才清空存储。 |

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

Codes your strategy should throw / 策略建议抛出的 code：

`invalid_credentials` · `invalid_grant` · `invalid_refresh_token` ·
`token_expired` · `session_expired` · `network_unreachable` · `http_error` ·
`unauthorized` · `unknown`

```dart
throw AuthException('Wrong password', code: 'invalid_credentials');
```

You can also throw the bare domain type — `mapAuthFailure` reads its `code` just
the same / 也可以直接抛出裸的领域类型，`mapAuthFailure` 一样会读取它的 `code`：

```dart
throw const AuthFail('Wrong password', code: 'invalid_credentials');
```

Codes raised by the manager itself / 管理器自身产生的 code：

| Code | Meaning |
|---|---|
| `invalid_credentials` | Mapped from your strategy / 由你的策略映射而来 |
| `session_expired`, `invalid_grant`, `invalid_refresh_token`, `token_expired` | `SessionExpiredException` — the grant is dead / 授权失效 |
| `no_active_session` | An operation needed an active session / 需要活动会话却没有 |
| `refresh_token_missing` | Refresh requested without a refresh token / 无刷新令牌却请求刷新 |
| `auth_flow_in_progress` | Another login / register / loginWith is running / 已有登录流程在执行 |
| `manager_disposed` | Operation called after `dispose()` / 释放后又调用操作 |
| `unexpected_auth_failure` | Fallback for anything unclassifiable / 无法归类时的兜底 |

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
  AuthManager({
    required AuthStrategy strategy,
    TokenStore? tokenStore,
    Duration? autoRefreshAhead,
    Duration? autoRefreshRetryDelay,
    int? autoRefreshMaxRetries,
    Duration? autoRefreshMinInterval,
    RefreshFailurePolicy? refreshFailurePolicy,
    DateTime Function()? clock,
    Duration? clockSkew,               // default 30s / 默认 30 秒
    double clockSkewFraction = 0.25,   // caps clockSkew for short-lived tokens / 为短寿命令牌设置容差上限
    bool preserveSessionDetails = true,
    void Function(AuthState state)? onStateChanged,
    void Function(Object error, StackTrace stack)? onObserverError,
  });
}
```

Constructor-only knobs — they shape behaviour but are **not** readable members
(`AuthManager` keeps them private), so do not expect `auth.autoRefreshAhead`:

仅存在于构造函数的调参项 —— 它们决定行为，但**不是**可读成员（`AuthManager` 将其私有化），
因此不要去读 `auth.autoRefreshAhead`：

| Constructor parameter / 构造参数 | Type | Notes |
|---|---|---|
| `autoRefreshAhead` | `Duration?` | Proactive renewal lead time; `null` disables it / 主动续期提前量，`null` 为关闭 |
| `autoRefreshRetryDelay` | `Duration?` | Re-arms a proactive renewal that failed (default 30s), while a session still exists / 主动续期失败后重新排程（默认 30 秒） |
| `autoRefreshMaxRetries` | `int?` | How many failed proactive renewals to retry (default 3) / 主动续期最多重试几次（默认 3） |
| `autoRefreshMinInterval` | `Duration?` | Floor for an already-due proactive renewal (default 5s) / 「已到期」主动续期的最小等待（默认 5 秒） |

Readable members / 可读成员：

| Member | Signature | Notes |
|---|---|---|
| `strategy` | `final AuthStrategy` | Your backend boundary / 后端边界 |
| `tokenStore` | `final TokenStore` | Defaults to `InMemoryTokenStore` |
| `clockSkew` | `final Duration` | How much earlier a token counts as expired (default 30s) / 提前多久把令牌视为过期（默认 30 秒） |
| `clockSkewFraction` | `final double` | Caps `clockSkew` at this fraction of the observed token lifetime (default `0.25`); `double.infinity` disables the cap / 把 `clockSkew` 钳制为观测到的令牌寿命的这个比例（默认 `0.25`）；`double.infinity` 关闭该上限 |
| `preserveSessionDetails` | `final bool` | Carry identity fields across a renewal that returns tokens only (default `true`) / 只返回令牌的续期是否保留身份字段（默认 `true`） |
| `onStateChanged` | `final void Function(AuthState)?` | Called for every emission; handy for logging or analytics without subscribing / 每次发出状态时调用，便于日志或埋点 |
| `onObserverError` | `final void Function(Object, StackTrace)?` | Called when `onStateChanged` throws, so a broken sink is reported instead of failing silently. Never affects the state machine / 当 `onStateChanged` 抛异常时调用，使坏掉的日志/埋点被上报而不是静默失败；绝不影响状态机 |
| `refreshFailurePolicy` | `final RefreshFailurePolicy` | Whether a failed refresh signs out / 刷新失败是否登出 |
| `clock` | `final DateTime Function()` | Time source; defaults to the system clock / 时间源，默认系统时钟 |
| `current` | `AuthState get current` | Current state, always available / 当前状态，始终可读 |
| `state` | `Stream<AuthState> get state` | Broadcast, replays last value / 广播且重放最近值 |
| `currentSession` | `AuthSession? get currentSession` | `null` unless `Authenticated` / `Refreshing` |
| `accessToken` | `String? get accessToken` | From `AuthTokenSource`; may already be expired — see `validAccessToken` / 可能已过期，见 `validAccessToken` |
| `restore()` | `Future<void> restore({bool refreshIfExpired = true})` | Loads from `TokenStore`; an expired session is refreshed first, dropped when the failure is terminal and **kept** when it is transient. Concurrent calls share one attempt / 载入持久化会话；过期会话先续期，终局失败丢弃、**瞬时**失败保留。并发调用共享同一次尝试 |
| `login()` | `Future<Authenticated> login(Credentials)` | Emits `Authenticating → Authenticated`; on failure emits `AuthError` **and rethrows** |
| `register()` | `Future<Authenticated> register(RegistrationInput)` | Same semantics as `login` |
| `loginWith()` | `Future<Authenticated> loginWith(Future<AuthSession> Function(AuthStrategy))` | Adopts a session from any flow (OAuth, magic link, passkey) / 接纳任意流程的会话 |
| `logout()` | `Future<void>` | Emits `LoggingOut`, best-effort `strategy.logout`, then `clear()`, then `Unauthenticated` |
| `refresh()` | `Future<AuthSession>` | Emits `Refreshing`; single-flight within an epoch; on failure applies `refreshFailurePolicy` / 发出 `Refreshing`；同一 epoch 内单飞；失败时按策略处理 |
| `validAccessToken()` | `Future<String?> validAccessToken({Duration? leeway})` | Never returns an expired token; refreshes first when it expires within `leeway` (default `clockSkew`) / 绝不返回过期令牌；会在 `leeway`（默认 `clockSkew`）内过期时先续期 |
| `updateSession()` | `Future<Authenticated> updateSession(AuthSession Function(AuthSession current))` | Replaces the active session without a re-login (profile update, refreshed claims); throws `NoActiveSessionException` when signed out / 免重新登录替换活动会话 |
| `supports<T>()` | `bool supports<T>()` | Whether the strategy implements an optional capability / 策略是否实现了某可选能力 |
| `dispose()` | `Future<void>` | Closes the stream and cancels proactive refresh. **Later operations throw** `AuthException(code: 'manager_disposed')` / 关闭状态流；之后再操作会抛 `manager_disposed` |

### 11.2 `AuthState` (sealed)

| Subtype | Payload | Meaning |
|---|---|---|
| `Unauthenticated` | – | No session |
| `Authenticating` | – | login / register in flight |
| `Authenticated` | `AuthSession session` | Session active |
| `Refreshing` | `AuthSession session` | Renewal in flight; the previous session stays usable |
| `LoggingOut` | `AuthSession session` | Logout in flight; that session is being discarded |
| `AuthError` | `AppException error` | A failure was reported. Whether the session survives depends on `refreshFailurePolicy`: a terminal one clears it, a transient one keeps it / 已上报一次失败。会话是否保留由 `refreshFailurePolicy` 决定：终局失败清空、瞬时失败保留 |

`bool get isAuthenticated` — `true` for `Authenticated` **and** `Refreshing`, so a
token renewal never unmounts signed-in UI. `bool get isBusy` covers
`Authenticating`, `Refreshing` and `LoggingOut`. `AuthSession? get session`
returns the session any state carries (`Authenticated` / `Refreshing` /
`LoggingOut`), or `null` — no pattern-matching needed for the common case.

`isAuthenticated` 在 `Authenticated` 与 `Refreshing` 下均为 `true`，令牌续期不会卸载
已登录界面；`isBusy` 覆盖 `Authenticating`、`Refreshing`、`LoggingOut`；
`AuthSession? get session` 返回该状态携带的会话（`Authenticated` / `Refreshing` /
`LoggingOut`）或 `null`，常见场景无需再做模式匹配。

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
| `isExpiredAt(now)` | `bool` | Evaluate against your own clock / 按你自己的时钟判断 |
| `timeUntilExpiry([now])` | `Duration?` | Remaining lifetime / 剩余有效期 |
| `isExpiringWithin(window, [now])` | `bool` | Renew a little before it dies / 在真正失效前提前续期 |
| `copyWith(...)` | `AuthSession` | `null` keeps the current value / 传 `null` 表示保留原值 |
| `toJson()` / `fromJson()` | `Map` / `AuthSession` | Persistence; `fromJson` throws on malformed input / 持久化，畸形数据会抛异常 |
| `AuthSession.tryFromJson()` | `AuthSession?` | Same, but `null` instead of throwing / 同上，但返回 `null` 而非抛异常 |

Value equality on `accessToken`, `refreshToken`, `expiresAt`, `userId`,
`displayName` **and `claims`** — nested maps and lists are compared by content,
so a change inside `claims` counts as a new session.

相等性覆盖 `accessToken`、`refreshToken`、`expiresAt`、`userId`、`displayName`
**与 `claims`** —— 嵌套的 Map / List 按内容比较，因此 `claims` 内部的变化也算新会话。

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
String? get accessToken;                                // may be expired / 可能已过期
Future<String?> validAccessToken({Duration? leeway});   // renewed first / 先续期
```

`AuthManager` and `AuthManagerGroup` override `validAccessToken()` to renew the
session first. A source without a manager behind it can simply forward the getter.
`AuthManager` 与 `AuthManagerGroup` 会覆写 `validAccessToken()` 以先续期；背后没有
管理器的令牌源直接转发 getter 即可。

### 11.7 Value objects / 值对象

| Type | Constructor |
|---|---|
| `Credentials` | `Credentials({required String username, required String password})` |
| `RegistrationInput` | `RegistrationInput({required String username, required String password, String? displayName, String? email})` |
| `SessionHandle` | `SessionHandle({required String userId, RefreshToken? refreshToken})` |
| `RefreshToken` | `RefreshToken(String value)` |

Optional capability interfaces a strategy may also implement, detected with
`AuthManager.supports<T>()` / 策略可选实现的能力接口，可用 `supports<T>()` 检测：

| Interface | Method |
|---|---|
| `SupportsPasswordReset` | `Future<void> requestPasswordReset(String identifier)` |
| `SupportsPasswordChange` | `Future<void> changePassword({required currentPassword, required newPassword})` |
| `SupportsReauthentication` | `Future<AuthSession> reauthenticate(Credentials credentials)` |

```dart
if (auth.supports<SupportsPasswordReset>()) {
  await (auth.strategy as SupportsPasswordReset).requestPasswordReset(email);
}
```

### 11.8 Errors / 错误

| Type | Members |
|---|---|
| `AppException` (abstract) | `String message`, `String? code`, `Object? cause`, `toString()` → `AppException(code): message` |
| `AuthException extends AppException` | `AuthFail fail`；`AuthException(String message, {String? code, Object? cause})`；`AuthException.fromFail(AuthFail)` |
| `AuthFail` | `String message`, `String? code`, `Object? cause` |
| `Result<T>` (sealed) | `bool isOk`, `bool isErr`, `T getOrThrow`, `Result<R> map<R>(R Function(T))` |
| `Ok<T>` / `Err<T>` | `T value` / `Object error` (plus `Err.appException` for the mapped domain error / `Err.appException` 提供映射后的领域错误) |

### 11.9 `AuthManagerGroup` (optional, multi-account)

Coordinates one `AuthManager` per account. Opt-in — `AuthManager` itself stays
single-session. See the
[Multi-Account cookbook](https://zero-labsco.github.io/zero_auth/Multi-Account).
协调每个账号一个 `AuthManager`，可选 —— `AuthManager` 本身仍为单会话。详见
[多账号 cookbook](https://zero-labsco.github.io/zero_auth/Multi-Account)。

| Member | Notes |
|---|---|
| `AuthManagerGroup({strategyFactory, storeFactory, managerFactory?, autoRefreshAhead?, autoRefreshRetryDelay?, autoRefreshMaxRetries?, autoRefreshMinInterval?, refreshFailurePolicy?, clock?, clockSkew?, preserveSessionDetails?, onStateChanged?})` | Every manager knob is forwarded to the managers it creates; `managerFactory` builds them yourself. `onStateChanged` is called as `(accountId, state)` / 管理器调参会完整转发；也可传 `managerFactory` 自行构建；`onStateChanged` 以 `(accountId, state)` 形式调用 |
| `forAccount(id)` / `addAccount(id)` | Lazily creates and caches that account's manager / 惰性创建并缓存 |
| `switchTo(id)` | Makes an account active; the group's `state` follows it and `activeIdChanges` emits / 激活账号，状态流随之切换且 `activeIdChanges` 发出新值 |
| `activeIdChanges` | `Stream<String?>` of the active account id (`null` when none) / 激活账号 id 流（无则为 `null`） |
| `accountIds` | `Iterable<String>` of the ids the group currently owns / 分组当前持有的账号 id |
| `activeId` | `String?` — the active account id, `null` when none / 激活账号 id，无则为 `null` |
| `active` | `AuthManager?` — the active account's manager, `null` when none / 激活账号的管理器，无则为 `null` |
| `current` / `state` / `currentSession` / `accessToken` | Mirror the active account / 反映激活账号 |
| `validAccessToken({leeway})` | The active account's renewed token, or `null` / 激活账号续期后的令牌，无则为 `null` |
| `restoreAll(ids, {activeId, dropOthers = false, parallel = false})` | Restores every account — one failing account does not abandon the rest — then activates one. `dropOthers` disposes managers for ids no longer known; `parallel` restores them concurrently / 恢复所有账号（某账号失败不连累其余）并激活其一；`dropOthers` 会释放不再已知 id 的管理器，`parallel` 则并发恢复 |
| `onObserverError` | Called as `(accountId, error, stack)` when the group's `onStateChanged` throws; forwarded to every manager it creates / 当分组的 `onStateChanged` 抛异常时以 `(accountId, error, stack)` 调用；会转发给它创建的每个管理器 |
| `remove(id)` | Signs out and forgets an account / 登出并移除 |
| `logoutAll()` | Signs every account out / 一次性登出所有账号 |
| `disposeAll()` | Releases every manager / 释放所有管理器 |

After `disposeAll()` every read on the group — `accountIds`, `activeId`,
`active`, `current`, `currentSession`, `accessToken`, `state` and
`validAccessToken()` — throws `AuthException(code: 'group_disposed')`, mirroring
the single-manager `manager_disposed` contract. `disposeAll()` itself is
idempotent.

`disposeAll()` 之后，分组上的每一次读取 —— `accountIds`、`activeId`、`active`、
`current`、`currentSession`、`accessToken`、`state` 与 `validAccessToken()` ——
都会抛出 `AuthException(code: 'group_disposed')`，与单管理器的 `manager_disposed`
约定一致；`disposeAll()` 本身可重复调用。

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
| `refresh()` throws `NoActiveSessionException: Refresh aborted` | The refresh started before a newer login / `updateSession` replaced the session; it is aborted on purpose / 刷新在会话被替换之前启动，被有意中止 | Catch `AuthException` in interceptors and retry, or simply read `validAccessToken()` / 在拦截器里捕获 `AuthException` 重试，或直接读 `validAccessToken()` |
| Session lost after restart | Using `InMemoryTokenStore` | Inject a durable `TokenStore` |
| Token never renewed automatically | No built-in timer | Refresh lazily / near expiry / with your own timer ([§9](#9-refresh--expiry--刷新与过期)) |
| Duplicate refresh calls | Bypassing `refresh()` (e.g. calling strategy directly) | Always go through `AuthManager.refresh()` |
| `isExpired` always `false` | `expiresAt` was never set | Populate `expiresAt` when building `AuthSession` |
| Signed out right after launch, on a flaky network | (fixed in 1.0) a transient renewal failure during `restore()` used to clear the store | Upgrade to 1.0: transient failures keep the session / 升级到 1.0，瞬时失败会保留会话 |
| `userId` / `displayName` vanish after a refresh | Your backend returns tokens only | (fixed in 1.0) identity carries over; `preserveSessionDetails: false` opts out / 1.0 起身份字段会保留 |
| `AuthException: Unexpected auth failure` although you threw `AuthFail` with a code | (fixed in 1.0) the code of a bare `AuthFail` used to be ignored | Upgrade to 1.0; `mapAuthFailure` now reads it / 升级到 1.0，`mapAuthFailure` 会读取它 |
| `Bad state`/`FormatException` from your `TokenStore.load()` | `AuthSession.fromJson()` on malformed data | Use `AuthSession.tryFromJson()` / 改用 `tryFromJson()` |
| Compiler error: "missing implementation of `validAccessToken`" | You `implements AuthTokenSource` and upgraded to 1.0 | Add `@override Future<String?> validAccessToken({Duration? leeway}) async => accessToken;` |

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

  await auth.login(const Credentials(username: 'user', password: 'user'));

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
