import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:zero_auth/zero_auth.dart';

import 'fake_strategy.dart';

/// A strategy whose [refresh] only resolves once [gate] completes, so tests can
/// land a refresh result *after* another operation has finished.
/// [refresh] 只在 [gate] 完成后才返回的策略，便于测试「刷新结果晚于其它操作返回」。
final class _GatedStrategy implements AuthStrategy {
  _GatedStrategy(this._session);

  final AuthSession _session;
  final Completer<AuthSession> gate = Completer<AuthSession>();

  @override
  Future<AuthSession> login(Credentials credentials) async => _session;

  @override
  Future<AuthSession> register(RegistrationInput input) async => _session;

  @override
  Future<void> logout(SessionHandle handle) async {}

  @override
  Future<AuthSession> refresh(RefreshToken token) => gate.future;
}

void main() {
  final fixedNow = DateTime.utc(2026, 1, 1, 12);
  final credentials = Credentials(username: 'a', password: 'b');

  AuthSession buildSession({
    String accessToken = 'access',
    bool expired = false,
    bool withRefresh = true,
    Duration ttl = const Duration(hours: 1),
  }) =>
      AuthSession(
        accessToken: accessToken,
        refreshToken: withRefresh ? const RefreshToken('refresh') : null,
        expiresAt: expired
            ? fixedNow.subtract(const Duration(minutes: 5))
            : fixedNow.add(ttl),
        userId: 'u1',
      );

  /// Lets pending microtasks settle so stream emissions become observable.
  /// 让挂起的微任务执行完，使状态流的新值可被观察。
  Future<void> pump([int times = 3]) async {
    for (var i = 0; i < times; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  group('AuthManager — refresh lifecycle', () {
    test(
      'emits Refreshing then Authenticated, and stays usable meanwhile',
      () async {
        final strategy = FakeAuthStrategy(session: buildSession());
        final manager = AuthManager(
          strategy: strategy,
          tokenStore: InMemoryTokenStore(),
          clock: () => fixedNow,
        );
        await manager.login(credentials);

        final states = <AuthState>[];
        final sub = manager.state.listen(states.add);
        await manager.refresh();
        await pump();

        expect(states.any((s) => s is Refreshing), isTrue);
        expect(states.last, isA<Authenticated>());
        expect(manager.current.isAuthenticated, isTrue);
        expect(manager.accessToken, 'access');
        await sub.cancel();
        await manager.dispose();
      },
    );

    test('a session stays available during Refreshing', () async {
      final strategy = _GatedStrategy(buildSession());
      final manager = AuthManager(strategy: strategy, clock: () => fixedNow);
      await manager.login(credentials);

      final refreshing = manager.refresh();
      await pump();

      expect(manager.current, isA<Refreshing>());
      expect(manager.current.isAuthenticated, isTrue);
      expect(manager.currentSession, isNotNull);
      expect(manager.accessToken, 'access');

      strategy.gate.complete(buildSession(accessToken: 'fresh'));
      await refreshing;
      await manager.dispose();
    });

    test('emits LoggingOut then Unauthenticated on logout', () async {
      final strategy = FakeAuthStrategy(session: buildSession());
      final manager = AuthManager(
        strategy: strategy,
        tokenStore: InMemoryTokenStore(),
        clock: () => fixedNow,
      );
      await manager.login(credentials);

      final states = <AuthState>[];
      final sub = manager.state.listen(states.add);
      await manager.logout();
      await pump();

      expect(states.any((s) => s is LoggingOut), isTrue);
      expect(states.last, const Unauthenticated());
      await sub.cancel();
      await manager.dispose();
    });
  });

  group('AuthManager — loginWith', () {
    test('adopts a session from an external flow', () async {
      final store = InMemoryTokenStore();
      final strategy = FakeAuthStrategy(session: buildSession());
      final manager = AuthManager(
        strategy: strategy,
        tokenStore: store,
        clock: () => fixedNow,
      );
      final external = buildSession(accessToken: 'oauth-token');

      final states = <AuthState>[];
      final sub = manager.state.listen(states.add);
      final result = await manager.loginWith((s) async => external);
      await pump();

      expect(result.session.accessToken, 'oauth-token');
      expect(manager.current, isA<Authenticated>());
      expect(manager.accessToken, 'oauth-token');
      expect(await store.load(), isNotNull);
      expect(states.any((s) => s is Authenticating), isTrue);
      await sub.cancel();
      await manager.dispose();
    });

    test('failure emits AuthError and rethrows', () async {
      final manager = AuthManager(
        strategy: FakeAuthStrategy(session: buildSession()),
        tokenStore: InMemoryTokenStore(),
        clock: () => fixedNow,
      );

      await expectLater(
        manager.loginWith((s) async => throw SessionExpiredException()),
        throwsA(isA<SessionExpiredException>()),
      );
      expect(manager.current, isA<AuthError>());
      await manager.dispose();
    });
  });

  group('AuthManager — refresh failure policy', () {
    test('default policy signs out when the grant is dead', () async {
      final store = InMemoryTokenStore();
      final strategy = FakeAuthStrategy(session: buildSession())
        ..refreshError = SessionExpiredException();
      final manager = AuthManager(
        strategy: strategy,
        tokenStore: store,
        clock: () => fixedNow,
      );
      await manager.login(credentials);

      await expectLater(
        manager.refresh(),
        throwsA(isA<SessionExpiredException>()),
      );
      await pump();

      expect(manager.current, const Unauthenticated());
      expect(manager.currentSession, isNull);
      expect(await store.load(), isNull);
      await manager.dispose();
    });

    test('default policy keeps the session on transient failures', () async {
      final store = InMemoryTokenStore();
      final strategy = FakeAuthStrategy(session: buildSession())
        ..refreshError = AuthException('offline', code: 'network_unreachable');
      final manager = AuthManager(
        strategy: strategy,
        tokenStore: store,
        clock: () => fixedNow,
      );
      await manager.login(credentials);

      await expectLater(manager.refresh(), throwsA(isA<AuthException>()));
      await pump();

      // The session survives so a later attempt can still succeed.
      // 会话被保留，稍后仍有机会重试成功。
      expect(manager.current, isA<Authenticated>());
      expect(manager.accessToken, 'access');
      expect(await store.load(), isNotNull);
      await manager.dispose();
    });

    test('a custom policy can override the decision', () async {
      final store = InMemoryTokenStore();
      final strategy = FakeAuthStrategy(session: buildSession())
        ..refreshError = SessionExpiredException();
      final manager = AuthManager(
        strategy: strategy,
        tokenStore: store,
        clock: () => fixedNow,
        refreshFailurePolicy: (error) => false,
      );
      await manager.login(credentials);

      await expectLater(manager.refresh(), throwsA(isA<AuthException>()));
      await pump();

      expect(manager.current, isA<Authenticated>());
      expect(await store.load(), isNotNull);
      await manager.dispose();
    });
  });

  group('AuthManager — restore', () {
    test('refreshes an expired persisted session', () async {
      final stale = buildSession(expired: true);
      final store = InMemoryTokenStore();
      await store.save(stale);
      final strategy = FakeAuthStrategy(session: stale)
        ..refreshedSession = buildSession(accessToken: 'fresh');
      final manager = AuthManager(
        strategy: strategy,
        tokenStore: store,
        clock: () => fixedNow,
      );

      await manager.restore();
      await pump();

      expect(manager.current, isA<Authenticated>());
      expect(manager.accessToken, 'fresh');
      expect(strategy.refreshCount, 1);
      await manager.dispose();
    });

    test('drops an expired session that has no refresh token', () async {
      final stale = buildSession(expired: true, withRefresh: false);
      final store = InMemoryTokenStore();
      await store.save(stale);
      final manager = AuthManager(
        strategy: FakeAuthStrategy(session: stale),
        tokenStore: store,
        clock: () => fixedNow,
      );

      await manager.restore();
      await pump();

      expect(manager.current, const Unauthenticated());
      expect(await store.load(), isNull);
      await manager.dispose();
    });

    test(
      'lands unauthenticated when refreshing an expired session fails',
      () async {
        final stale = buildSession(expired: true);
        final store = InMemoryTokenStore();
        await store.save(stale);
        final strategy = FakeAuthStrategy(session: stale)
          ..refreshError = SessionExpiredException();
        final manager = AuthManager(
          strategy: strategy,
          tokenStore: store,
          clock: () => fixedNow,
        );

        await manager.restore();
        await pump();

        expect(manager.current, const Unauthenticated());
        expect(await store.load(), isNull);
        await manager.dispose();
      },
    );

    test('refreshIfExpired: false keeps the session untouched', () async {
      final stale = buildSession(expired: true);
      final store = InMemoryTokenStore();
      await store.save(stale);
      final manager = AuthManager(
        strategy: FakeAuthStrategy(session: stale),
        tokenStore: store,
        clock: () => fixedNow,
      );

      await manager.restore(refreshIfExpired: false);
      await pump();

      expect(manager.current, isA<Authenticated>());
      expect(manager.accessToken, 'access');
      await manager.dispose();
    });
  });

  group('AuthManager — races', () {
    test(
      'a refresh landing after logout does not resurrect the session',
      () async {
        final strategy = _GatedStrategy(buildSession());
        final store = InMemoryTokenStore();
        final manager = AuthManager(
          strategy: strategy,
          tokenStore: store,
          clock: () => fixedNow,
        );
        await manager.login(credentials);

        Object? refreshFailure;
        final refreshing = manager.refresh();
        unawaited(
          refreshing.then<void>(
            (_) {},
            onError: (e) {
              refreshFailure = e;
            },
          ),
        );

        await manager.logout();
        strategy.gate.complete(buildSession(accessToken: 'late'));
        await pump();

        expect(refreshFailure, isA<AuthException>());
        expect(manager.current, const Unauthenticated());
        expect(manager.currentSession, isNull);
        expect(await store.load(), isNull);
        await manager.dispose();
      },
    );
  });

  group('AuthManager — proactive refresh', () {
    test('failures never leak an unhandled async error', () async {
      final errors = <Object>[];
      final zoneRun = runZonedGuarded<Future<void>>(
        () async {
          final strategy = FakeAuthStrategy(
            session: buildSession(ttl: Duration.zero),
          )..refreshError = SessionExpiredException();
          final manager = AuthManager(
            strategy: strategy,
            tokenStore: InMemoryTokenStore(),
            autoRefreshAhead: const Duration(minutes: 5),
            clock: () => fixedNow,
          );
          await manager.login(credentials);
          await pump();
          expect(manager.current, const Unauthenticated());
          await manager.dispose();
        },
        (error, stack) => errors.add(error),
      );
      await (zoneRun ?? Future<void>.value());
      expect(errors, isEmpty);
    });

    test('scheduling is driven by the injected clock', () {
      FakeAsync().run((async) {
        final strategy = FakeAuthStrategy(session: buildSession());
        final manager = AuthManager(
          strategy: strategy,
          tokenStore: InMemoryTokenStore(),
          autoRefreshAhead: const Duration(minutes: 5),
          clock: () => fixedNow,
        );

        unawaited(manager.login(credentials));
        async.flushMicrotasks();
        expect(strategy.refreshCount, 0);

        async.elapse(const Duration(minutes: 54));
        expect(strategy.refreshCount, 0);

        async.elapse(const Duration(minutes: 1));
        expect(strategy.refreshCount, 1);
        unawaited(manager.dispose());
      });
    });
  });

  group('AuthManager — validAccessToken', () {
    test('refreshes first when the token is expired', () async {
      final strategy = FakeAuthStrategy(session: buildSession(expired: true))
        ..refreshedSession = buildSession(accessToken: 'fresh');
      final manager = AuthManager(
        strategy: strategy,
        tokenStore: InMemoryTokenStore(),
        clock: () => fixedNow,
      );
      await manager.login(credentials);

      expect(await manager.validAccessToken(), 'fresh');
      expect(strategy.refreshCount, 1);
      await manager.dispose();
    });

    test('returns the current token when it is still valid', () async {
      final strategy = FakeAuthStrategy(session: buildSession());
      final manager = AuthManager(
        strategy: strategy,
        tokenStore: InMemoryTokenStore(),
        clock: () => fixedNow,
      );
      await manager.login(credentials);

      expect(await manager.validAccessToken(), 'access');
      expect(strategy.refreshCount, 0);
      await manager.dispose();
    });

    test('returns null when unauthenticated', () async {
      final manager = AuthManager(
        strategy: FakeAuthStrategy(session: buildSession()),
        clock: () => fixedNow,
      );
      expect(await manager.validAccessToken(), isNull);
      await manager.dispose();
    });
  });

  group('AuthManager — emission dedupe', () {
    test('suppresses consecutive duplicate states', () async {
      final manager = AuthManager(
        strategy: FakeAuthStrategy(session: buildSession()),
        tokenStore: InMemoryTokenStore(),
        clock: () => fixedNow,
      );
      final states = <AuthState>[];
      final sub = manager.state.listen(states.add);

      await manager.restore();
      await pump();

      // Only the replayed initial value; the "nothing persisted" emission is a
      // duplicate and therefore suppressed.
      // 只有重放的初始值；「无持久化会话」那次通知是重复值，因此被抑制。
      expect(states.length, 1);
      expect(states.single, const Unauthenticated());
      await sub.cancel();
      await manager.dispose();
    });
  });

  group('mapAuthFailure', () {
    test('maps invalid_credentials', () {
      final mapped = mapAuthFailure(
        AuthException('nope', code: 'invalid_credentials'),
      );
      expect(mapped, isA<InvalidCredentialsException>());
      expect(mapped.code, 'invalid_credentials');
    });

    test('maps every dead-grant code to SessionExpiredException', () {
      for (final code in const [
        'invalid_grant',
        'invalid_refresh_token',
        'token_expired',
        'session_expired',
      ]) {
        expect(
          mapAuthFailure(AuthException('x', code: code)),
          isA<SessionExpiredException>(),
        );
      }
    });

    test('preserves unrecognised strategy vocabulary', () {
      final original = AuthException('offline', code: 'network_unreachable');
      expect(mapAuthFailure(original), same(original));
    });

    test('wraps unknown throwables', () {
      final mapped = mapAuthFailure(StateError('boom'));
      expect(mapped, isA<UnexpectedAuthException>());
      expect(mapped.cause, isA<StateError>());
    });
  });
}
