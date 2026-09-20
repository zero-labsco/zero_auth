import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:zero_auth/zero_auth.dart';

import 'fake_strategy.dart';

/// A store that can fail on read or write, or delay its read.
final class _FlakyTokenStore implements TokenStore {
  _FlakyTokenStore({
    this.failLoad = false,
    this.failClear = false,
    this.loadDelay = Duration.zero,
  });

  final bool failLoad;
  final bool failClear;
  final Duration loadDelay;

  AuthSession? _session;

  @override
  Future<void> save(AuthSession session) async => _session = session;

  @override
  Future<AuthSession?> load() async {
    if (loadDelay > Duration.zero) await Future<void>.delayed(loadDelay);
    if (failLoad) throw StateError('store unavailable');
    return _session;
  }

  @override
  Future<void> clear() async {
    if (failClear) throw StateError('store unavailable');
    _session = null;
  }
}

/// A strategy whose login only resolves once [gate] completes.
final class _GatedLoginStrategy implements AuthStrategy {
  final Completer<AuthSession> gate = Completer<AuthSession>();
  int loginCalls = 0;

  @override
  Future<AuthSession> login(Credentials credentials) async {
    loginCalls++;
    return gate.future;
  }

  @override
  Future<AuthSession> register(RegistrationInput input) => gate.future;

  @override
  Future<void> logout(SessionHandle handle) async {}

  @override
  Future<AuthSession> refresh(RefreshToken token) => gate.future;
}

/// A strategy declaring an optional capability.
///
/// Composes [FakeAuthStrategy] rather than extending it — that test double is a
/// `final class`.
final class _ResettableStrategy implements AuthStrategy, SupportsPasswordReset {
  final FakeAuthStrategy _delegate = FakeAuthStrategy();

  String? resetRequestedFor;

  @override
  Future<void> requestPasswordReset(String identifier) async =>
      resetRequestedFor = identifier;

  @override
  Future<AuthSession> login(Credentials credentials) =>
      _delegate.login(credentials);

  @override
  Future<AuthSession> register(RegistrationInput input) =>
      _delegate.register(input);

  @override
  Future<void> logout(SessionHandle handle) => _delegate.logout(handle);

  @override
  Future<AuthSession> refresh(RefreshToken token) => _delegate.refresh(token);
}

