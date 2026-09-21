/// Read-only access-token source for network layers (Dio / GraphQL interceptors).
/// 供网络层（Dio / GraphQL 拦截器）使用的只读访问令牌来源。
abstract class AuthTokenSource {
  /// Current access token, or `null` when unauthenticated.
  ///
  /// This value may already be expired — read [validAccessToken] when the token
  /// is about to be attached to a request.
  /// 当前访问令牌；未认证时为 `null`。
  ///
  /// 该值可能已经过期 —— 令牌即将附着到请求上时，请读取 [validAccessToken]。
  String? get accessToken;

  /// A token that is guaranteed not to be expired, refreshing first when needed.
  /// Returns `null` when unauthenticated.
  ///
  /// [leeway] is how long the token must stay valid for; a token that would die
  /// while the request is in flight is renewed first.
  ///
  /// Sources backed by an `AuthManager` renew the session; a plain source falls
  /// back to [accessToken]. The default implementation keeps every existing
  /// implementation source-compatible.
  /// 保证未过期的令牌，必要时先刷新；未认证时返回 `null`。
  ///
  /// [leeway] 表示令牌必须还能维持有效的时长；会在请求途中失效的令牌会被提前续期。
  ///
  /// 由 `AuthManager` 支持的来源会续期会话；普通来源回落到 [accessToken]。默认实现
  /// 使所有既有实现保持源码兼容。
  Future<String?> validAccessToken({Duration? leeway}) async => accessToken;
}
