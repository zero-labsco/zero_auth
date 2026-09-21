import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:zero_auth/zero_auth.dart';

/// In-memory store that also counts reads, so shared [AuthManager.restore]
/// attempts are observable.
final class _MemStore implements TokenStore {
  _MemStore([AuthSession? initial]) : value = initial;

  AuthSession? value;
  int loadCount = 0;

  @override
  Future<void> save(AuthSession session) async => value = session;

  @override
  Future<AuthSession?> load() async {
    loadCount++;
    return value;
  }

  @override
  Future<void> clear() async => value = null;
}

/// A store whose reads always fail.
final class _BrokenStore implements TokenStore {
  @override
  Future<void> save(AuthSession session) async {}

  @override
  Future<AuthSession?> load() async => throw StateError('store unavailable');

  @override
  Future<void> clear() async {}
}

/// Store that can fail on write or on clear, and counts writes so a test can let
/// the first `save` (login) succeed and break a later one.
final class _FailingStore implements TokenStore {
  _FailingStore({
    this.failSaveAfter = 0,
    this.failClear = false,
    AuthSession? initial,
  })  : value = initial,
        _allowedSaves = failSaveAfter;

  final int failSaveAfter;
  final bool failClear;
  final int _allowedSaves;

  AuthSession? value;
  int saveCount = 0;

  @override
  Future<void> save(AuthSession session) async {
    saveCount++;
    if (saveCount > _allowedSaves) throw StateError('write failed');
    value = session;
  }

  @override
  Future<AuthSession?> load() async => value;

  @override
  Future<void> clear() async {
    if (failClear) throw StateError('clear failed');
    value = null;
  }
}

/// Strategy whose [refresh] only resolves once [gate] completes.
final class _GatedStrategy implements AuthStrategy {
  _GatedStrategy({required this.gate, required this.refreshed});

  final Completer<AuthSession> gate;
  final AuthSession refreshed;
  int loginCount = 0;
  int refreshCount = 0;

  @override
  Future<AuthSession> login(Credentials credentials) async =>
      _session('login-${++loginCount}');

  @override
  Future<AuthSession> register(RegistrationInput input) async =>
      _session('register');

  @override
  Future<void> logout(SessionHandle handle) async {}

  @override
  Future<AuthSession> refresh(RefreshToken token) {
    refreshCount++;
    return gate.future;
  }
}

/// Strategy with fixed [session] / [refreshed] answers.
final class _FixedStrategy implements AuthStrategy {
  _FixedStrategy({required this.session, required this.refreshed});

  final AuthSession session;
  final AuthSession refreshed;
  int refreshCount = 0;

  @override
  Future<AuthSession> login(Credentials credentials) async => session;

  @override
  Future<AuthSession> register(RegistrationInput input) async => session;

  @override
  Future<void> logout(SessionHandle handle) async {}

  @override
  Future<AuthSession> refresh(RefreshToken token) async {
    refreshCount++;
    return refreshed;
  }
}

/// Strategy whose [refresh] always throws [error].
final class _FailingRefreshStrategy implements AuthStrategy {
  _FailingRefreshStrategy(this.error, {required this.session});

  final Object error;
  final AuthSession session;
  int refreshCount = 0;

  @override
  Future<AuthSession> login(Credentials credentials) async => session;

  @override
  Future<AuthSession> register(RegistrationInput input) async => session;

  @override
  Future<void> logout(SessionHandle handle) async {}

  @override
  Future<AuthSession> refresh(RefreshToken token) async {
    refreshCount++;
    throw error;
  }
}

/// Strategy with a real (wall-clock) short TTL, to prove the proactive scheduler
/// actually fires on a real [Timer] rather than only under `fake_async`.
final class _ShortTtlStrategy implements AuthStrategy {
  int refreshCount = 0;

  @override
  Future<AuthSession> login(Credentials credentials) async => _issue();

  @override
  Future<AuthSession> register(RegistrationInput input) async => _issue();

  @override
  Future<void> logout(SessionHandle handle) async {}

