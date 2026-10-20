import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:zero_auth/zero_auth.dart';

import 'fake_strategy.dart';

/// A strategy whose `refresh` waits for [gate], so a test decides exactly when a
/// renewal lands — including in the middle of a suspended `updateSession`.
/// 其 `refresh` 在 [gate] 完成前不返回的策略，使测试能精确决定续期落地的时刻 ——
/// 包括在 `updateSession` 挂起期间。
final class _GatedRefreshStrategy implements AuthStrategy {
  final Completer<AuthSession> gate = Completer<AuthSession>();
  int refreshCount = 0;

  AuthSession _session([String token = 'stale-access']) => AuthSession(
        accessToken: token,
        refreshToken: RefreshToken('$token-refresh'),
        userId: 'u1',
        displayName: 'User',
      );

  @override
  Future<AuthSession> login(Credentials credentials) async => _session();

  @override
  Future<AuthSession> register(RegistrationInput input) async => _session();

  @override
  Future<void> logout(SessionHandle handle) async {}

  @override
  Future<AuthSession> refresh(RefreshToken token) {
    refreshCount++;
    return gate.future;
  }
}

/// A store that counts writes, so a test can tell "nothing was persisted" apart
/// from "the same value was persisted again".
/// 记录写入次数的存储，便于测试区分「没有写入」与「又写了一次相同的值」。
final class _RecordingStore implements TokenStore {
  AuthSession? value;
  int saveCount = 0;

  @override
  Future<void> save(AuthSession session) async {
    saveCount++;
    value = session;
  }

  @override
  Future<AuthSession?> load() async => value;

  @override
  Future<void> clear() async => value = null;
}

/// A store whose reads always fail, modelling storage that cannot be opened.
/// 读取必然失败的存储，模拟无法打开的存储。
final class _BrokenStore implements TokenStore {
  @override
  Future<void> save(AuthSession session) async {}

  @override
  Future<AuthSession?> load() async => throw StateError('store unavailable');

  @override
  Future<void> clear() async {}
}

/// A raw, non-`AppException` failure — the kind a network call throws before
/// anybody maps it.
/// 裸的、非 `AppException` 的失败 —— 网络调用在被映射前抛出的那种。
final class _BoomError implements Exception {
  @override
  String toString() => 'BoomError: connection reset';
}

/// A strategy whose `refresh` answers from a script, so a test decides which
/// call fails and which one succeeds.
/// 其 `refresh` 按脚本应答的策略，使测试能决定哪次调用失败、哪次成功。
final class _ScriptedRefreshStrategy implements AuthStrategy {
  _ScriptedRefreshStrategy(this._script);

  final Future<AuthSession> Function(int call) _script;
  int _calls = 0;

  int get calls => _calls;

  @override
  Future<AuthSession> login(Credentials credentials) async =>
      _ScriptedRefreshStrategy.session();

  @override
  Future<AuthSession> register(RegistrationInput input) async =>
      _ScriptedRefreshStrategy.session();

  @override
  Future<void> logout(SessionHandle handle) async {}

  @override
  Future<AuthSession> refresh(RefreshToken token) => _script(++_calls);

  /// Already expired, so every activation is "due" and the throttle — not the
  /// expiry — decides when the next renewal runs.
  /// 已过期，因此每次激活都是「已到期」，由节流而非过期时间决定下一次续期时机。
  static AuthSession session() => AuthSession(
        accessToken: 'access',
        refreshToken: const RefreshToken('refresh'),
        expiresAt: fixedNow.subtract(const Duration(minutes: 5)),
        userId: 'u1',
      );
}

final fixedNow = DateTime.utc(2026, 1, 1, 12);
const credentials = Credentials(username: 'u', password: 'p');

