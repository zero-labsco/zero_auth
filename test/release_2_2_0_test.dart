import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:zero_auth/zero_auth.dart';

import 'fake_strategy.dart';

const _credentials = Credentials(username: 'a', password: 'b');
const _registration = RegistrationInput(username: 'a', password: 'b');

AuthSession _session([String token = 'access']) => AuthSession(
      accessToken: token,
      refreshToken: RefreshToken('$token-refresh'),
      userId: 'u1',
      displayName: 'User',
    );

/// A strategy whose four methods can be replaced per test.
/// 四个方法均可按用例替换的策略。
final class _FnStrategy implements AuthStrategy {
  _FnStrategy({
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
      _loginFn == null ? _session() : _loginFn(credentials);

  @override
  Future<AuthSession> register(RegistrationInput input) async =>
      _registerFn == null ? _session() : _registerFn(input);

  @override
  Future<void> logout(SessionHandle handle) async => _logoutFn?.call(handle);

  @override
  Future<AuthSession> refresh(RefreshToken token) async =>
      _refreshFn == null ? _session('renewed') : _refreshFn(token);
}

/// A store whose `save` can be frozen mid-write so a logout can be interleaved.
/// 可把 `save` 冻结在写入途中的存储，用于在持久化窗口插入 logout。
final class _BlockingStore implements TokenStore {
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
final class _BrokenStore implements TokenStore {
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
final class _FailingClearStore implements TokenStore {
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
  group('2.2.0 — public deserializers', () {
    test('RefreshToken.fromJson throws an AppException, never a raw TypeError',
        () {
      for (final bad in <Object?>[
        42,
        null,
        <String>['x'],
        <String, int>{'x': 1},
        true,
      ]) {
        expect(
          () => RefreshToken.fromJson(bad),
          throwsA(isA<UnexpectedAuthException>()),
          reason: 'input: $bad',
        );
        expect(
          () => RefreshToken.fromJson(bad),
          throwsA(isA<AppException>()),
          reason: 'input: $bad',
        );
      }
    });

    test('RefreshToken.tryFromJson returns null for anything but a String', () {
      for (final bad in <Object?>[
        42,
        null,
        <String>['x'],
        <String, int>{'x': 1},
      ]) {
        expect(RefreshToken.tryFromJson(bad), isNull, reason: 'input: $bad');
      }
      expect(RefreshToken.tryFromJson('r1'), const RefreshToken('r1'));
    });

    test('RefreshToken JSON round-trips through both entry points', () {
      const token = RefreshToken('r1');
      expect(RefreshToken.fromJson(token.toJson()), token);
      expect(RefreshToken.tryFromJson(token.toJson()), token);
    });

    test('AuthSession.fromJson wraps every malformed shape in an AppException',
        () {
      final malformed = <Map<String, Object?>>[
        <String, Object?>{},
        <String, Object?>{'accessToken': 42},
        <String, Object?>{'accessToken': 'a', 'refreshToken': 42},
        <String, Object?>{'accessToken': 'a', 'expiresAt': 42},
        <String, Object?>{'accessToken': 'a', 'expiresAt': 'not-a-date'},
        <String, Object?>{'accessToken': 'a', 'userId': 42},
        <String, Object?>{'accessToken': 'a', 'displayName': 42},
        <String, Object?>{'accessToken': 'a', 'claims': 42},
        <String, Object?>{
          'accessToken': 'a',
          'claims': <int, Object?>{1: 'x'},
        },
      ];
      for (final json in malformed) {
        expect(
          () => AuthSession.fromJson(json),
          throwsA(isA<UnexpectedAuthException>()),
          reason: 'json: $json',
        );
        expect(AuthSession.tryFromJson(json), isNull, reason: 'json: $json');
      }
    });

    test('AuthSession.tryFromJson still round-trips a valid session', () {
      final session = _session();
      expect(AuthSession.tryFromJson(session.toJson()), session);
    });
  });

  group('2.2.0 — AuthManagerGroup.clockSkewFraction', () {
    AuthManagerGroup group() => AuthManagerGroup(
          strategyFactory: (_) => FakeAuthStrategy(),
          storeFactory: (_) => InMemoryTokenStore(),
        );

    test('defaults to 0.25 and is forwarded to every manager', () {
      final g = group();
      expect(g.forAccount('a').clockSkewFraction, 0.25);
      expect(g.forAccount('b').clockSkewFraction, 0.25);
    });

    test('a custom value reaches every manager the group creates', () async {
      final g = AuthManagerGroup(
        strategyFactory: (_) => FakeAuthStrategy(),
        storeFactory: (_) => InMemoryTokenStore(),
        clockSkewFraction: 0.75,
      );
      expect(g.forAccount('a').clockSkewFraction, 0.75);
      expect(g.forAccount('b').clockSkewFraction, 0.75);
      await g.disposeAll();
    });

    test('group.validAccessToken reads the active account token', () async {
      final g = group();
      await g.forAccount('a').login(_credentials);
      g.switchTo('a');
      expect(await g.validAccessToken(), 'access');
      await g.disposeAll();
    });
  });

  group('2.2.0 — the four new try* variants', () {
    test('tryRegister returns Ok with the installed state', () async {
      final manager = AuthManager(strategy: _FnStrategy());
      final result = await manager.tryRegister(_registration);
      expect(result.isOk, isTrue);
      expect(result.getOrThrow.session.accessToken, 'access');
      await manager.dispose();
    });

    test('tryRegister maps a strategy failure into Err and emits AuthError',
        () async {
      final manager = AuthManager(
        strategy: _FnStrategy(
          registerFn: (_) async =>
              throw AuthException('rejected', code: 'invalid_credentials'),
        ),
      );
      final states = <AuthState>[];
      final sub = manager.state.listen(states.add);
      final result = await manager.tryRegister(_registration);
      expect(result.isErr, isTrue);
      expect(
        (result as Err<Authenticated>).appException,
        isA<InvalidCredentialsException>(),
      );
      await Future<void>.delayed(Duration.zero);
      expect(states.whereType<AuthError>(), hasLength(1));
      await sub.cancel();
      await manager.dispose();
    });

    test('tryLoginWith returns Ok / Err without rethrowing', () async {
      final manager = AuthManager(strategy: _FnStrategy());
      final ok = await manager.tryLoginWith((_) async => _session('oauth'));
      expect(ok.isOk, isTrue);
      expect(ok.getOrThrow.session.accessToken, 'oauth');

      final err = await manager.tryLoginWith(
        (_) async => throw StateError('provider down'),
      );
      expect(err.isErr, isTrue);
      expect(
        (err as Err<Authenticated>).appException,
        isA<UnexpectedAuthException>(),
      );
      await manager.dispose();
    });

    test('tryLogout always completes the local sign-out', () async {
      final store = InMemoryTokenStore();
      final manager = AuthManager(strategy: _FnStrategy(), tokenStore: store);
      await manager.login(_credentials);
      final result = await manager.tryLogout();
      expect(result.isOk, isTrue);
      expect(manager.current, const Unauthenticated());
      expect(await store.load(), isNull);
      await manager.dispose();
    });

    test('tryLogout reports a failing clear as Err but still signs out',
        () async {
      final manager = AuthManager(
        strategy: _FnStrategy(),
        tokenStore: _FailingClearStore(),
      );
      await manager.login(_credentials);
      final result = await manager.tryLogout();
      expect(result.isErr, isTrue);
      expect(
        (result as Err<void>).appException,
        isA<UnexpectedAuthException>(),
      );
      expect(manager.current, const Unauthenticated());
      await manager.dispose();
    });

    test('tryLogout swallows a backend logout failure', () async {
      final manager = AuthManager(
        strategy: _FnStrategy(
          logoutFn: (_) async => throw StateError('offline'),
        ),
      );
      await manager.login(_credentials);
      expect((await manager.tryLogout()).isOk, isTrue);
      expect(manager.current, const Unauthenticated());
      await manager.dispose();
    });

    test('tryUpdateSession keeps the session when the callback fails',
        () async {
      final manager = AuthManager(strategy: _FnStrategy());
      await manager.login(_credentials);
      final result = await manager.tryUpdateSession(
        (_) => throw StateError('profile service down'),
      );
      expect(result.isErr, isTrue);
      expect(manager.current, isA<Authenticated>());
      expect(manager.currentSession?.accessToken, 'access');
      await manager.dispose();
    });

    test('tryUpdateSession returns Ok with the replaced session', () async {
      final manager = AuthManager(strategy: _FnStrategy());
      await manager.login(_credentials);
      final result = await manager.tryUpdateSession(
        (current) => current.copyWith(displayName: 'New Name'),
      );
      expect(result.isOk, isTrue);
      expect(result.getOrThrow.session.displayName, 'New Name');
      await manager.dispose();
    });

    test('the new try* variants return Err after dispose instead of throwing',
        () async {
      final manager = AuthManager(strategy: _FnStrategy());
      await manager.dispose();
      final results = <Result<dynamic>>[
        await manager.tryRegister(_registration),
        await manager.tryLoginWith((_) async => _session()),
        await manager.tryLogout(),
        await manager.tryUpdateSession((current) => current),
        await manager.tryLogin(_credentials),
        await manager.tryRefresh(),
        await manager.tryRestore(),
      ];
      for (final result in results) {
        expect(result.isErr, isTrue);
        expect((result as Err<dynamic>).appException?.code, 'manager_disposed');
      }
    });
  });

  group('2.2.0 — lazy state subscriptions', () {
    test('reading state without listening does not pin an old snapshot',
        () async {
      final manager = AuthManager(strategy: _FnStrategy());
      final stream = manager.state;
      await manager.login(_credentials);
      expect(await stream.first, isA<Authenticated>());
      await manager.dispose();
    });

    test('the group state stream still replays the active state on listen',
        () async {
      final group = AuthManagerGroup(
        strategyFactory: (_) => FakeAuthStrategy(),
        storeFactory: (_) => InMemoryTokenStore(),
      );
      await group.forAccount('a').login(_credentials);
      group.switchTo('a');
      final stream = group.state;
      expect(await stream.first, isA<Authenticated>());
      await group.disposeAll();
    });
  });

  group('2.2.0 — race and lifecycle regressions', () {
    test('a logout during updateSession persist aborts and clears the store',
        () async {
      final store = _BlockingStore();
      final manager = AuthManager(strategy: _FnStrategy(), tokenStore: store);
      await manager.login(_credentials);

      store.blocking = true;
      final updateGate = Completer<AuthSession>();
      final pending = manager.updateSession((_) => updateGate.future);
      await Future<void>.delayed(Duration.zero);
      updateGate.complete(_session('updated'));
      await store.saveStarted.future;

      await manager.logout();
      store.saveGate.complete();

      await expectLater(pending, throwsA(isA<NoActiveSessionException>()));
      expect(await store.load(), isNull);
      expect(manager.current, const Unauthenticated());
      await manager.dispose();
    });

    test('a renewal still in flight when dispose arrives cannot resurrect',
        () async {
      final gate = Completer<AuthSession>();
      final manager = AuthManager(
        strategy: _FnStrategy(refreshFn: (_) => gate.future),
      );
      await manager.login(_credentials);
      final pending = manager.refresh();
      await manager.dispose();
      gate.complete(_session('late'));
      await expectLater(pending, throwsA(isA<NoActiveSessionException>()));
      expect(manager.currentSession?.accessToken, 'access');
    });

    test('refresh is rejected while logging out and currentSession is null',
        () async {
      final gate = Completer<void>();
      final manager = AuthManager(
        strategy: _FnStrategy(logoutFn: (_) => gate.future),
      );
      await manager.login(_credentials);
      final pending = manager.logout();
      expect(manager.current, isA<LoggingOut>());
      expect(manager.currentSession, isNull);
      expect(
        () => manager.refresh(),
        throwsA(isA<NoActiveSessionException>()),
      );
      gate.complete();
      await pending;
      await manager.dispose();
    });

    test('register emits AuthError and rethrows the mapped failure', () async {
      final manager = AuthManager(
        strategy: _FnStrategy(
          registerFn: (_) async => throw const AuthFail(
            'rejected',
            code: 'invalid_credentials',
          ),
        ),
      );
      final states = <AuthState>[];
      final sub = manager.state.listen(states.add);
      await expectLater(
        manager.register(_registration),
        throwsA(isA<InvalidCredentialsException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(states.whereType<AuthError>(), hasLength(1));
      await sub.cancel();
      await manager.dispose();
    });

    test('mapAuthFailure covers the tail of the code table', () {
      expect(
        mapAuthFailure(AuthException('x', code: 'no_active_session')),
        isA<NoActiveSessionException>(),
      );
      expect(
        mapAuthFailure(const AuthFail('x', code: 'refresh_token_missing')),
        isA<RefreshTokenMissingException>(),
      );
      expect(mapAuthFailure(StateError('x')), isA<UnexpectedAuthException>());
      expect(
        mapAuthFailure(const AuthFail('no code')),
        isA<UnexpectedAuthException>(),
      );
    });

    test('an InvalidCredentialsException renewal is terminal', () async {
      final strategy = FakeAuthStrategy()
        ..refreshError = AuthException('bad', code: 'invalid_credentials');
      final store = InMemoryTokenStore();
      final manager = AuthManager(strategy: strategy, tokenStore: store);
      await manager.login(_credentials);
      await expectLater(
        manager.refresh(),
        throwsA(isA<InvalidCredentialsException>()),
      );
      expect(await store.load(), isNull);
      expect(manager.current, const Unauthenticated());
      await manager.dispose();
    });

    test('dropping an unrenewable session reports why and clears locally',
        () async {
      final manager = AuthManager(
        strategy: _FnStrategy(),
        tokenStore: _FailingClearStore(),
      );
      final states = <AuthState>[];
      final sub = manager.state.listen(states.add);
      await expectLater(
        manager.restore(),
        throwsA(isA<UnexpectedAuthException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(states.whereType<AuthError>(), hasLength(1));
      expect(manager.current, const Unauthenticated());
      await sub.cancel();
      await manager.dispose();
    });

    test('restoreAll(parallel: true) aggregates a real failure in input order',
        () async {
      final group = AuthManagerGroup(
        strategyFactory: (_) => FakeAuthStrategy(),
        storeFactory: (id) =>
            id == 'b' || id == 'c' ? _BrokenStore() : InMemoryTokenStore(),
      );
      await expectLater(
        group.restoreAll(['a', 'b', 'c'], parallel: true),
        throwsA(isA<AppException>()),
      );
      expect(group.accountIds.toList(), containsAll(<String>['a', 'b', 'c']));
      await group.disposeAll();
    });
  });

  group('2.2.0 — timer-driven behaviour', () {
    test('dispose cancels a scheduled proactive renewal', () {
      FakeAsync().run((async) {
        final strategy = _TimerStrategy();
        final manager = AuthManager(
          strategy: strategy,
          autoRefreshAhead: const Duration(minutes: 5),
        );
        unawaited(manager.login(_credentials));
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
        unawaited(manager.login(_credentials));
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
        unawaited(manager.login(_credentials));
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

  group('2.2.0 — Result edge cases', () {
    test('Err keeps a non-AppException cause untouched', () {
      final err = Err<int>(StateError('x'));
      expect(err.appException, isNull);
      expect(() => err.getOrThrow, throwsA(isA<StateError>()));
      final mapped = err.map((value) => value.toString());
      expect(mapped.isErr, isTrue);
      expect((mapped as Err<String>).error, isA<StateError>());
    });
  });
}
