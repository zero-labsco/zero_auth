import 'package:zero_auth/zero_auth.dart';

/// A configurable in-test [AuthStrategy].
/// 测试用的可配置 [AuthStrategy]。
final class FakeAuthStrategy implements AuthStrategy {
  AuthSession? nextSession;
  Object? loginError;
  int refreshCount = 0;
  bool logoutCalled = false;

  FakeAuthStrategy({AuthSession? session})
    : nextSession = session ?? _default();

  static AuthSession _default() => const AuthSession(
    accessToken: 'access',
    refreshToken: RefreshToken('refresh'),
    userId: 'u1',
    displayName: 'User',
  );

  @override
  Future<AuthSession> login(Credentials credentials) async {
    if (loginError != null) throw loginError!;
    return nextSession!;
  }

  @override
  Future<AuthSession> register(RegistrationInput input) async => nextSession!;

  @override
  Future<void> logout(SessionHandle handle) async => logoutCalled = true;

  @override
  Future<AuthSession> refresh(RefreshToken token) async {
    refreshCount++;
    return nextSession!;
  }
}
