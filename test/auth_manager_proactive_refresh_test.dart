import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:zero_auth/zero_auth.dart';

import 'test_doubles.dart';

/// A strategy handing out one-hour tokens, for timer-driven tests.
/// 签发一小时令牌的策略，用于定时器驱动测试。
final class _TimerStrategy implements AuthStrategy {
  int refreshCount = 0;

  AuthSession _timed([String token = 'access']) => AuthSession(
        accessToken: token,
        refreshToken: RefreshToken('$token-refresh'),
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

  @override
  Future<AuthSession> login(Credentials credentials) async => _timed();

  @override
  Future<AuthSession> register(RegistrationInput input) async => _timed();

  @override
  Future<void> logout(SessionHandle handle) async {}

  @override
  Future<AuthSession> refresh(RefreshToken token) async {
    refreshCount++;
    return _timed('renewed-$refreshCount');
  }
}

/// A strategy issuing very short-lived tokens, for the effective-skew schedule.
/// 签发极短寿命令牌的策略，用于验证排程使用有效容差。
final class _ShortTtlStrategy implements AuthStrategy {
  int refreshCount = 0;

  AuthSession _short() => AuthSession(
        accessToken: 'short',
        refreshToken: const RefreshToken('short-refresh'),
        expiresAt: DateTime.now().add(const Duration(seconds: 10)),
      );

  @override
  Future<AuthSession> login(Credentials credentials) async => _short();

  @override
  Future<AuthSession> register(RegistrationInput input) async => _short();

  @override
  Future<void> logout(SessionHandle handle) async {}

  @override
  Future<AuthSession> refresh(RefreshToken token) async {
    refreshCount++;
    return _short();
  }
}

void main() {
  group('AuthManager — proactive refresh scheduling', () {
    test('dispose cancels a scheduled proactive renewal', () {
      FakeAsync().run((async) {
        final strategy = _TimerStrategy();
        final manager = AuthManager(
          strategy: strategy,
          autoRefreshAhead: const Duration(minutes: 5),
        );
        unawaited(manager.login(testCredentials));
        async.flushMicrotasks();
        expect(strategy.refreshCount, 0);
        unawaited(manager.dispose());
        async.elapse(const Duration(hours: 2));
        expect(strategy.refreshCount, 0);
      });
    });

    test('logout cancels a scheduled proactive renewal', () {
      FakeAsync().run((async) {
        final strategy = _TimerStrategy();
        final manager = AuthManager(
          strategy: strategy,
          autoRefreshAhead: const Duration(minutes: 5),
        );
        unawaited(manager.login(testCredentials));
        async.flushMicrotasks();
        unawaited(manager.logout());
        async.flushMicrotasks();
        async.elapse(const Duration(hours: 2));
        expect(strategy.refreshCount, 0);
      });
    });

    test('the proactive schedule uses the effective (capped) skew', () {
      FakeAsync().run((async) {
        final strategy = _ShortTtlStrategy();
        final manager = AuthManager(
          strategy: strategy,
          autoRefreshAhead: const Duration(seconds: 1),
          autoRefreshMinInterval: Duration.zero,
          clockSkew: const Duration(seconds: 30),
          clockSkewFraction: 0.25,
        );
        unawaited(manager.login(testCredentials));
        async.flushMicrotasks();
        // 10s lifetime, 1s ahead, 30s skew capped to 2.5s -> fires at 6.5s.
        async.elapse(const Duration(seconds: 6));
        expect(strategy.refreshCount, 0);
        async.elapse(const Duration(milliseconds: 500));
        expect(strategy.refreshCount, 1);
        unawaited(manager.dispose());
      });
    });
  });
}
