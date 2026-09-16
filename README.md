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

> **🔔 Upgrade recommended:** `0.2.0` adds **session (de)serialization** (`AuthSession.toJson` / `AuthSession.fromJson`) so sessions survive restarts, a **file-based reference store** for server/CLI, and **opt-in proactive auto-refresh** that renews tokens before they expire. Pin `zero_auth: ^0.2.0` (or git `ref: v0.2.0`).

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
  - [Example app & demo backend](#example-app--demo-backend)
- [API Reference](#api-reference)
- [Architecture](#architecture)
- [Contributing](#contributing)
- [License](#license)

---

## Features

- **Backend-agnostic** — a pure-Dart core; bring any backend by implementing `AuthStrategy` (REST, gRPC, Firebase, your own RPC…).
- **Explicit state machine** — `Unauthenticated → Authenticating → Authenticated → AuthError`, broadcast as a replay-last stream.
- **Silent restore & refresh** — restores the persisted session at startup and refreshes tokens transparently (single-flight, so concurrent callers share one call).
- **Pluggable persistence** — `TokenStore` is the only persistence boundary; the core ships `InMemoryTokenStore`, production uses a secure store (see `example/`).
- **Unified errors** — domain failures map to `AppException` (from this package's error kernel); raw `Exception`s never cross the public surface.
- **Network-ready** — `AuthTokenSource` is the extension point that lets Dio / GraphQL interceptors attach `Authorization: Bearer` headers.
- **Zero native code** — no plugins, no `dart:io`-only APIs; runs on server, CLI, and Flutter alike.
- **Strongly-typed session** — `AuthSession` carries access/refresh tokens, expiry, and raw claims.
- **Session (de)serialization** — `AuthSession.toJson` / `AuthSession.fromJson` make persistence a one-liner; a file-based reference store ships for server/CLI.
- **Proactive auto-refresh** — pass `autoRefreshAhead` to `AuthManager` and tokens renew before expiry (single-flight), so callers rarely hit an expired access token.

## Installation

### Pub.dev (recommended)

```yaml
dependencies:
  zero_auth: ^0.2.0
```

### Git

```yaml
dependencies:
  zero_auth:
    git:
      url: https://github.com/zero-labsco/zero_auth.git
      ref: v0.2.0   # pin a release tag, not a moving branch
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

`AuthManager` *is* an `AuthTokenSource`. Hand it to a Dio interceptor (reference implementation in `example/lib/dio_interceptor.dart`):

```dart
dio.interceptors.add(AuthInterceptor(auth)); // adds `Authorization: Bearer <token>`
```

### Example app & demo backend

The repo ships two runnable pieces, so you can exercise the whole lifecycle end to end:

- `example/` — a Flutter app driving `AuthManager` (login / refresh / logout / call a protected endpoint).
- `server/` — a zero-dependency `dart:io` backend for the example (no `pub get` required).

**1. Start the demo backend**

```bash
cd server
dart run bin/server.dart        # listens on http://localhost:8080
```

| Method & path | Request | Response |
|---------------|---------|----------|
| `POST /login` | `{ "username": "a", "password": "b" }` | `200` tokens (`expiresIn: 3600`) · `401 invalid_credentials` |
| `POST /refresh` | `{ "refreshToken": "demo-refresh-token" }` | `200` new tokens · `401 invalid_refresh_token` |
| `POST /logout` | – | `200 { "ok": true }` |
| `GET /me` | header `Authorization: Bearer demo-access-token` | `200 { "userId", "displayName" }` · `401 unauthorized` |

Any username works, but **the password must be `b`** — anything else returns `401`, which is the easiest way to watch the `AuthError` path. CORS is enabled, so a Flutter Web build can call it directly.

**2. Run the example app**

```bash
cd example
flutter run
```

- The app talks to the **real backend by default**; flip the AppBar switch to fall back to the offline fake (`_DemoStrategy`) when you don't want to run the server.
- Log in with any username and password `b`, then press **Call /me** to watch `AuthInterceptor` attach `Authorization: Bearer …` and the backend echo the user back.
- Stop the backend and log in again to see the mapped `network_unreachable` error instead of a raw `DioException`.

> On an Android emulator use `http://10.0.2.2:8080` instead of `localhost` (`_baseUrl` in `example/lib/main.dart`).

## API Reference

| Type | Role |
|------|------|
| `AuthManager` | Orchestrates the state machine and session lifecycle; the main entry point. |
| `AuthState` | Sealed state: `Unauthenticated` / `Authenticating` / `Authenticated` / `AuthError`. |
| `AuthSession` | The active session: access/refresh tokens, expiry, display name, raw claims. |
| `AuthStrategy` | Backend boundary you implement (login / register / logout / refresh). |
| `TokenStore` | Persistence boundary for the active session (`save` / `load` / `clear`). |
| `AuthTokenSource` | Read-only access-token source for network layers. |
| `AppException` | The single public error type (from this package's error kernel). |
| `Result<T>` | Explicit `Ok` / `Err` success-failure wrapper. |

## Architecture

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

The manager holds no UI, backend, or native code. Wire your backend via `AuthStrategy` and your persistence via `TokenStore`; network layers depend only on `AuthTokenSource`.

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