/// Lets pending microtasks settle so stream emissions become observable.
/// 让挂起的微任务执行完，使状态流的新值可被观察。
Future<void> pump([int times = 3]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// The mapped domain error a failed [Result] carries, or `null` when it is an
/// [Ok].
/// 失败的 [Result] 所携带的映射后领域错误；[Ok] 时为 `null`。
AppException? failureOf<T>(Result<T> result) => switch (result) {
      Err(:final appException) => appException,
      _ => null,
    };

void main() {
  group('AuthManager — updateSession failure mapping', () {
    test('a raw callback failure leaves as an AppException, never raw',
        () async {
      final manager = AuthManager(strategy: FakeAuthStrategy());
      await manager.login(credentials);

      await expectLater(
        manager.updateSession((current) async {
          await Future<void>.delayed(Duration.zero);
          throw _BoomError();
        }),
        throwsA(isA<AppException>()),
      );

      await manager.dispose();
    });

    test('a raw callback failure is emitted as AuthError first', () async {
      final manager = AuthManager(strategy: FakeAuthStrategy());
      await manager.login(credentials);

      final states = <AuthState>[];
      final sub = manager.state.listen(states.add);

      await expectLater(
        manager.updateSession((current) async => throw _BoomError()),
        throwsA(isA<AuthException>()),
      );
      await pump();

      // The failure is reported on the stream…
      expect(states.any((s) => s is AuthError), isTrue);
      // …and the manager lands back on the untouched session: a failed update
      // must not sign the user out.
      // ……管理器随即回到未被触及的会话：更新失败绝不能把用户登出。
      expect(states.last, isA<Authenticated>());
      expect(manager.current, isA<Authenticated>());
      expect(manager.currentSession?.accessToken, 'access');
      expect(manager.accessToken, 'access');

      await sub.cancel();
      await manager.dispose();
    });

    test('an AuthException thrown by the callback is preserved', () async {
      final manager = AuthManager(strategy: FakeAuthStrategy());
      await manager.login(credentials);

      await expectLater(
        manager.updateSession(
          (current) async => throw SessionExpiredException(),
        ),
        throwsA(isA<SessionExpiredException>()),
      );

      await manager.dispose();
    });
  });

  group('AuthManager — updateSession vs a mid-update renewal', () {
    test('a renewal landing mid-update aborts instead of clobbering it',
        () async {
      final strategy = _GatedRefreshStrategy();
      final store = _RecordingStore();
      final manager = AuthManager(
        strategy: strategy,
        tokenStore: store,
        clock: () => fixedNow,
      );
      await manager.login(credentials);
      final savesAfterLogin = store.saveCount;

      // Hold a renewal open, then start an async update that suspends.
      // 挡住一次续期，再启动一个会挂起的异步更新。
      final refreshing = manager.refresh();
      await pump();

      final updating = manager.updateSession((current) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return current.copyWith(displayName: 'Renamed');
      });

      // The renewal lands while the update is suspended.
      // 更新挂起期间，续期落地。
      strategy.gate.complete(
        AuthSession(
          accessToken: 'fresh-access',
          refreshToken: const RefreshToken('fresh-refresh'),
          userId: 'u1',
        ),
      );
      await refreshing;
      await expectLater(updating, throwsA(isA<NoActiveSessionException>()));

      // The renewed session survives; nothing stale was written over it.
      // 续期后的会话保留；没有任何旧值被写到它上面。
      expect(manager.currentSession?.accessToken, 'fresh-access');
      expect(
        manager.currentSession?.refreshToken,
        const RefreshToken('fresh-refresh'),
      );
      // The update persisted nothing: the store still holds the renewed one.
      // 更新没有持久化任何东西：存储里仍是续期后的那个。
      expect(store.saveCount, savesAfterLogin + 1);
      expect((await store.load())?.accessToken, 'fresh-access');

      await manager.dispose();
    });

    test('a logout landing mid-update aborts', () async {
      final strategy = _GatedRefreshStrategy();
      final store = _RecordingStore();
      final manager = AuthManager(
        strategy: strategy,
        tokenStore: store,
        clock: () => fixedNow,
      );
      await manager.login(credentials);

      final updating = manager.updateSession((current) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return current.copyWith(displayName: 'Renamed');
      });

      await manager.logout();
      await expectLater(updating, throwsA(isA<NoActiveSessionException>()));

      expect(manager.current, const Unauthenticated());
      expect(await store.load(), isNull);

      await manager.dispose();
    });

    test('a re-login landing mid-update aborts', () async {
      final manager = AuthManager(strategy: FakeAuthStrategy());
      await manager.login(credentials);

      final updating = manager.updateSession((current) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return current.copyWith(displayName: 'Renamed');
      });

      await manager.login(const Credentials(username: 'other', password: 'pw'));
      await expectLater(updating, throwsA(isA<NoActiveSessionException>()));

      // The re-login won: its session is the active one.
      // 重新登录胜出：它的会话才是活动会话。
      expect(manager.currentSession?.displayName, 'User');

      await manager.dispose();
    });
  });

  group('AuthManager — non-throwing variants', () {
    test('tryLogin returns Ok with the installed state', () async {
      final manager = AuthManager(strategy: FakeAuthStrategy());

      final result = await manager.tryLogin(credentials);

      expect(result.isOk, isTrue);
      final value = result.getOrThrow;
      expect(value.session.accessToken, 'access');
      expect(manager.current, isA<Authenticated>());

      await manager.dispose();
    });

    test('tryLogin returns Err with the typed failure', () async {
      final strategy = FakeAuthStrategy()
        ..loginError = AuthException('nope', code: 'invalid_credentials');
      final manager = AuthManager(strategy: strategy);

      final result = await manager.tryLogin(credentials);

      expect(result.isErr, isTrue);
      expect(
        failureOf(result),
        isA<InvalidCredentialsException>(),
      );
      // The stream still saw the failure — one code path, two styles.
      // 状态流依然收到了这次失败 —— 同一条代码路径，两种风格。
      expect(manager.current, isA<AuthError>());

      await manager.dispose();
    });

    test('tryRefresh returns Ok with the renewed session', () async {
      final strategy = FakeAuthStrategy()
        ..refreshedSession = AuthSession(
          accessToken: 'fresh',
          refreshToken: const RefreshToken('refresh'),
          userId: 'u1',
        );
      final manager = AuthManager(strategy: strategy);
      await manager.login(credentials);

      final result = await manager.tryRefresh();

      expect(result.isOk, isTrue);
      expect(result.getOrThrow.accessToken, 'fresh');

      await manager.dispose();
    });

    test('tryRefresh captures the synchronous pre-conditions', () async {
      final manager = AuthManager(strategy: FakeAuthStrategy());

      // No session at all: an Err, not a throw.
      // 完全没有会话：返回 Err，而不是抛出。
      var result = await manager.tryRefresh();
      expect(result.isErr, isTrue);
      expect(failureOf(result), isA<NoActiveSessionException>());

      // A session without a refresh token: same doorway.
      // 没有刷新令牌的会话：同一道门。
      await manager.login(credentials);
      await manager.updateSession(
        (current) => AuthSession(accessToken: current.accessToken),
      );
      result = await manager.tryRefresh();
      expect(result.isErr, isTrue);
      expect(failureOf(result), isA<RefreshTokenMissingException>());

      await manager.dispose();
    });

    test('tryRestore reports Ok when nothing is persisted', () async {
      final manager = AuthManager(strategy: FakeAuthStrategy());

      final result = await manager.tryRestore();

      expect(result.isOk, isTrue);
      expect(manager.current, const Unauthenticated());

      await manager.dispose();
    });

    test('tryRestore returns Err when the store cannot be read', () async {
      final manager = AuthManager(
        strategy: FakeAuthStrategy(),
        tokenStore: _BrokenStore(),
        clock: () => fixedNow,
      );

      final result = await manager.tryRestore();

      expect(result.isErr, isTrue);
      expect(failureOf(result), isA<UnexpectedAuthException>());
      expect(manager.current, const Unauthenticated());

      await manager.dispose();
    });
  });

  group('AuthManager — proactive retry counter', () {
    test('a successful manual renewal resets the backoff', () {
      FakeAsync().run((async) {
        final strategy = _ScriptedRefreshStrategy((call) async {
          if (call == 1 || call == 3) {
            throw AuthException('offline', code: 'network_unreachable');
          }
          return _ScriptedRefreshStrategy.session();
        });
        final manager = AuthManager(
          strategy: strategy,
          tokenStore: InMemoryTokenStore(),
          autoRefreshAhead: const Duration(minutes: 5),
          autoRefreshRetryDelay: const Duration(seconds: 30),
          clock: () => fixedNow,
        );

        unawaited(manager.login(credentials));
        async.flushMicrotasks();
        // Already expired: the first renewal fires at once and fails, which
        // arms the retry timer.
        // 已过期：第一次续期立刻触发并失败，随之装上重试定时器。
        expect(strategy.calls, 1);

        // A caller-driven renewal succeeds — the session is healthy again.
        // 调用方驱动的续期成功 —— 会话重新健康。
        unawaited(manager.refresh());
        async.flushMicrotasks();
        expect(strategy.calls, 2);

        // The session is still already due, so the schedule re-arms at once,
        // throttled by autoRefreshMinInterval.
        // 会话依旧已到期，于是调度立刻重新武装，受 autoRefreshMinInterval 节流。
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(strategy.calls, 3);

        // That failure re-arms with the BASE delay: the counter was reset by
        // the successful manual renewal, so the backoff does not escalate.
        // 这次失败按基础延迟重新排程：成功的手动续期已把计数归零，
        // 因此退避不会升级。
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();
        expect(strategy.calls, 4);

        unawaited(manager.dispose());
      });
    });
  });
}
