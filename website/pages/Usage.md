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
| `restore()` | Rehydrate the persisted session at startup / 启动时恢复会话 |
| `login(username, password)` | Authenticate and enter `Authenticated` / 登录并进入已认证 |
| `register(username, password)` | Register and authenticate / 注册并认证 |
| `logout()` | Clear the session / 清除会话 |
| `refresh()` | Silent token refresh — concurrent calls share one flight / 静默刷新，并发共享单飞 |
| `tokenSource` | An `AuthTokenSource` for HTTP clients / 供 HTTP 客户端使用的令牌源 |

## Token refresh & expiry / 令牌刷新与过期

`AuthSession` exposes `isExpired` so callers can refresh proactively. `refresh()` is single-flight: if several callers request a refresh at once, only one network call is made and its result is shared.

`AuthSession` 提供 `isExpired`，调用方可主动刷新。`refresh()` 为单飞：多个调用方同时请求刷新时，只发起一次网络调用并共享结果。 A failed refresh clears the session and emits `AuthError`.

刷新失败会清空会话并发出 `AuthError`。

## Attaching the bearer token / 附加 Bearer 令牌

`AuthManager` implements `AuthTokenSource`, so a Dio interceptor can read the current token without depending on the manager. See [Network Integration](Network-Integration).

`AuthManager` 实现了 `AuthTokenSource`，Dio 拦截器可在不依赖管理器的情况下读取当前令牌。详见[网络集成](Network-Integration)。

## Next Steps / 下一步

- [Auth State Machine](Auth-State-Machine) — State lifecycle details / 状态机细节
- [Backend Strategy](Backend-Strategy) — Full `AuthStrategy` contract / 完整后端契约
- [Errors](Errors) — Exception & `Result` model / 异常与结果模型
