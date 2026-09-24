import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:zero_auth/zero_auth.dart';

import 'fake_strategy.dart';

/// A strategy whose [refresh] returns a session with a freshly extended expiry,
/// so proactive refresh does not re-trigger immediately.
/// 一个刷新会返回「过期时间已顺延」会话的策略，避免主动刷新立即重复触发。
final class ExtendingAuthStrategy implements AuthStrategy {
  int refreshCount = 0;

  AuthSession _session(DateTime expiresAt) => AuthSession(
        accessToken: 'access',
        refreshToken: const RefreshToken('refresh'),
        expiresAt: expiresAt,
        userId: 'u1',
      );

  @override
  Future<AuthSession> login(Credentials credentials) async =>
      _session(DateTime.now().add(const Duration(hours: 1)));

  @override
  Future<AuthSession> register(RegistrationInput input) async =>
      _session(DateTime.now().add(const Duration(hours: 1)));

  @override
  Future<void> logout(SessionHandle handle) async {}

  @override
  Future<AuthSession> refresh(RefreshToken token) async {
    refreshCount++;
    return _session(DateTime.now().add(const Duration(hours: 1)));
  }
}

void main() {
  group('AuthManager — construction', () {
    test('starts unauthenticated', () {
      final manager = AuthManager(strategy: FakeAuthStrategy());
      expect(manager.current, const Unauthenticated());
      expect(manager.currentSession, isNull);
      expect(manager.accessToken, isNull);
    });
  });

  group('AuthManager — state stream', () {
    test('replays the last value to new listeners', () async {
      final manager = AuthManager(strategy: FakeAuthStrategy());
      final first = <AuthState>[];
      final sub = manager.state.listen(first.add);
      await manager.login(const Credentials(username: 'a', password: 'b'));

      final second = <AuthState>[];
      final sub2 = manager.state.listen(second.add);
      await Future<void>.delayed(Duration.zero);

      expect(second.first, isA<Authenticated>());
      await sub.cancel();
      await sub2.cancel();
    });
  });

  group('AuthManager — login', () {
    test(
      'emits Authenticating then Authenticated and saves the session',
      () async {
        final store = InMemoryTokenStore();
        final manager = AuthManager(
          strategy: FakeAuthStrategy(),
          tokenStore: store,
        );
        final states = <AuthState>[];
        final sub = manager.state.listen(states.add);

        await manager.login(const Credentials(username: 'a', password: 'b'));
        await Future<void>.delayed(Duration.zero);

        expect(manager.current, isA<Authenticated>());
        expect(manager.currentSession, isNotNull);
        expect(manager.accessToken, 'access');
        expect(await store.load(), isNotNull);
        expect(states, contains(isA<Authenticating>()));
        expect(states.last, isA<Authenticated>());
        await sub.cancel();
      },
    );

    test('failure emits AuthError and throws', () async {
      final strategy = FakeAuthStrategy()
        ..loginError = AuthException('bad', code: 'bad_creds');
      final manager = AuthManager(strategy: strategy);
      final states = <AuthState>[];
      final sub = manager.state.listen(states.add);

      expect(
        () => manager.login(const Credentials(username: 'a', password: 'b')),
        throwsA(isA<AuthException>()),
      );
      await Future<void>.delayed(Duration.zero);

      expect(states, contains(isA<Authenticating>()));
      expect(states.last, isA<AuthError>());
      expect(manager.current, isA<AuthError>());
      await sub.cancel();
    });
  });

  group('AuthManager — logout', () {
    test(
      'clears the store, calls the strategy, emits Unauthenticated',
      () async {
        final strategy = FakeAuthStrategy();
        final store = InMemoryTokenStore();
        final manager = AuthManager(strategy: strategy, tokenStore: store);

        await manager.login(const Credentials(username: 'a', password: 'b'));
        await manager.logout();

        expect(manager.current, const Unauthenticated());
        expect(manager.currentSession, isNull);
        expect(strategy.logoutCalled, isTrue);
        expect(await store.load(), isNull);
      },
    );
  });

  group('AuthManager — restore', () {
    test('loads a persisted session', () async {
      final store = InMemoryTokenStore();
      await store.save(const AuthSession(accessToken: 'a', userId: 'u'));
      final manager = AuthManager(
        strategy: FakeAuthStrategy(),
        tokenStore: store,
      );

      await manager.restore();
      expect(manager.current, isA<Authenticated>());
    });

    test('stays unauthenticated when nothing is persisted', () async {
      final manager = AuthManager(strategy: FakeAuthStrategy());
      await manager.restore();
      expect(manager.current, const Unauthenticated());
    });
  });

  group('AuthManager — refresh (single-flight)', () {
    test('concurrent refreshes call the backend once', () async {
      final strategy = FakeAuthStrategy();
      final manager = AuthManager(strategy: strategy);
      await manager.login(const Credentials(username: 'a', password: 'b'));

      final f1 = manager.refresh();
      final f2 = manager.refresh();
      await Future.wait([f1, f2]);

      expect(strategy.refreshCount, 1);
    });

    test('throws without a session', () async {
      final manager = AuthManager(strategy: FakeAuthStrategy());
      // Wrapped in a closure: `refresh()` rejects synchronous pre-conditions
      // (no session, no refresh token, disposed) by throwing, not by returning
      // a failed Future.
      expect(() => manager.refresh(), throwsA(isA<NoActiveSessionException>()));
    });

    test('throws synchronously when the session has no refresh token',
        () async {
      final manager = AuthManager(
        strategy: FakeAuthStrategy(
          session: const AuthSession(accessToken: 'access-only'),
        ),
      );
      await manager.login(const Credentials(username: 'a', password: 'b'));

      expect(
        () => manager.refresh(),
        throwsA(isA<RefreshTokenMissingException>()),
      );
    });
  });

  group('AuthManager — auto refresh', () {
    test('refreshes proactively ahead of expiry', () {
      FakeAsync().run((async) {
        final strategy = ExtendingAuthStrategy();
        final manager = AuthManager(
          strategy: strategy,
          autoRefreshAhead: const Duration(minutes: 5),
        );

        manager.login(const Credentials(username: 'a', password: 'b'));
        async.flushMicrotasks();
        expect(strategy.refreshCount, 0);

        // Advance to 5 minutes before the 1-hour expiry; the timer fires once.
        async.elapse(const Duration(minutes: 55));
        expect(strategy.refreshCount, 1);
      });
    });

    test('does not schedule when autoRefreshAhead is null', () {
      FakeAsync().run((async) {
        final strategy = ExtendingAuthStrategy();
        final manager = AuthManager(strategy: strategy);

        manager.login(const Credentials(username: 'a', password: 'b'));
        async.flushMicrotasks();
        async.elapse(const Duration(hours: 2));
        expect(strategy.refreshCount, 0);
      });
    });

    test('does not schedule without a refresh token', () {
      FakeAsync().run((async) {
        final strategy = FakeAuthStrategy(
          session: const AuthSession(
            accessToken: 'access',
            userId: 'u1',
            expiresAt: null,
          ),
        );
        final manager = AuthManager(
          strategy: strategy,
          autoRefreshAhead: const Duration(minutes: 5),
        );

        manager.login(const Credentials(username: 'a', password: 'b'));
        async.flushMicrotasks();
        async.elapse(const Duration(hours: 2));
        expect(strategy.refreshCount, 0);
      });
    });
  });

  group('AuthException', () {
    test('fromFail preserves code and cause', () {
      const fail = AuthFail('m', code: 'c', cause: 'k');
      final e = AuthException.fromFail(fail);
      expect(e.message, 'm');
      expect(e.code, 'c');
      expect(e.cause, 'k');
      expect(e.fail, fail);
    });
  });
}
