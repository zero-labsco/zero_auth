import 'auth_session.dart';

/// Login credentials.
/// 登录凭据。
final class Credentials {
  final String username;
  final String password;

  const Credentials({required this.username, required this.password});

  @override
  bool operator ==(Object other) =>
      other is Credentials &&
      other.username == username &&
      other.password == password;

  @override
  int get hashCode => Object.hash(username, password);
}

/// Registration input.
/// 注册输入。
final class RegistrationInput {
  final String username;
  final String password;
  final String? displayName;
  final String? email;

  const RegistrationInput({
    required this.username,
    required this.password,
    this.displayName,
    this.email,
  });

  @override
  bool operator ==(Object other) =>
      other is RegistrationInput &&
      other.username == username &&
      other.password == password &&
      other.displayName == displayName &&
      other.email == email;

  @override
  int get hashCode => Object.hash(username, password, displayName, email);
}

/// Backend boundary. Implement this to plug in any auth backend
/// (REST, gRPC, Firebase, your own RPC…).
/// 后端边界。实现它即可接入任意认证后端（REST、gRPC、Firebase、自有 RPC……）。
abstract class AuthStrategy {
  /// Authenticate and return a fresh session.
  /// 认证并返回全新会话。
  Future<AuthSession> login(Credentials credentials);

  /// Register a new account and return its first session.
  /// 注册新账户并返回首个会话。
  Future<AuthSession> register(RegistrationInput input);

  /// Invalidate the session on the backend.
  /// 在后端使会话失效。
  Future<void> logout(SessionHandle handle);

  /// Exchange a refresh token for a new session.
  /// 用刷新令牌换取新会话。
  Future<AuthSession> refresh(RefreshToken token);
}
