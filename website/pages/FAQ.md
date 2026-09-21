# FAQ / 常见问题

### Does `zero_auth` ship an HTTP client? / `zero_auth` 内置 HTTP 客户端吗？

No. The core is backend-agnostic and ships no HTTP, SDK or native code. You implement `AuthStrategy` to call your backend.

不。内核后端无关，不含任何 HTTP、SDK 或原生代码。你通过实现 `AuthStrategy` 来调用自己的后端。

### Does it depend on Flutter? / 它依赖 Flutter 吗？

No. It is a pure-Dart package; `flutter:` is only a declared constraint because the example app uses Flutter. The runtime has no Flutter dependency.

不。它是纯 Dart 包；仅因示例 App 用到 Flutter 才声明 `flutter:` 约束，运行时不依赖 Flutter。

### Where are tokens stored? / 令牌存在哪里？

Wherever your `TokenStore` puts them. The core ships `InMemoryTokenStore` (lost on restart). For production, use the `flutter_secure_storage`-backed reference in `example/lib/secure_token_store.dart`.

取决于你的 `TokenStore`。内核自带 `InMemoryTokenStore`（重启即丢失）。生产请用 `example/lib/secure_token_store.dart` 中基于 `flutter_secure_storage` 的参考实现。

### What happens on a failed refresh? / 刷新失败会怎样？

The failure is always reported as `AuthError` and rethrown. What happens *next*
depends on `refreshFailurePolicy`: an unrecoverable failure (`SessionExpiredException`,
`InvalidCredentialsException`) clears the store and lands on `Unauthenticated`,
while a transient one (network, 5xx) keeps the previous session so a retry can
succeed. See [Configuration](Configuration#refresh-failure-policy).

失败总会以 `AuthError` 上报并重新抛出。*之后*如何取决于 `refreshFailurePolicy`：
不可恢复的失败（`SessionExpiredException`、`InvalidCredentialsException`）会清空存储
并落到 `Unauthenticated`；瞬时故障（网络、5xx）保留上一个会话以便重试成功。参见
[配置](Configuration#refresh-failure-policy)。

### Is token refresh concurrent-safe? / 令牌刷新是否并发安全？

Yes — `refresh()` is single-flight: many concurrent callers share one in-flight request and its result.

是的——`refresh()` 为单飞：多个并发调用方共享同一次请求及其结果。

### How do I attach the bearer token to requests? / 如何给请求附加 Bearer 令牌？

`AuthManager` is an `AuthTokenSource`. Use the Dio interceptor in `example/lib/dio_interceptor.dart`, or read `accessToken` directly — but prefer `validAccessToken()` (or `RefreshingAuthInterceptor`) whenever the token reaches a server, since `accessToken` may already be expired.

`AuthManager` 即 `AuthTokenSource`。可用 `example/lib/dio_interceptor.dart` 中的 Dio 拦截器，或直接读取 `accessToken` —— 但只要令牌要发到服务端，就请优先用 `validAccessToken()`（或 `RefreshingAuthInterceptor`），因为 `accessToken` 可能已经过期。

### Does it sync sessions across devices? / 它会在多设备间同步会话吗？

No — and by design. A session is local state plus whatever your backend decides;
pushing "signed out elsewhere" to a device needs server push (or polling), which
is outside a headless state machine. Model it with your backend revoking the
grant: the next refresh fails, `refreshFailurePolicy` signs the device out, and
`AuthError` explains why.

不会 —— 这是有意的设计。会话是本地状态加上你后端的决定；把「在别处已登出」推送到某台
设备需要服务端推送（或轮询），那超出了无头状态机的职责。可由后端吊销授权来实现：下一次
刷新失败，`refreshFailurePolicy` 会让该设备登出，并由 `AuthError` 说明原因。

### Which platforms are supported? / 支持哪些平台？

Any platform where Dart or Flutter runs (Android, iOS, Web, Windows, macOS, Linux).

任何能运行 Dart 或 Flutter 的平台（Android、iOS、Web、Windows、macOS、Linux）。