void main() {
  final now = DateTime.utc(2026, 1, 1, 12);

  AuthSession session({
    String token = 'access',
    String name = 'user@demo',
    bool expired = false,
  }) =>
      AuthSession(
        accessToken: token,
        refreshToken: const RefreshToken('refresh'),
        expiresAt: expired
            ? now.subtract(const Duration(minutes: 1))
            : now.add(const Duration(minutes: 5)),
        userId: 'user',
        displayName: name,
      );

  group('restore hardening', () {
    test('a logout during restore does not resurrect the session', () async {
      final store =
          _FlakyTokenStore(loadDelay: const Duration(milliseconds: 20));
      await store.save(session());
      final manager = AuthManager(
        strategy: FakeAuthStrategy(session: session()),
        tokenStore: store,
        clock: () => now,
      );

      final restoring = manager.restore();
      await manager.logout();
      await restoring;
      await Future<void>.delayed(Duration.zero);

      expect(manager.current, const Unauthenticated());
      expect(manager.currentSession, isNull);
      await manager.dispose();
    });

    test('a store that cannot be read is treated as no session', () async {
      final manager = AuthManager(
        strategy: FakeAuthStrategy(session: session()),
        tokenStore: _FlakyTokenStore(failLoad: true),
        clock: () => now,
      );

      await expectLater(
        manager.restore(),
        throwsA(isA<UnexpectedAuthException>()),
      );
      expect(manager.current, const Unauthenticated());
      await manager.dispose();
    });

    test('dropping an unrenewable session reports why', () async {
      final store = _FlakyTokenStore();
      await store.save(session(expired: true));
      final manager = AuthManager(
        strategy: FakeAuthStrategy(session: session())
          ..refreshError = SessionExpiredException(),
        tokenStore: store,
        clock: () => now,
      );

      final states = <AuthState>[];
      final sub = manager.state.listen(states.add);
      await manager.restore();
      await Future<void>.delayed(Duration.zero);

      // AuthError first (so the UI knows why), then Unauthenticated.
      expect(states.any((s) => s is AuthError), isTrue);
      expect(states.last, const Unauthenticated());
      expect(await store.load(), isNull);

      await sub.cancel();
      await manager.dispose();
    });
  });

  group('logout hardening', () {
    test('local logout completes even when the store fails', () async {
      final manager = AuthManager(
        strategy: FakeAuthStrategy(session: session()),
        tokenStore: _FlakyTokenStore(failClear: true),
        clock: () => now,
      );
      await manager.login(
        const Credentials(username: 'user', password: 'user'),
      );

      await expectLater(
        manager.logout(),
        throwsA(isA<UnexpectedAuthException>()),
      );
      // The user is still signed out locally.
      expect(manager.current, const Unauthenticated());
      await manager.dispose();
    });
  });

  group('auth flow serialisation', () {
    test('overlapping logins are rejected', () async {
      final strategy = _GatedLoginStrategy();
      final manager = AuthManager(strategy: strategy, clock: () => now);

      final first = manager.login(
        const Credentials(username: 'user', password: 'user'),
      );
      await Future<void>.delayed(Duration.zero);

      await expectLater(
        manager.login(const Credentials(username: 'other', password: 'pw')),
        throwsA(
          isA<AuthException>().having(
            (e) => e.code,
            'code',
            'auth_flow_in_progress',
          ),
        ),
      );

      strategy.gate.complete(session());
      await first;
      expect(manager.current, isA<Authenticated>());
      await manager.dispose();
    });
  });

  group('disposed manager', () {
    test('operations are rejected instead of silently ignored', () async {
      final manager = AuthManager(
        strategy: FakeAuthStrategy(session: session()),
        clock: () => now,
      );
      await manager.dispose();

      await expectLater(
        manager.login(const Credentials(username: 'u', password: 'p')),
        throwsA(
          isA<AuthException>()
              .having((e) => e.code, 'code', 'manager_disposed'),
        ),
      );
      await expectLater(
        manager.restore(),
        throwsA(isA<AuthException>()),
      );
    });
  });

  group('session updates & capabilities', () {
    test('updateSession replaces the active session', () async {
      final store = _FlakyTokenStore();
      final manager = AuthManager(
        strategy: FakeAuthStrategy(session: session()),
        tokenStore: store,
        clock: () => now,
      );
      await manager.login(
        const Credentials(username: 'user', password: 'user'),
      );

      await manager.updateSession(
        (current) => AuthSession(
          accessToken: current.accessToken,
          refreshToken: current.refreshToken,
          expiresAt: current.expiresAt,
          userId: current.userId,
          displayName: 'Renamed User',
          claims: {'plan': 'pro'},
        ),
      );

      expect(manager.currentSession?.displayName, 'Renamed User');
      expect(manager.currentSession?.claims?['plan'], 'pro');
      expect((await store.load())?.displayName, 'Renamed User');
      await manager.dispose();
    });

    test('updateSession without a session throws', () async {
      final manager = AuthManager(
        strategy: FakeAuthStrategy(session: session()),
        clock: () => now,
      );
      await expectLater(
        manager.updateSession((c) => c),
        throwsA(isA<NoActiveSessionException>()),
      );
      await manager.dispose();
    });

    test('supports<T> detects optional capabilities', () async {
      final withCapability = AuthManager(
        strategy: _ResettableStrategy(),
        clock: () => now,
      );
      expect(withCapability.supports<SupportsPasswordReset>(), isTrue);
      expect(withCapability.supports<SupportsPasswordChange>(), isFalse);

      final strategy = withCapability.strategy as SupportsPasswordReset;
      await strategy.requestPasswordReset('user@example.com');
      expect(
        (strategy as _ResettableStrategy).resetRequestedFor,
        'user@example.com',
      );

      await withCapability.dispose();
    });
  });

  group('proactive refresh retry', () {
    test('a transient failure re-arms the renewal', () {
      FakeAsync().run((async) {
        final strategy = FakeAuthStrategy(session: session(expired: true))
          ..refreshError =
              AuthException('offline', code: 'network_unreachable');
        final manager = AuthManager(
          strategy: strategy,
          tokenStore: _FlakyTokenStore(),
          autoRefreshAhead: const Duration(minutes: 5),
          clock: () => now,
        );

        manager.login(const Credentials(username: 'user', password: 'user'));
        async.flushMicrotasks();
        // Already expired, so the renewal fires immediately and fails.
        expect(strategy.refreshCount, 1);

        async.elapse(const Duration(seconds: 30));
        expect(strategy.refreshCount, 2);

        unawaited(manager.dispose());
      });
    });
  });

  group('session equality', () {
    test('claims participate in equality', () {
      AuthSession build(Map<String, Object?>? claims) => AuthSession(
            accessToken: 'access',
            userId: 'user',
            claims: claims,
          );

      expect(build({'plan': 'pro'}), isNot(build({'plan': 'free'})));
      expect(build({'plan': 'pro'}), build({'plan': 'pro'}));
      expect(build(null), build(null));
      expect(build(null), isNot(build({'plan': 'pro'})));
    });
  });

  group('group lifecycle', () {
    test('addAccount and logoutAll', () async {
      final group = AuthManagerGroup(
        strategyFactory: (id) => FakeAuthStrategy(session: session()),
        storeFactory: (id) => _FlakyTokenStore(),
      );

      await group.addAccount('alice').login(
            const Credentials(username: 'alice', password: 'pw'),
          );
      await group.addAccount('bob').login(
            const Credentials(username: 'bob', password: 'pw'),
          );
      group.switchTo('bob');
      expect(group.accessToken, isNotNull);

      await group.logoutAll();

      expect(group.accountIds, isEmpty);
      expect(group.active, isNull);
      expect(group.accessToken, isNull);
      await group.disposeAll();
    });
  });
}