  @override
  Future<AuthSession> refresh(RefreshToken token) async {
    refreshCount++;
    return _issue();
  }

  AuthSession _issue() => AuthSession(
        accessToken: 'access-$refreshCount',
        refreshToken: const RefreshToken('refresh'),
        expiresAt: DateTime.now().add(const Duration(milliseconds: 300)),
      );
}

/// A strategy that keeps handing out sessions that are already due, to prove the
/// proactive scheduler throttles instead of spinning.
final class _ShortLivedStrategy implements AuthStrategy {
  _ShortLivedStrategy(this.clock);

  final DateTime Function() clock;
  int refreshCount = 0;

  @override
  Future<AuthSession> login(Credentials credentials) async => _issued();

  @override
  Future<AuthSession> register(RegistrationInput input) async => _issued();

  @override
  Future<void> logout(SessionHandle handle) async {}

  @override
  Future<AuthSession> refresh(RefreshToken token) async {
    refreshCount++;
    return _issued();
  }

  AuthSession _issued() => AuthSession(
        accessToken: 'access-$refreshCount',
        refreshToken: const RefreshToken('refresh'),
        expiresAt: clock().add(const Duration(seconds: 1)),
      );
}

final class _StaticTokenSource implements AuthTokenSource {
  @override
  String? get accessToken => 'static-token';

  // Implementations that only mirror a stored token simply forward the getter.
  // 只镜像已存令牌的实现，直接转发 getter 即可。
  @override
  Future<String?> validAccessToken({Duration? leeway}) async => accessToken;
}

AuthSession _session(
  String token, {
  DateTime? expiresAt,
  String? userId,
  String? displayName,
  Map<String, Object?>? claims,
}) =>
    AuthSession(
      accessToken: token,
      refreshToken: const RefreshToken('refresh'),
      expiresAt: expiresAt,
      userId: userId,
      displayName: displayName,
      claims: claims,
    );

const _credentials = Credentials(username: 'user', password: 'user');

