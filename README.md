# Zero Auth

<div align="center" style="display: flex; align-items: center; justify-content: center; gap: 36px;">
<span style="font-size: 1.1em; padding: 0 8px;"><strong>English</strong> &nbsp;|&nbsp; <a href="README_zh.md">简体中文</a></span>
</div>

A backend-agnostic **auth state machine & session lifecycle** for Dart/Flutter: it models *who is logged in, who they are, and how they logged in / out / recovered* — a pure-Dart, headless core with **zero** native code, backend SDK, UI, or state-management framework.

[![License: MPL-2.0](https://img.shields.io/badge/License-MPL--2.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Dart%20%7C%20Flutter-green.svg)](https://pub.dev/packages/zero_auth)
[![Flutter](https://img.shields.io/badge/Flutter-✓-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-✓-0175C2?logo=dart)](https://dart.dev)
[![Style: effective dart](https://img.shields.io/badge/style-effective_dart-40c4ff.svg)](https://pub.dev/packages/effective_dart)

> **🔔 Upgrade recommended:** `1.0.0` is the **first stable release** — the public API is now frozen under semver. It closes the last lifecycle holes: `restore()` no longer signs you out when a renewal fails transiently, a late refresh can no longer overwrite a newer login, and a renewal no longer erases `userId` / `displayName` / `claims`. It also adds clock-skew tolerance (`clockSkew`, default 30s), `AuthSession.tryFromJson`, `AuthState.session` and renewing `AuthTokenSource.validAccessToken()`. **One migration step:** if you `implements AuthTokenSource`, add `@override Future<String?> validAccessToken({Duration? leeway}) async => accessToken;`. Pin `zero_auth: ^1.0.0` (or git `ref: release/v1.0.0`).

🌐 **[Official Website](https://www.zerolabsco.com/)** &nbsp;·&nbsp; 📦 **[View on pub.dev](https://pub.dev/packages/zero_auth)** &nbsp;·&nbsp; 🔗 **[View on GitHub](https://github.com/zero-labsco/zero_auth)**

---

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
  - [Quick start](#quick-start)
  - [Wire your backend (`AuthStrategy`)](#wire-your-backend-authstrategy)
  - [Persist the session (`TokenStore`)](#persist-the-session-tokenstore)
  - [Attach tokens to the network (`AuthTokenSource`)](#attach-tokens-to-the-network-authtokensource)
  - [Bring your own login flow (`loginWith`)](#bring-your-own-login-flow-loginwith)
  - [Never send an expired token](#never-send-an-expired-token)
  - [Handle failures with typed errors](#handle-failures-with-typed-errors)
  - [Example app & demo backend](#example-app--demo-backend)
- [API Reference](#api-reference)
- [Architecture](#architecture)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

---

## Features

- **Backend-agnostic** — a pure-Dart core; bring any backend by implementing `AuthStrategy` (REST, gRPC, Firebase, your own RPC…).
- **Explicit state machine** — `Unauthenticated`, `Authenticating`, `Authenticated`, `Refreshing`, `LoggingOut` and `AuthError`, broadcast as a replay-last stream. Prefer `state.isAuthenticated` / `state.isBusy` over `state is Authenticated`, so a token renewal never unmounts your signed-in UI.
- **Silent restore & refresh** — restores the persisted session at startup (refreshing it first when it has expired) and refreshes tokens transparently (single-flight, so concurrent callers share one call).
- **Bring your own login flow** — `loginWith` adopts a session from any flow you drive yourself: third-party OAuth, magic links, passkeys or biometric unlock.
- **Never send an expired token** — `validAccessToken()` renews the session first when the token has expired (or is about to, per `clockSkew`); ideal for HTTP interceptors.
- **Clock-skew tolerant** — `clockSkew` (default 30s) treats a token as expired a little early, so a device clock running ahead cannot hand out a token that dies in flight.
- **Typed auth exceptions** — `InvalidCredentialsException`, `SessionExpiredException`, and friends, mapped automatically from your strategy's `AuthException.code`.
- **Configurable refresh failure handling** — `refreshFailurePolicy` decides whether a failed refresh signs the user out (default: yes for unrecoverable failures, no for transient ones).
- **Multiple accounts (opt-in)** — `AuthManagerGroup` keeps one `AuthManager` per account so several can stay signed in at once; the core itself stays single-session.
- **Pluggable persistence** — `TokenStore` is the only persistence boundary; the core ships `InMemoryTokenStore`, production uses a secure store (see `example/`).
- **Unified errors** — domain failures map to `AppException` (from this package's error kernel); raw `Exception`s never cross the public surface.
- **Network-ready** — `AuthTokenSource` is the extension point that lets Dio / GraphQL interceptors attach `Authorization: Bearer` headers.
- **Zero native code** — no plugins, no `dart:io`-only APIs; runs on server, CLI, and Flutter alike.
- **Strongly-typed session** — `AuthSession` carries access/refresh tokens, expiry, and raw claims.
- **Session (de)serialization** — `AuthSession.toJson` / `AuthSession.fromJson` make persistence a one-liner; `AuthSession.tryFromJson` returns `null` instead of throwing on malformed data. A file-based reference store ships for server/CLI.
- **Proactive auto-refresh** — pass `autoRefreshAhead` to `AuthManager` and tokens renew before expiry (single-flight), so callers rarely hit an expired access token.

## Installation

### Pub.dev (recommended)

```yaml
dependencies:
  zero_auth: ^1.0.0
```

### Git

```yaml
dependencies:
  zero_auth:
    git:
      url: https://github.com/zero-labsco/zero_auth.git
      ref: release/v1.0.0   # pin the release/vX.Y.Z branch (immutable per release)
```

## Usage

### Quick start

```dart
import 'package:zero_auth/zero_auth.dart';

final auth = AuthManager(strategy: MyAuthStrategy());

void main() async {
  await auth.restore();        // restore a persisted session at app start
  auth.state.listen((s) {      // subscribe to state changes (replays last)
    print(s);
  });

  await auth.login(Credentials(username: 'me', password: '••••'));
}
```

### Wire your backend (`AuthStrategy`)

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

### Persist the session (`TokenStore`)

The core ships only `InMemoryTokenStore`. For production, inject a secure store — a `flutter_secure_storage`-backed reference implementation lives in `example/lib/secure_token_store.dart`:

```dart
final auth = AuthManager(
  strategy: MyAuthStrategy(),
  tokenStore: SecureTokenStore(),   // from example/
);
```

### Attach tokens to the network (`AuthTokenSource`)

`AuthManager` *is* an `AuthTokenSource`. Hand it to a Dio interceptor (reference implementations in `example/lib/dio_interceptor.dart`):

```dart
// Renews first when needed — the safe default for real apps.
dio.interceptors.add(RefreshingAuthInterceptor(auth));

// Synchronous variant: attaches whatever the session currently holds, which may
// already be expired. Fine for short-lived sessions you renew elsewhere.
dio.interceptors.add(AuthInterceptor(auth));
```

Because `AuthTokenSource` itself now exposes `validAccessToken()`, an interceptor
can depend on the interface alone and still get a renewed token.

### Bring your own login flow (`loginWith`)

Third-party OAuth, magic links and passkeys are flows *you* drive; `zero_auth`
only owns what comes after. The provider handshake stays outside this package
(it needs platform code), your backend verifies the provider credential and mints
*your* tokens, and `loginWith` hands that session to the manager:

```dart
Future<AuthSession> signInWithGoogle() async {
  final code = await myOAuthClient.authenticate();        // outside zero_auth
  final res = await myApi.post('/auth/google', {'code': code});
  return AuthSession(
    accessToken: res['accessToken'] as String,
    refreshToken: RefreshToken(res['refreshToken'] as String),
    expiresAt: DateTime.now().add(Duration(seconds: res['expiresIn'] as int)),
    userId: res['userId'] as String,
  );
}

// Emits Authenticating -> Authenticated, or AuthError + rethrow.
await auth.loginWith((strategy) => signInWithGoogle());
```

The full pattern — including why the login *method* is invisible to the state
machine — lives in the
[Third-Party Login cookbook](https://zero-labsco.github.io/zero_auth/Third-Party-Login).

### Never send an expired token

`accessToken` returns whatever the current session holds, which may already be
expired. For network layers use `validAccessToken()`: it renews first (reusing the
single-flight refresh) and returns `null` only when there is nothing to send.

```dart
final token = await auth.validAccessToken();
if (token != null) headers['Authorization'] = 'Bearer $token';
```

It also refuses a token that would die *while the request is in flight*:
`clockSkew` (default 30s) is how much validity is left as a margin, and
`validAccessToken(leeway:)` overrides it per call.

```dart
// A long upload: demand a token that survives the next two minutes.
final token = await auth.validAccessToken(leeway: const Duration(minutes: 2));

// Opt out of the skew entirely.
final strict = AuthManager(strategy: strategy, clockSkew: Duration.zero);
```

> If your access tokens live **shorter than a minute**, lower `clockSkew` (say
> `const Duration(seconds: 5)`) — otherwise almost every read renews first.

Or let the manager renew proactively before expiry:

```dart
final auth = AuthManager(
  strategy: strategy,
  autoRefreshAhead: const Duration(minutes: 5),
);
```

Either way, a renewal that only returns tokens keeps the signed-in identity
(`userId` / `displayName` / `claims`); pass `preserveSessionDetails: false` to
take the backend answer verbatim.

### Handle failures with typed errors

Failures never leak raw `Exception`s. Your strategy opts into precise types by
throwing an `AuthException` with a `code`:

| `code` | Maps to |
|--------|---------|
| `invalid_credentials` | `InvalidCredentialsException` |
| `invalid_grant` / `invalid_refresh_token` / `token_expired` / `session_expired` | `SessionExpiredException` |
| `no_active_session` | `NoActiveSessionException` |
| `refresh_token_missing` | `RefreshTokenMissingException` |
| anything else | kept as-is, or `UnexpectedAuthException` |

```dart
try {
  await auth.login(credentials);
} on SessionExpiredException {
  // the grant is dead: only a fresh login recovers
} on InvalidCredentialsException {
  // show a form error
} on AuthException catch (e) {
  // every other auth failure, still carrying a stable e.code
}
```

A failed refresh is also reported on the state stream as `AuthError`. Whether it
ends the session is up to `refreshFailurePolicy`: unrecoverable failures sign the
user out, transient ones keep the session so a retry can succeed.

### Example app & demo backend

The repo ships two runnable pieces, so you can exercise the whole lifecycle end to end:

- `example/` — a Flutter app driving `AuthManager` (login / refresh / logout / call a protected endpoint).
- `server/` — a layered `dart:io` backend that issues real HMAC-SHA256 JWTs with refresh-token rotation, family revocation and replay detection, and logs every request. Run `dart pub get` once before starting it.

**1. Start the demo backend**

```bash
cd server
dart pub get
dart run bin/server.dart        # listens on http://localhost:8080
```

| Method & path | Request | Response |
|---------------|---------|----------|
| `POST /login` | `{ "username": "user", "password": "user" }` | `200` real JWT pair + `expiresIn` · `401 invalid_credentials` |
| `POST /refresh` | `{ "refreshToken": "<rotating token>" }` | `200` rotated pair · `401 invalid_grant` (expired, revoked or replayed) |
| `POST /logout` | `{ "refreshToken": "…" }` | `200 { "ok": true }` — revokes the token family |
| `GET /me` | header `Authorization: Bearer <access token>` | `200 { "userId", "displayName" }` · `401 invalid_token` |
| `GET /health` | – | `200 { "status": "ok", … }` |
| `POST /debug/expire-access` | – | Rejects every access token issued so far |
| `POST /debug/access-ttl` | `{ "seconds": 10 }` | Changes the lifetime granted to new tokens |
| `POST /debug/reset` | – | Restores the defaults and clears simulated expiry |

Sign in with **`user` / `user`** — anything else returns `401`, which is the easiest way to watch the `AuthError` path. Tokens are real HMAC-SHA256 JWTs with refresh-token rotation and replay detection, and every request is logged. CORS is enabled, so a Flutter Web build can call it directly.

**2. Run the example app**

```bash
cd example
flutter run
```

- The app talks to the **real backend by default**; turn **Live backend** off in its card to fall back to the offline double (`_DemoStrategy`).
- Log in with `user` / `user`, then press **Call /me** to watch the interceptor attach `Authorization: Bearer …` and the backend echo the user back.
- While signed in, the **Debug** card offers *Expire now* (then `Call /me` shows the `401`) and *Expire in 10s* (shortens the token so the next `Call /me` exercises transparent renewal).
- Stop the backend and log in again to see the mapped `network_unreachable` error instead of a raw `DioException`.

> On an Android emulator use `http://10.0.2.2:8080` instead of `localhost` (`_baseUrl` in `example/lib/main.dart`).

## API Reference

> **Upgrading to 1.0** — the public surface is frozen under semver from here on.
> One migration step: if you `implements AuthTokenSource`, add
> `@override Future<String?> validAccessToken({Duration? leeway}) async => accessToken;`.
> (From 0.2.x: `AuthState` gained the `Refreshing` and `LoggingOut` subtypes, so
> exhaustive `switch` statements must handle them — prefer `state.isAuthenticated`
> and `state.isBusy`, which stay correct as states evolve.)

### `AuthManager`

| Member | Signature | Notes |
|--------|-----------|-------|
| constructor | `AuthManager({required strategy, TokenStore? tokenStore, Duration? autoRefreshAhead, Duration? autoRefreshRetryDelay, int? autoRefreshMaxRetries, Duration? autoRefreshMinInterval, RefreshFailurePolicy? refreshFailurePolicy, DateTime Function()? clock, Duration? clockSkew, bool preserveSessionDetails = true, void Function(AuthState)? onStateChanged})` | `tokenStore` defaults to `InMemoryTokenStore`; `autoRefreshAhead` enables proactive renewal, `autoRefreshRetryDelay` re-arms a failed one, `autoRefreshMaxRetries` caps those retries (default 3) and `autoRefreshMinInterval` floors an already-due one (default 5s); `clockSkew` is how much earlier a token counts as expired (default 30s); `preserveSessionDetails` keeps identity fields across a renewal; `clock` overrides the time source; `onStateChanged` observes every emission |
| `current` | `AuthState get current` | Latest state, always readable |
| `state` | `Stream<AuthState> get state` | Broadcast, replays the latest value to new listeners |
| `currentSession` | `AuthSession? get currentSession` | Available while `Authenticated` **and** `Refreshing` |
| `accessToken` | `String? get accessToken` | May already be expired — use `validAccessToken` for requests |
| `restore()` | `Future<void> restore({bool refreshIfExpired = true})` | Heals an expired persisted session; keeps it when the renewal fails transiently, drops it when the failure is terminal. Concurrent calls share one attempt |
| `login()` | `Future<Authenticated> login(Credentials)` | Emits `Authenticating → Authenticated`; on failure emits `AuthError` **and rethrows** |
| `register()` | `Future<Authenticated> register(RegistrationInput)` | Same semantics as `login` |
| `loginWith()` | `Future<Authenticated> loginWith(Future<AuthSession> Function(AuthStrategy))` | Adopts a session from any flow you drive yourself |
| `refresh()` | `Future<AuthSession>` | Emits `Refreshing`; single-flight within one epoch; applies `refreshFailurePolicy` on failure |
| `validAccessToken()` | `Future<String?> validAccessToken({Duration? leeway})` | Never returns an expired token; renews first when it expires within `leeway` (default `clockSkew`) |
| `logout()` | `Future<void>` | Emits `LoggingOut`, best-effort backend call, clears the store, lands on `Unauthenticated` |
| `updateSession()` | `Future<Authenticated> updateSession(AuthSession Function(AuthSession))` | Replaces the active session without a re-login; throws when nothing is signed in |
| `supports<T>()` | `bool supports<T>()` | Whether the strategy implements an optional capability |
| `dispose()` | `Future<void>` | Closes the stream and cancels proactive refresh. Later operations throw `AuthException(code: 'manager_disposed')` |

### `AuthManagerGroup` (optional, multi-account)

Coordinates one `AuthManager` per account. Opt-in: `AuthManager` itself stays
single-session, so nothing changes unless you use this.

| Member | Notes |
|--------|-------|
| constructor | `AuthManagerGroup({required strategyFactory, required storeFactory, managerFactory, autoRefreshAhead, autoRefreshRetryDelay, autoRefreshMaxRetries, autoRefreshMinInterval, refreshFailurePolicy, clock, clockSkew, preserveSessionDetails, onStateChanged})` — both factories receive the account id; give each account its own `TokenStore`. Every manager knob is forwarded to the managers it creates; `managerFactory` builds them yourself instead |
| `forAccount(id)` / `addAccount(id)` | Lazily creates and caches that account's `AuthManager` |
| `switchTo(id)` | Makes an account active; the group's `state` follows it and `activeIdChanges` emits |
| `activeIdChanges` | `Stream<String?>` of the active account id (`null` when none is active) |
| `onStateChanged` | Called as `(accountId, state)` for every emission of every account |
| `logoutAll()` | Signs every account out and forgets them |
| `current` / `state` / `currentSession` / `accessToken` | Mirror the active account |
| `validAccessToken()` | The active account's renewed token, or `null` |
| `restoreAll(ids, {activeId})` | Restores every account — one failing account does not abandon the rest — then activates one |
| `remove(id)` | Signs out and forgets an account |
| `disposeAll()` | Releases every manager |

If you only need to *switch* between accounts, a simple logout + login is usually
enough — see the [Multi-Account cookbook](https://zero-labsco.github.io/zero_auth/Multi-Account).

### `AuthState` (sealed)

| Subtype | Payload | Meaning |
|---------|---------|---------|
| `Unauthenticated` | – | No session |
| `Authenticating` | – | `login` / `register` / `loginWith` in flight |
| `Authenticated` | `AuthSession session` | Session active |
| `Refreshing` | `AuthSession session` | Renewal in flight; the previous session stays usable |
| `LoggingOut` | `AuthSession session` | Logout in flight; that session is being discarded |
| `AuthError` | `AppException error` | Last operation failed |

Helpers: `isAuthenticated` is `true` for `Authenticated` **and** `Refreshing`;
`isBusy` covers `Authenticating`, `Refreshing` and `LoggingOut`; `session`
returns the session any state carries (`Authenticated` / `Refreshing` /
`LoggingOut`), or `null`.

### `AuthSession`

| Member | Notes |
|--------|-------|
| `accessToken`, `refreshToken`, `expiresAt`, `userId`, `displayName`, `claims` | Tokens, expiry, identity and raw claims |
| `isExpired` | Expired per the system clock |
| `isExpiredAt(DateTime)` | Expired per your own clock |
| `timeUntilExpiry([DateTime])` | Remaining lifetime, or `null` when there is no expiry |
| `isExpiringWithin(window, [DateTime])` | Renew a little before it actually dies |
| `copyWith(...)` | Replace only the fields you pass; `null` keeps the current value (build a new session to clear one) |
| `toJson()` / `AuthSession.fromJson()` | Persistence; `null` fields are omitted. `fromJson` throws on malformed input |
| `AuthSession.tryFromJson()` | Same, but returns `null` instead of throwing — use it for anything read from disk or secure storage |

### Boundaries & value objects

| Type | Role |
|------|------|
| `AuthStrategy` | Backend boundary you implement: `login` / `register` / `logout` / `refresh` |
| `TokenStore` | Persistence boundary: `save` / `load` / `clear`; `InMemoryTokenStore` ships in-core |
| `AuthTokenSource` | Read-only token source for network layers: `accessToken` plus `validAccessToken({leeway})` (renews first when backed by a manager). `AuthManager` and `AuthManagerGroup` implement it |
| `Credentials`, `RegistrationInput`, `SessionHandle`, `RefreshToken` | Value objects passed across those boundaries |
| `SupportsPasswordReset`, `SupportsPasswordChange`, `SupportsReauthentication` | Optional capability interfaces; detect with `AuthManager.supports<T>()` so the four-method contract stays intact |

### Errors

| Type | Role |
|------|------|
| `AppException` | The single public error type: `message` / `code` / `cause` |
| `AuthException` | Base auth failure, carrying an `AuthFail` |
| `InvalidCredentialsException` | Credentials rejected; retrying them fails again |
| `SessionExpiredException` | Grant expired or revoked; only a fresh login recovers |
| `NoActiveSessionException` | An operation needed an active session and there was none |
| `RefreshTokenMissingException` | Refresh requested for a session without a refresh token |
| `UnexpectedAuthException` | Fallback for anything unclassifiable |
| `mapAuthFailure(Object)` | Maps a caught error onto the richest subclass, by `code` — works for both `AuthException` and a bare `AuthFail` |
| `defaultRefreshFailurePolicy` | Signs out on unrecoverable failures, keeps the session on transient ones |
| `Result<T>` | Optional explicit `Ok` / `Err` wrapper |

## Architecture

```
   login/register ──► Authenticating ──► Authenticated
                                            │
                              refresh ──────┤
                                            ▼
                                        Refreshing
                                       │         │
                            renewed ───┘         └─── failed
                                │                      │
                                ▼                      ▼
                    Authenticated (new token)      AuthError
                                                   │        │
                                    unrecoverable ─┘        └── transient
                                          │                       │
                                          ▼                       ▼
                                   Unauthenticated          Authenticated
                                                           (previous session)

   logout ──► LoggingOut ──► Unauthenticated
   restore() ──► Authenticated, or Unauthenticated when nothing persists
                 (a transient renewal failure keeps the persisted session)
```

The manager holds no UI, backend, or native code. Wire your backend via `AuthStrategy` and your persistence via `TokenStore`; network layers depend only on `AuthTokenSource`.

Consecutive duplicate states are suppressed, so listeners only rebuild on a real
change.

## Documentation

This README is the front door; these go deeper:

- [Usage & API Guide](USAGE.md) — the complete reference: every boundary, the
  error model, lifecycle best practices, pitfalls and testing.
- [Documentation site](https://zero-labsco.github.io/zero_auth/) — topic pages and
  cookbooks: [Auth State Machine](https://zero-labsco.github.io/zero_auth/Auth-State-Machine),
  [Backend Strategy](https://zero-labsco.github.io/zero_auth/Backend-Strategy),
  [Token Store](https://zero-labsco.github.io/zero_auth/Token-Store),
  [Network Integration](https://zero-labsco.github.io/zero_auth/Network-Integration),
  [Errors](https://zero-labsco.github.io/zero_auth/Errors),
  [Configuration](https://zero-labsco.github.io/zero_auth/Configuration),
  [Session Persistence](https://zero-labsco.github.io/zero_auth/Persistence),
  [Third-Party Login](https://zero-labsco.github.io/zero_auth/Third-Party-Login)
  and [Multi-Account](https://zero-labsco.github.io/zero_auth/Multi-Account).

## Contributing

Contributions are welcome! Please read the [Contributing Guidelines](CONTRIBUTING.md) before submitting issues or pull requests.

- 🐛 [Report a Bug](https://github.com/zero-labsco/zero_auth/issues/new?template=bug_report.md)
- 💡 [Request a Feature](https://github.com/zero-labsco/zero_auth/issues/new?template=feature_request.md)
- 💬 [Join Discussions](https://github.com/zero-labsco/zero_auth/discussions)

## License

Copyright (c) 2026 Zero Labs Co. (AmisKwok). This project is licensed under the **Mozilla Public License 2.0 (MPL-2.0)** — see the [LICENSE](LICENSE) file for details. The copyright notice and additional statements (no warranty, no endorsement) live in [NOTICE](NOTICE).

- **Commercial use is allowed.** Use, modification and closed-source distribution are permitted.
- **Modified the package?** The files you modified must be published in source form under MPL-2.0. Your own app does **not** need to be open-sourced.
- **Used it unmodified?** No source disclosure is required.
- **No endorsement.** "Zero Labs Co.", "zero_auth", the logo / mascot artwork, and the author's name (AmisKwok) may not be used to endorse or promote derived products, or to imply sponsorship or affiliation, without prior written permission.
- **No warranty, no liability.** The copyright holder provides no warranty and accepts no liability for any modified or derivative version; modified versions must be clearly marked as modified.

This package is provided "as is", without warranty of any kind. The author assumes no responsibility or liability for the functionality, security, or any consequences arising from the use of modified versions or derivative projects.
