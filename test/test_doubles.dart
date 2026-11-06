import 'dart:async';

import 'package:zero_auth/zero_auth.dart';

/// Shared constants and test doubles for manager-level regression tests.
/// 管理器级回归测试共用的常量与测试替身。

const testCredentials = Credentials(username: 'a', password: 'b');
const testRegistration = RegistrationInput(username: 'a', password: 'b');

AuthSession testSession([String token = 'access']) => AuthSession(
      accessToken: token,
      refreshToken: RefreshToken('$token-refresh'),
      userId: 'u1',
      displayName: 'User',
    );

/// A strategy whose four methods can be replaced per test.
/// 四个方法均可按用例替换的策略。
final class FnStrategy implements AuthStrategy {
  FnStrategy({
    Future<AuthSession> Function(Credentials)? loginFn,
    Future<AuthSession> Function(RegistrationInput)? registerFn,
    Future<void> Function(SessionHandle)? logoutFn,
    Future<AuthSession> Function(RefreshToken)? refreshFn,
  })  : _loginFn = loginFn,
        _registerFn = registerFn,
        _logoutFn = logoutFn,
        _refreshFn = refreshFn;

  final Future<AuthSession> Function(Credentials)? _loginFn;
  final Future<AuthSession> Function(RegistrationInput)? _registerFn;
  final Future<void> Function(SessionHandle)? _logoutFn;
  final Future<AuthSession> Function(RefreshToken)? _refreshFn;

  @override
  Future<AuthSession> login(Credentials credentials) async =>
      _loginFn == null ? testSession() : _loginFn(credentials);

  @override
  Future<AuthSession> register(RegistrationInput input) async =>
      _registerFn == null ? testSession() : _registerFn(input);

  @override
  Future<void> logout(SessionHandle handle) async => _logoutFn?.call(handle);

  @override
  Future<AuthSession> refresh(RefreshToken token) async =>
      _refreshFn == null ? testSession('renewed') : _refreshFn(token);
}

/// A store whose `save` can be frozen mid-write so a logout can be interleaved.
/// 可把 `save` 冻结在写入途中的存储，用于在持久化窗口插入 logout。
final class BlockingStore implements TokenStore {
  bool blocking = false;
  final Completer<void> saveStarted = Completer<void>();
  final Completer<void> saveGate = Completer<void>();
  AuthSession? stored;

  @override
  Future<void> save(AuthSession session) async {
    stored = session;
    if (blocking) {
      if (!saveStarted.isCompleted) saveStarted.complete();
      await saveGate.future;
    }
  }

  @override
  Future<AuthSession?> load() async => stored;

  @override
  Future<void> clear() async {
    stored = null;
  }
}

/// A store that cannot be read, for group-level failure aggregation.
/// 无法读取的存储，用于分组失败聚合。
final class BrokenStore implements TokenStore {
  @override
  Future<void> save(AuthSession session) async {}

  @override
  Future<AuthSession?> load() async => throw StateError('unreadable');

  @override
  Future<void> clear() async {}
}

/// A store that cannot be cleared, and whose persisted session is already
/// expired with no refresh token (the `_dropSession` shape).
/// 无法清空的存储，且其持久化会话已过期、无刷新令牌（`_dropSession` 形状）。
final class FailingClearStore implements TokenStore {
  AuthSession? stored;

  @override
  Future<void> save(AuthSession session) async {
    stored = session;
  }

  @override
  Future<AuthSession?> load() async =>
      stored ??
      AuthSession(
        accessToken: 'old',
        userId: 'u1',
        expiresAt: DateTime.utc(2000),
      );

  @override
  Future<void> clear() async => throw StateError('disk full');
}
