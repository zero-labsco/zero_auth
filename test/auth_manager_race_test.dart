import 'dart:async';

import 'package:test/test.dart';
import 'package:zero_auth/zero_auth.dart';

import 'fake_strategy.dart';
import 'test_doubles.dart';

/// A store whose [save] blocks until [saveGate] completes, so a caller can be
/// frozen mid-persist and a concurrent operation (e.g. logout) slipped in.
/// 一个 save 会阻塞到 [saveGate] 完成的存储，从而把调用者冻在「持久化途中」，
/// 好让并发操作（如登出）插进来。
final class _GatedSaveStore implements TokenStore {
  Completer<void> saveGate = Completer<void>();
  AuthSession? saved;

  @override
  Future<void> save(AuthSession session) async {
    saved = session;
    await saveGate.future;
  }

  @override
  Future<AuthSession?> load() async => saved;

  @override
  Future<void> clear() async {
    saved = null;
  }
}

/// A store whose [clear] blocks until [clearGate] completes and whose [load]
/// returns an already-expired session with no refresh token — the exact shape
/// that drives [AuthManager.restore] into [_dropSession].
/// 一个 clear 会阻塞到 [clearGate] 完成的存储；其 [load] 返回一个「已过期且无刷新
/// 令牌」的会话 —— 正是把 [AuthManager.restore] 引向 [_dropSession] 的形状。
final class _GatedClearStore implements TokenStore {
  final Completer<void> clearGate = Completer<void>();
  AuthSession? saved;

  @override
  Future<void> save(AuthSession session) async {
    saved = session;
  }

  @override
  Future<AuthSession?> load() async => AuthSession(
        accessToken: 'old',
        userId: 'u1',
        expiresAt: DateTime.utc(2000),
      );

  @override
  Future<void> clear() async {
    await clearGate.future;
    saved = null;
  }
}

