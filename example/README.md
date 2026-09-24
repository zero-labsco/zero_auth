# zero_auth_example

A runnable Flutter app that drives the `zero_auth` state machine end to end:
login, register, silent refresh, logout and a protected `GET /me` call with a
bearer token attached by a Dio interceptor.

Targets: Android, iOS, Web and Windows. Not published to pub.dev
(`publish_to: none`).

## Run it

```bash
# 1. Start the demo backend (keep it running).
cd ../server
dart run bin/server.dart      # http://localhost:8080

# 2. Run the app.
cd ../example
flutter run
```

The app defaults to the **live backend**. Flip the *Live backend* switch off to
fall back to the in-app double (`_DemoStrategy`), which needs no server.

## What to try

| Action | Where | What it shows |
|---|---|---|
| Log in | Sign-in card, `user` / `user` | `Authenticating` → `Authenticated` |
| Register instead | Sign-in card | `register()` — the backend rejects a taken username with `409` |
| Call /me | Session card | The interceptor attaches (and renews) the bearer token |
| Refresh | Session card | A manual `refresh()`; watch rotation in the server log |
| Log out | Session card | `LoggingOut` → `Unauthenticated`, store cleared |
| Expire now / in 10s / Reset | Debug card | Forces a renewal on the next request |

The demo account is `user` / `user`. Access tokens live 120s, so waiting — or
pressing *Expire now* — is enough to see a transparent renewal.

On an Android emulator the backend is not `localhost`: set `_baseUrl` in
`lib/main.dart` to `http://10.0.2.2:8080`.

## Files

| File | Purpose |
|---|---|
| `lib/main.dart` | The app: `AuthManager`, the state-machine UI and the backend toggle |
| `lib/dio_interceptor.dart` | Copy-paste Dio integrations — `RefreshingAuthInterceptor` (renews first), `AuthInterceptor` (synchronous read), `AuthRetryInterceptor` (replays once after a 401) |
| `lib/secure_token_store.dart` | Reference `TokenStore` on `flutter_secure_storage`; use this shape in production |
| `lib/json_token_store.dart` | Reference file-backed `TokenStore` for server / CLI / desktop |
| `test/widget_test.dart` | Renders the signed-out state and checks three viewport sizes |
| `test/json_token_store_test.dart` | Keeps the file-backed reference store honest |

`main.dart` itself uses `InMemoryTokenStore`, so the session does not survive a
restart — swap in one of the reference stores to try persistence.

## Checks

```bash
flutter analyze lib/ test/
flutter test
```
