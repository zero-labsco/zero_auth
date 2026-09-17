# Third-Party Login / 第三方登录

## The key idea / 核心思路

`zero_auth` does **not** run the OAuth handshake — and that is deliberate. It is a
pure-Dart package, so it ships no platform code, no browser plumbing and no
redirect URL handling (those live outside `lib/`).

Instead, `zero_auth` manages what comes **after** the handshake: the session your
own backend issues.

`zero_auth` **不负责** OAuth 握手环节，这是刻意为之：它是纯 Dart 包，不含任何平台
代码、浏览器通道或重定向回调处理（这些只能在 `lib/` 之外）。

它负责的是握手**之后**的事：你自己后端所签发的会话。

```
provider consent ──► code / id_token ──► YOUR BACKEND ──► your access + refresh tokens ──► zero_auth
   (outside)                            (any language)                                    (this package)
```

Because the login *method* is invisible to the manager, password login and
Google/Apple login end up sharing **one** token lifecycle. That is the whole
point.

登录*方式*对管理器是透明的，因此密码登录与 Google / Apple 登录最终共享**同一套**
令牌生命周期机制。这正是关键所在。

## When this fits / 适用场景

This pattern fits when **your backend brokers the provider** — you have a
backend, it verifies the provider token, then mints your own tokens.

下面的模式适用于**你的后端作为经纪方**：你有后端，它校验提供方令牌，然后签发你自己的
令牌。

| Scenario | Fit |
|----------|-----|
| Own backend + Google/Apple/GitHub sign-in / 自有后端 + 第三方登录 | ✅ Ideal / 理想 |
| Own backend + password AND social logins / 自有后端，密码与社交登录并存 | ✅ One shared session model / 共用一套会话模型 |
| Firebase/Supabase issues the tokens directly / 由 Firebase/Supabase 直接签发令牌 | ⚠️ Use their SDK instead / 请改用其 SDK |

## Wiring it up / 接线步骤

**1. Run the handshake outside this package.**
Use whichever OAuth client fits your targets (`flutter_web_auth`, AppAuth, or a
server-side flow). This code lives in your app or a sibling Flutter package, never
in `lib/`.

**1. 在本包之外完成握手。**
使用适合目标平台的 OAuth 客户端（`flutter_web_auth`、AppAuth 或服务端流程）。这部分
代码放在你的应用或兄弟 Flutter 包里，绝不放在 `lib/`。

**2. Trade the provider credential for your tokens on your backend.**

**2. 用提供方凭据到你的后端换取自有令牌。**

```dart
Future<AuthSession> signInWithGoogle(BuildContext context) async {
  // 1) Provider consent (outside zero_auth) → authorization code / id_token.
  //    提供方授权（零依赖，在 zero_auth 之外）→ 授权码 / id_token。
  final code = await myOAuthClient.authenticate();

  // 2) Your backend verifies it with Google and returns YOUR tokens.
  //    你的后端用它与 Google 校验，并返回「你自己的」令牌。
  final res = await myApi.post('/auth/google', data: {'code': code});

  return AuthSession(
    accessToken: res['accessToken'] as String,
    refreshToken: RefreshToken(res['refreshToken'] as String),
    expiresAt: DateTime.now().add(Duration(seconds: res['expiresIn'] as int)),
    userId: res['userId'] as String,
  );
}
```

**3. Hand the session to the manager with `loginWith`.**
`loginWith` is the escape hatch for flows that are not `login` / `register`: the
manager still owns persistence, the state machine and proactive refresh.

**3. 用 `loginWith` 把会话交给管理器。**
`loginWith` 是为那些不符合 `login` / `register` 形态的流程准备的逃生口：持久化、状态机
与主动刷新仍由管理器负责。

```dart
final result = await auth.loginWith((strategy) => signInWithGoogle(context));
// emits Authenticating → Authenticated, or AuthError + rethrow.
// 发出 Authenticating → Authenticated；失败则发 AuthError 并重新抛出。
```

> Keep `signInWithGoogle` throwing `AuthException` with a meaningful `code`
> (`'invalid_credentials'`, `'session_expired'`, …) so failures map to the typed
> exceptions in [Errors](Errors).
>
> 让 `signInWithGoogle` 抛出带有实用 `code`（`'invalid_credentials'`、
> `'session_expired'` 等）的 `AuthException`，这样失败就能映射为
> [Errors](Errors) 里的具体异常类型。

## Same model for every method / 各登录方式共用一套模型

```dart
// Password users and Google users end up with the same AuthSession shape.
// 密码用户与 Google 用户最终得到的都是同一种 AuthSession。
await auth.login(const Credentials(username: user, password: pass));
await auth.loginWith((strategy) => signInWithGoogle(context));
```

Your UI only ever reads `state.isAuthenticated`, and your network layer only ever
reads `auth.validAccessToken()` — regardless of how the user signed in.

你的界面只需要读 `state.isAuthenticated`，网络层只需要读 `auth.validAccessToken()`
——无需关心用户是哪种方式登录的。

## Also works for / 同样适用于

`loginWith` covers any flow you drive yourself:

`loginWith` 适用于任何由你驱动的流程：

- Magic links / email OTP / 魔法链接、邮箱验证码
- Passkeys / WebAuthn
- Biometric re-unlock (load a locked session and re-mint tokens) / 生物识别解锁
- Migrating from another auth SDK / 从其它认证 SDK 迁移

## Next Steps / 下一步

- [Backend Strategy](Backend-Strategy) — what your strategy must implement / 策略需要实现什么
- [Auth State Machine](Auth-State-Machine) — the states this flow emits / 该流程发出的状态
- [Errors](Errors) — typed exceptions and codes / 类型化异常与 code