void main() {
  test('a logout during login persist does not resurrect the session',
      () async {
    final store = _GatedSaveStore();
    final manager = AuthManager(
      strategy: FakeAuthStrategy(),
      tokenStore: store,
    );

    // The future is created inside expectLater so the (expected) abort stays
    // within its managed zone. Login is frozen mid-persist.
    // future 在 expectLater 内创建，使「预期的中止」处于受管 zone 内。登录冻在持久化途中。
    final expectation = expectLater(
      () => manager.login(Credentials(username: 'u', password: 'p')),
      throwsA(isA<NoActiveSessionException>()),
    );
    expect(manager.current, isA<Authenticating>());

    // Log out while the login is still writing.
    // 在登录仍写入时登出。
    await manager.logout();
    expect(manager.current, isA<Unauthenticated>());

    // Release the stalled persist: the now-stale login must abort and must not
    // leave its tokens in the store.
    // 放行卡住的持久化：已失效的登录必须中止，且不能把令牌留在存储里。
    store.saveGate.complete();
    await expectation;

    expect(manager.current, isA<Unauthenticated>());
    expect(store.saved, isNull);
  });

  test('a logout during register persist does not resurrect the session',
      () async {
    final store = _GatedSaveStore();
    final manager = AuthManager(
      strategy: FakeAuthStrategy(),
      tokenStore: store,
    );

    final expectation = expectLater(
      () => manager.register(RegistrationInput(username: 'u', password: 'p')),
      throwsA(isA<NoActiveSessionException>()),
    );
    expect(manager.current, isA<Authenticating>());

    await manager.logout();
    expect(manager.current, isA<Unauthenticated>());

    store.saveGate.complete();
    await expectation;

    expect(manager.current, isA<Unauthenticated>());
    expect(store.saved, isNull);
  });

  test('a logout during loginWith persist does not resurrect the session',
      () async {
    final store = _GatedSaveStore();
    final manager = AuthManager(
      strategy: FakeAuthStrategy(),
      tokenStore: store,
    );

    final expectation = expectLater(
      () => manager.loginWith(
        (strategy) => strategy.login(Credentials(username: 'u', password: 'p')),
      ),
      throwsA(isA<NoActiveSessionException>()),
    );
    expect(manager.current, isA<Authenticating>());

    await manager.logout();
    expect(manager.current, isA<Unauthenticated>());

    store.saveGate.complete();
    await expectation;

    expect(manager.current, isA<Unauthenticated>());
    expect(store.saved, isNull);
  });

  test('a logout during refresh persist does not resurrect the session',
      () async {
    final store = _GatedSaveStore();
    final manager = AuthManager(
      strategy: FakeAuthStrategy(),
      tokenStore: store,
    );

    // Establish a session first.
    // 先建立会话。
    final login = manager.login(Credentials(username: 'u', password: 'p'));
    store.saveGate.complete();
    await login;
    expect(manager.current, isA<Authenticated>());

    // Arm a fresh gate so refresh blocks mid-persist.
    // 重置 gate，让 refresh 卡在持久化途中。
    store.saveGate = Completer<void>();
    final expectation = expectLater(
      () => manager.refresh(),
      throwsA(isA<NoActiveSessionException>()),
    );
    expect(manager.current, isA<Refreshing>());

    await manager.logout();
    expect(manager.current, isA<Unauthenticated>());

    // Release the stalled persist: the refresh must abort without installing the
    // (retired) tokens it minted.
    // 放行卡住的持久化：刷新必须中止，且不安装它签发的（已退役）令牌。
    store.saveGate.complete();
    await expectation;

    expect(manager.current, isA<Unauthenticated>());
  });

  test('a login during restore drop is not overwritten by the sign-out',
      () async {
    final store = _GatedClearStore();
    final manager = AuthManager(
      strategy: FakeAuthStrategy(),
      tokenStore: store,
    );

    final restore = manager.restore(refreshIfExpired: true);
    // Restore is frozen inside [_dropSession]'s clear.
    // restore 冻在 [_dropSession] 的清存储途中。
    expect(manager.current, isA<Restoring>());

    // A login lands while the restore is still clearing the store.
    // 在 restore 仍在清存储时，一次登录落地了。
    await manager.login(Credentials(username: 'u', password: 'p'));
    expect(manager.current, isA<Authenticated>());

    // Let the restore finish; it must not overwrite the new session with a
    // sign-out.
    // 让 restore 结束；它不能把新会话覆盖成登出。
    store.clearGate.complete();
    await restore;

    expect(manager.current, isA<Authenticated>());
  });

  test(
      'AuthSession.fromJson throws an AppException (not a raw error) on '
      'malformed input', () {
    expect(
      () => AuthSession.fromJson(<String, Object?>{'refreshToken': 'r'}),
      throwsA(isA<AppException>()),
    );
  });

  test('AuthSession.fromJson round-trips a valid session', () {
    final session = AuthSession(
      accessToken: 'a',
      userId: 'u1',
      refreshToken: RefreshToken('r'),
      expiresAt: DateTime.utc(2030),
    );
    final back = AuthSession.fromJson(session.toJson());
    expect(back.accessToken, 'a');
    expect(back.refreshToken, isA<RefreshToken>());
    expect(back.userId, 'u1');
  });

  group('AuthManager — session-installation races', () {
    test('a logout during updateSession persist aborts and clears the store',
        () async {
      final store = BlockingStore();
      final manager = AuthManager(strategy: FnStrategy(), tokenStore: store);
      await manager.login(testCredentials);

      store.blocking = true;
      final updateGate = Completer<AuthSession>();
      final pending = manager.updateSession((_) => updateGate.future);
      await Future<void>.delayed(Duration.zero);
      updateGate.complete(testSession('updated'));
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
        strategy: FnStrategy(refreshFn: (_) => gate.future),
      );
      await manager.login(testCredentials);
      final pending = manager.refresh();
      await manager.dispose();
      gate.complete(testSession('late'));
      await expectLater(pending, throwsA(isA<NoActiveSessionException>()));
      expect(manager.currentSession?.accessToken, 'access');
    });

    test('refresh is rejected while logging out and currentSession is null',
        () async {
      final gate = Completer<void>();
      final manager = AuthManager(
        strategy: FnStrategy(logoutFn: (_) => gate.future),
      );
      await manager.login(testCredentials);
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
  });
}
