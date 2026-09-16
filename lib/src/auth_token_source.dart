/// Read-only access-token source for network layers (Dio / GraphQL interceptors).
/// 供网络层（Dio / GraphQL 拦截器）使用的只读访问令牌来源。
abstract class AuthTokenSource {
  /// Current access token, or `null` when unauthenticated.
  /// 当前访问令牌；未认证时为 `null`。
  String? get accessToken;
}
