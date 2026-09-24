# Usage / 使用指南

## Three-step integration / 三步集成

### 1. Implement `AuthStrategy` / 实现后端边界

```dart
class MyAuthStrategy implements AuthStrategy {
  @override
  Future<AuthSession> login(Credentials credentials) => myApi.login(
        credentials.username, // an email or phone works too
        credentials.password,
      );

  @override
  Future<AuthSession> register(RegistrationInput input) =>
      myApi.register(input.username, input.password);

  @override
  Future<void> logout(SessionHandle handle) => myApi.logout(handle.userId);

  @override
  Future<AuthSession> refresh(RefreshToken token) =>
      myApi.refresh(token.value);
}
```

### 2. Create `AuthManager` and restore / 创建管理器并恢复

```dart
final auth = AuthManager(
  strategy: MyAuthStrategy(),
  tokenStore: InMemoryTokenStore(),
);
await auth.restore(); // rehydrate a persisted session / 恢复持久化会话
```

### 3. Drive the UI from the state stream / 用状态流驱动界面

```dart
await for (final state in auth.state) {
  // render based on state / 根据状态渲染
}
```

## Operations / 操作

| Method | Description |
|--------|-------------|
| `restore({refreshIfExpired = true})` | Rehydrate the persisted session at startup / 启动时恢复会话 |
| `login(Credentials)` | Authenticate and enter `Authenticated` / 登录并进入已认证 |
| `register(RegistrationInput)` | Register and authenticate / 注册并认证 |
| `logout()` | Notify the backend, clear the session, emit `Unauthenticated` / 通知后端、清除会话并发 `Unauthenticated` |
| `refresh()` | Silent token refresh — concurrent calls share one flight / 静默刷新，并发共享单飞 |
| `updateSession(update)` | Replace the active session without a re-login / 无需重新登录即可替换会话 |
| `loginWith(flow)` | Adopt a session from a flow you drive yourself (OAuth, magic link…) / 接纳自行驱动流程产生的会话 |
| `accessToken` | The current token, possibly already expired / 当前令牌，可能已过期 |
| `validAccessToken({leeway})` | A token guaranteed unexpired, renewing first when needed / 保证未过期的令牌，必要时先续期 |

`AuthManager` itself **is** an `AuthTokenSource`, so there is no separate `tokenSource` member to reach for: pass the manager (or the narrower interface) straight to your HTTP layer.

`AuthManager` 本身**就是** `AuthTokenSource`，因此并不存在单独的 `tokenSource` 成员：把管理器（或更窄的接口）直接交给网络层即可。

## Token refresh & expiry / 令牌刷新与过期

`AuthSession` exposes `isExpired` so callers can refresh proactively. `refresh()` is single-flight: if several callers request a refresh at once, only one network call is made and its result is shared.

`AuthSession` 提供 `isExpired`，调用方可主动刷新。`refresh()` 为单飞：多个调用方同时请求刷新时，只发起一次网络调用并共享结果。

A failed refresh always emits `AuthError` first, but it does **not** necessarily end the session. `refreshFailurePolicy` decides: a **terminal** failure (`SessionExpiredException`, `InvalidCredentialsException` by default) clears the stored session and lands on `Unauthenticated`, while a **transient** one (network hiccup, 5xx) keeps the session so a later call can retry.

刷新失败总是先发出 `AuthError`，但**不一定**终止会话。由 `refreshFailurePolicy` 决定：**终局**失败（默认 `SessionExpiredException`、`InvalidCredentialsException`）会清空存储的会话并落到 `Unauthenticated`；**瞬时**失败（网络抖动、5xx）则保留会话，供稍后重试。

## Attaching the bearer token / 附加 Bearer 令牌

`AuthManager` implements `AuthTokenSource`, so a Dio interceptor can read the current token without depending on the manager. See [Network Integration](Network-Integration).

`AuthManager` 实现了 `AuthTokenSource`，Dio 拦截器可在不依赖管理器的情况下读取当前令牌。详见[网络集成](Network-Integration)。

## Next Steps / 下一步

- [Auth State Machine](Auth-State-Machine) — State lifecycle details / 状态机细节
- [Backend Strategy](Backend-Strategy) — Full `AuthStrategy` contract / 完整后端契约
- [Errors](Errors) — Exception & `Result` model / 异常与结果模型