void main() {
  final now = DateTime.utc(2026, 1, 1, 12);

  group('restore — transient renewal failures', () {
    test('keeps the persisted session when the renewal fails transiently',
        () async {
      final store = _MemStore(
        _session(
          'old',
          expiresAt: now.subtract(const Duration(minutes: 5)),
          userId: 'u1',
        ),
      );
      final manager = AuthManager(
        strategy: _FailingRefreshStrategy(
          AuthException('offline', code: 'network_unreachable'),
          session: _session('unused'),
        ),
        tokenStore: store,
        clock: () => now,
      );

      await manager.restore();

      // The whole point of the failure policy: a transient error must not
      // destroy a session that a later attempt could still renew.
      expect(store.value, isNotNull);
      expect(manager.currentSession?.accessToken, 'old');
      expect(manager.current, isA<Authenticated>());
    });

    test('still clears the session when the failure is terminal', () async {
      final store = _MemStore(
        _session('old', expiresAt: now.subtract(const Duration(minutes: 5))),
      );
      final manager = AuthManager(
        strategy: _FailingRefreshStrategy(
          SessionExpiredException(),
          session: _session('unused'),
        ),
        tokenStore: store,
        clock: () => now,
      );

      await manager.restore();

      expect(store.value, isNull);
      expect(manager.current, isA<Unauthenticated>());
    });

    test('concurrent calls share a single attempt', () async {
      final store = _MemStore(
        _session('stored', expiresAt: now.add(const Duration(minutes: 5))),
      );
      final manager = AuthManager(
        strategy: _FixedStrategy(
          session: _session('a'),
          refreshed: _session('b'),
        ),
        tokenStore: store,
        clock: () => now,
      );

      await Future.wait<void>([manager.restore(), manager.restore()]);

      expect(store.loadCount, 1);
    });

    test('re-arms proactive renewal when it is configured', () {
      FakeAsync().run((async) {
        final strategy = _FailingRefreshStrategy(
          AuthException('offline', code: 'network_unreachable'),
          session: _session('unused'),
        );
        final store = _MemStore(
          _session('old', expiresAt: now.subtract(const Duration(minutes: 5))),
        );
        final manager = AuthManager(
          strategy: strategy,
          tokenStore: store,
          clock: () => now,
          autoRefreshAhead: const Duration(minutes: 5),
        );

        unawaited(manager.restore());
        async.flushMicrotasks();
        expect(store.value, isNotNull);
        expect(strategy.refreshCount, 1);

        // The renewal is not retried immediately, but it is not abandoned either.
        // 续期不会立刻重试，但也没有被放弃。
        async.elapse(const Duration(seconds: 30));
        expect(strategy.refreshCount, 2);

        unawaited(manager.dispose());
      });
    });
  });

  group('storage failures', () {
    test('a store that cannot be cleared still settles the refresh', () async {
      final manager = AuthManager(
        strategy: _FailingRefreshStrategy(
          SessionExpiredException(),
          session: _session('a'),
        ),
        tokenStore: _FailingStore(failClear: true, failSaveAfter: 1),
        clock: () => now,
      );

      await manager.login(_credentials);

      // Would hang (or leak an unhandled async error) if the failing `clear()`
      // escaped before the completer was settled.
      // 若失败的 `clear()` 在 completer 落定之前逃逸，这里会挂住（或泄漏未处理的
      // 异步错误）。
      await expectLater(manager.refresh(), throwsA(isA<AuthException>()));
      expect(manager.current, isA<Unauthenticated>());
    });

    test('a store that cannot save surfaces an AppException', () async {
      final manager = AuthManager(
        strategy: _FixedStrategy(
          session: _session('a'),
          refreshed: _session('b'),
        ),
        tokenStore: _FailingStore(failSaveAfter: 1),
        clock: () => now,
      );

      await manager.login(_credentials);

      await expectLater(
        manager.updateSession((s) => s.copyWith(displayName: 'Renamed')),
        throwsA(isA<UnexpectedAuthException>()),
      );
    });
  });

  group('a stale refresh can never win', () {
    test('a refresh in flight does not overwrite a newer login', () async {
      final gate = Completer<AuthSession>();
      final strategy =
          _GatedStrategy(gate: gate, refreshed: _session('refreshed'));
      final store = _MemStore();
      final manager = AuthManager(
        strategy: strategy,
        tokenStore: store,
        clock: () => now,
      );

      await manager.login(_credentials);
      final refresh = manager.refresh();
      await manager.login(_credentials);

      gate.complete(_session('refreshed'));

      await expectLater(refresh, throwsA(isA<NoActiveSessionException>()));
      expect(manager.currentSession?.accessToken, 'login-2');
      expect(store.value?.accessToken, 'login-2');
    });

    test('a refresh in flight does not overwrite an updated session', () async {
      final gate = Completer<AuthSession>();
      final strategy =
          _GatedStrategy(gate: gate, refreshed: _session('refreshed'));
      final store = _MemStore();
      final manager = AuthManager(
        strategy: strategy,
        tokenStore: store,
        clock: () => now,
      );

      await manager.login(_credentials);
      final refresh = manager.refresh();
      await manager.updateSession(
        (current) => current.copyWith(displayName: 'Renamed'),
      );

      gate.complete(_session('refreshed'));

      await expectLater(refresh, throwsA(isA<NoActiveSessionException>()));
      expect(manager.currentSession?.displayName, 'Renamed');
      expect(manager.currentSession?.accessToken, 'login-1');
    });

    test('a new refresh does not join one started in a previous epoch',
        () async {
      final gate = Completer<AuthSession>();
      final strategy =
          _GatedStrategy(gate: gate, refreshed: _session('refreshed'));
      final manager = AuthManager(
        strategy: strategy,
        tokenStore: _MemStore(),
        clock: () => now,
      );

      await manager.login(_credentials);
      final first = manager.refresh();
      // The login invalidates the first attempt; a fresh one must start instead
      // of joining it.
      await manager.login(_credentials);
      final second = manager.refresh();
      expect(strategy.refreshCount, 2);

      gate.complete(_session('refreshed'));
      await expectLater(first, throwsA(isA<NoActiveSessionException>()));
      expect(await second, isA<AuthSession>());
    });
  });

  group('refresh keeps the signed-in identity', () {
    test('identity survives a renewal that only returns tokens', () async {
      final manager = AuthManager(
        strategy: _FixedStrategy(
          session: _session(
            'a',
            userId: 'u1',
            displayName: 'Ada',
            claims: {'plan': 'pro'},
          ),
          refreshed: _session('b'),
        ),
        tokenStore: _MemStore(),
        clock: () => now,
      );

      await manager.login(_credentials);
      await manager.refresh();

      expect(manager.currentSession!.userId, 'u1');
      expect(manager.currentSession!.displayName, 'Ada');
      expect(manager.currentSession!.claims, {'plan': 'pro'});
    });

    test('preserveSessionDetails: false keeps the backend answer verbatim',
        () async {
      final manager = AuthManager(
        strategy: _FixedStrategy(
          session: _session('a', userId: 'u1', displayName: 'Ada'),
          refreshed: _session('b'),
        ),
        tokenStore: _MemStore(),
        clock: () => now,
        preserveSessionDetails: false,
      );

      await manager.login(_credentials);
      await manager.refresh();

      expect(manager.currentSession!.userId, isNull);
      expect(manager.currentSession!.displayName, isNull);
    });
  });

  group('clock skew', () {
    test('renews a token that would expire in flight', () async {
      final manager = AuthManager(
        strategy: _FixedStrategy(
          session:
              _session('a', expiresAt: now.add(const Duration(seconds: 10))),
          refreshed: _session(
            'b',
            expiresAt: now.add(const Duration(minutes: 5)),
          ),
        ),
        tokenStore: _MemStore(),
        clock: () => now,
        clockSkew: const Duration(seconds: 30),
      );

      await manager.login(_credentials);

      // 10s left is less than the 30s skew, so the token is renewed first.
      expect(await manager.validAccessToken(), 'b');
    });

    test('validAccessToken(leeway:) overrides the manager default', () async {
      final manager = AuthManager(
        strategy: _FixedStrategy(
          session:
              _session('a', expiresAt: now.add(const Duration(seconds: 10))),
          refreshed: _session(
            'b',
            expiresAt: now.add(const Duration(minutes: 5)),
          ),
        ),
        tokenStore: _MemStore(),
        clock: () => now,
        clockSkew: Duration.zero,
      );

      await manager.login(_credentials);

      expect(await manager.validAccessToken(), 'a');
      expect(
        await manager.validAccessToken(leeway: const Duration(seconds: 30)),
        'b',
      );
    });
  });

  group('proactive renewal throttling', () {
    test('an always-due session is throttled instead of spinning', () {
      FakeAsync().run((async) {
        final strategy = _ShortLivedStrategy(() => now);
        final manager = AuthManager(
          strategy: strategy,
          tokenStore: _MemStore(),
          autoRefreshAhead: const Duration(minutes: 5),
          clock: () => now,
        );

        unawaited(manager.login(_credentials));
        async.flushMicrotasks();
        // Already due, so the first renewal is immediate…
        expect(strategy.refreshCount, 1);

        // …but the next one waits for `autoRefreshMinInterval`.
        async.elapse(const Duration(seconds: 4));
        expect(strategy.refreshCount, 1);
        async.elapse(const Duration(seconds: 2));
        expect(strategy.refreshCount, 2);

        unawaited(manager.dispose());
      });
    });
  });

  group('AuthSession serialization', () {
    test('tryFromJson returns null instead of throwing on bad input', () {
      expect(AuthSession.tryFromJson({'accessToken': 'a'}), isA<AuthSession>());
      expect(AuthSession.tryFromJson(null), isNull);
      expect(AuthSession.tryFromJson({'nope': true}), isNull);
      expect(AuthSession.tryFromJson({'accessToken': 42}), isNull);
      expect(
        AuthSession.tryFromJson({'accessToken': 'a', 'expiresAt': 'yesterday'}),
        isNull,
      );
      expect(
        AuthSession.tryFromJson({'accessToken': 'a', 'claims': 'nope'}),
        isNull,
      );
    });

    test('tryFromJson round-trips a serialized session', () {
      final session = _session(
        'a',
        expiresAt: now,
        userId: 'u1',
        displayName: 'Ada',
        claims: {'plan': 'pro'},
      );

      expect(AuthSession.tryFromJson(session.toJson()), session);
    });

    test('nested claims compare and hash by content', () {
      final a = _session(
        'a',
        claims: {
          'roles': ['admin', 'owner'],
        },
      );
      final same = _session(
        'a',
        claims: {
          'roles': ['admin', 'owner'],
        },
      );
      final different = _session(
        'a',
        claims: {
          'roles': ['admin'],
        },
      );

      expect(a, same);
      expect(a.hashCode, same.hashCode);
      expect(a, isNot(different));
    });
  });

  group('AuthState.session', () {
    test('exposes the session of every state that carries one', () {
      final session = _session('a');

      expect(const Unauthenticated().session, isNull);
      expect(const Authenticating().session, isNull);
      expect(Authenticated(session).session, session);
      expect(Refreshing(session).session, session);
      expect(LoggingOut(session).session, session);
      expect(AuthError(SessionExpiredException()).session, isNull);
    });
  });

  group('AuthTokenSource', () {
    test('a plain source falls back to accessToken', () async {
      expect(await _StaticTokenSource().validAccessToken(), 'static-token');
    });

    test('a manager-backed source renews first', () async {
      final manager = AuthManager(
        strategy: _FixedStrategy(
          session: _session(
            'a',
            expiresAt: now.subtract(const Duration(minutes: 1)),
          ),
          refreshed:
              _session('b', expiresAt: now.add(const Duration(minutes: 5))),
        ),
        tokenStore: _MemStore(),
        clock: () => now,
      );
      await manager.login(_credentials);

      final AuthTokenSource source = manager;
      expect(await source.validAccessToken(), 'b');
    });
  });

  group('mapAuthFailure', () {
    test('reads the code of a bare AuthFail', () {
      expect(
        mapAuthFailure(const AuthFail('nope', code: 'invalid_credentials')),
        isA<InvalidCredentialsException>(),
      );
      expect(
        mapAuthFailure(const AuthFail('gone', code: 'invalid_grant')),
        isA<SessionExpiredException>(),
      );
      expect(
        mapAuthFailure(const AuthFail('gone', code: 'token_expired')),
        isA<SessionExpiredException>(),
      );
    });

    test('preserves the message and cause of a bare AuthFail', () {
      final cause = StateError('boom');
      final mapped = mapAuthFailure(
        AuthFail('bad password', code: 'invalid_credentials', cause: cause),
      );

      expect(mapped.message, 'bad password');
      expect(mapped.cause, cause);
    });

    test('still wraps anything it cannot classify', () {
      expect(
        mapAuthFailure(StateError('boom')),
        isA<UnexpectedAuthException>(),
      );
    });
  });

  group('observers', () {
    test('a throwing onStateChanged never breaks the flow', () async {
      final seen = <AuthState>[];
      final manager = AuthManager(
        strategy: _FixedStrategy(
          session: _session('a'),
          refreshed: _session('b'),
        ),
        tokenStore: _MemStore(),
        clock: () => now,
        onStateChanged: (state) {
          seen.add(state);
          throw StateError('observer blew up');
        },
      );

      // The observer is a side channel: the machine still reaches Authenticated.
      // 观察者只是旁路：状态机依然走到了 Authenticated。
      await manager.login(_credentials);

      expect(manager.current, isA<Authenticated>());
      expect(seen, isNotEmpty);
      expect(await manager.validAccessToken(), 'a');
    });
  });

  group('real timers', () {
    test('proactive renewal fires on a real timer', () async {
      final strategy = _ShortTtlStrategy();
      final manager = AuthManager(
        strategy: strategy,
        tokenStore: _MemStore(),
        autoRefreshAhead: const Duration(milliseconds: 100),
        clockSkew: Duration.zero,
        autoRefreshMinInterval: const Duration(milliseconds: 40),
      );

      await manager.login(_credentials);
      // 300ms TTL − 100ms lead ⇒ scheduled, not immediate.
      // 300 毫秒寿命 − 100 毫秒提前量 ⇒ 走排程，而非立即刷新。
      expect(strategy.refreshCount, 0);

      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(strategy.refreshCount, greaterThanOrEqualTo(1));

      await manager.dispose();
    });
  });

  group('AuthManagerGroup configuration', () {
    test('forwards the tuning knobs to every account', () async {
      final seen = <String>[];
      final group = AuthManagerGroup(
        strategyFactory: (id) => _FixedStrategy(
          session: _session('a-$id'),
          refreshed: _session('b-$id'),
        ),
        storeFactory: (id) => _MemStore(),
        clock: () => now,
        clockSkew: const Duration(seconds: 30),
        autoRefreshAhead: const Duration(minutes: 2),
        onStateChanged: (id, state) => seen.add('$id:${state.runtimeType}'),
      );

      final manager = group.addAccount('alice');
      expect(manager.clockSkew, const Duration(seconds: 30));

      await manager.login(_credentials);
      expect(seen, contains('alice:Authenticated'));

      await group.disposeAll();
    });

    test('managerFactory wins over the individual knobs', () async {
      final strategy = _FixedStrategy(
        session: _session('a'),
        refreshed: _session('b'),
      );
      AuthManager? built;
      final group = AuthManagerGroup(
        strategyFactory: (id) => strategy,
        storeFactory: (id) => _MemStore(),
        managerFactory: (id, s, store) {
          built = AuthManager(strategy: s, tokenStore: store);
          return built!;
        },
      );

      expect(identical(group.addAccount('alice'), built), isTrue);
      await group.disposeAll();
    });

    test('activeIdChanges mirrors the active account', () async {
      final group = AuthManagerGroup(
        strategyFactory: (id) => _FixedStrategy(
          session: _session('a-$id'),
          refreshed: _session('b-$id'),
        ),
        storeFactory: (id) => _MemStore(),
      );
      final seen = <String?>[];
      final subscription = group.activeIdChanges.listen(seen.add);

      group.switchTo('alice');
      await Future<void>.delayed(Duration.zero);
      expect(seen, ['alice']);

      await group.remove('alice');
      await Future<void>.delayed(Duration.zero);
      expect(seen, ['alice', null]);

      await subscription.cancel();
      await group.disposeAll();
    });

    test('a manager disposed outside the group is forgotten', () async {
      final group = AuthManagerGroup(
        strategyFactory: (id) => _FixedStrategy(
          session: _session('a-$id'),
          refreshed: _session('b-$id'),
        ),
        storeFactory: (id) => _MemStore(),
      );
      final manager = group.addAccount('alice');
      await manager.login(_credentials);
      group.switchTo('alice');
      await Future<void>.delayed(Duration.zero);

      // Bypassing the group: it must not keep pointing at a released manager.
      // 绕过分组释放：分组不能继续指向一个已释放的管理器。
      await manager.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(group.activeId, isNull);
      expect(group.accountIds, isEmpty);
      expect(group.current, isA<Unauthenticated>());

      await group.disposeAll();
    });

    test('restoreAll keeps going when one account fails', () async {
      final group = AuthManagerGroup(
        strategyFactory: (id) => _FixedStrategy(
          session: _session('a-$id'),
          refreshed: _session('b-$id'),
        ),
        storeFactory: (id) => id == 'broken' ? _BrokenStore() : _MemStore(),
      );

      await expectLater(
        group.restoreAll(['broken', 'ok']),
        throwsA(isA<AuthException>()),
      );

      expect(group.accountIds, contains('ok'));
      await group.disposeAll();
    });
  });
}
