import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:zero_auth/zero_auth.dart';

import 'fake_strategy.dart';

/// Clears successfully but refuses to clear, so `logout()` surfaces a failure.
final class _UndeletableStore implements TokenStore {
  AuthSession? _session;

  @override
  Future<void> save(AuthSession session) async => _session = session;

  @override
  Future<AuthSession?> load() async => _session;

  @override
  Future<void> clear() async => throw StateError('store unavailable');
}

void main() {
  final now = DateTime.utc(2026, 1, 1, 12);

  AuthSession session({bool expired = false, bool withRefresh = true}) =>
      AuthSession(
        accessToken: 'access',
        refreshToken: withRefresh ? const RefreshToken('refresh') : null,
        expiresAt: expired
            ? now.subtract(const Duration(minutes: 1))
            : now.add(const Duration(minutes: 5)),
        userId: 'user',
        displayName: 'user@demo',
      );

  group('validAccessToken', () {
    test('never returns an expired token that cannot be renewed', () async {
      final manager = AuthManager(
        strategy: FakeAuthStrategy(session: session()),
        clock: () => now,
      );
      // Expired, and no refresh token, so there is no way to make it valid.
      await manager.login(
        const Credentials(username: 'user', password: 'user'),
      );
      // `copyWith` keeps a field when passed null, so clearing the refresh token
      // means building a new session.
      // `copyWith` 传入 null 表示保留原值，因此清除刷新令牌需要新建会话。
      await manager.updateSession(
        (current) => AuthSession(
          accessToken: current.accessToken,
          expiresAt: now.subtract(const Duration(minutes: 1)),
          userId: current.userId,
          displayName: current.displayName,
        ),
      );

      expect(manager.currentSession?.isExpiredAt(now), isTrue);
      expect(manager.currentSession?.refreshToken, isNull);
      expect(await manager.validAccessToken(), isNull);
      await manager.dispose();
    });

    test('renews an expired token when a refresh token exists', () async {
      final strategy = FakeAuthStrategy(session: session());
      final manager = AuthManager(strategy: strategy, clock: () => now);
      await manager.login(
        const Credentials(username: 'user', password: 'user'),
      );
      await manager.updateSession(
        (current) => current.copyWith(
          expiresAt: now.subtract(const Duration(minutes: 1)),
        ),
      );

      expect(await manager.validAccessToken(), isNotNull);
      expect(strategy.refreshCount, 1);
      await manager.dispose();
    });
  });

  group('AuthSession helpers', () {
    test('copyWith replaces only the given fields', () {
      final original = session();
      final copy = original.copyWith(displayName: 'Renamed');

      expect(copy.displayName, 'Renamed');
      expect(copy.accessToken, original.accessToken);
      expect(copy.userId, original.userId);
    });

    test('expiry helpers', () {
      final future = session();
      expect(future.timeUntilExpiry(now), const Duration(minutes: 5));
      expect(future.isExpiringWithin(const Duration(minutes: 1), now), isFalse);
      expect(future.isExpiringWithin(const Duration(minutes: 10), now), isTrue);

      final none = AuthSession(accessToken: 'a');
      expect(none.timeUntilExpiry(now), isNull);
      expect(none.isExpiringWithin(const Duration(minutes: 1), now), isFalse);
    });
  });

  group('updateSession', () {
    test('accepts an async update', () async {
      final store = _UndeletableStore();
      final manager = AuthManager(
        strategy: FakeAuthStrategy(session: session()),
        tokenStore: store,
        clock: () => now,
      );
      await manager.login(
        const Credentials(username: 'user', password: 'user'),
      );

      await manager.updateSession((current) async {
        await Future<void>.delayed(Duration.zero);
        return current.copyWith(displayName: 'Fetched');
      });

      expect(manager.currentSession?.displayName, 'Fetched');
      await manager.dispose();
    });
  });

  group('restore respects refreshIfExpired', () {
    test('a verbatim restore does not trigger a renewal', () {
      FakeAsync().run((async) {
        final strategy = FakeAuthStrategy(session: session(expired: true));
        final store = InMemoryTokenStore();
        // InMemoryTokenStore.save assigns synchronously, so the value is there
        // before the (unawaited) future resolves.
        // InMemoryTokenStore.save 是同步赋值的，因此在 future 完成前值已写入。
        unawaited(store.save(session(expired: true)));
        final manager = AuthManager(
          strategy: strategy,
          tokenStore: store,
          autoRefreshAhead: const Duration(minutes: 5),
          clock: () => now,
        );
        unawaited(manager.restore(refreshIfExpired: false));
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 10));

        expect(strategy.refreshCount, 0);
        expect(manager.current, isA<Authenticated>());
        unawaited(manager.dispose());
      });
    });
  });

  group('proactive retry is bounded', () {
    test('gives up after the configured number of attempts', () {
      FakeAsync().run((async) {
        final strategy = FakeAuthStrategy(
          session: session(expired: true),
        )..refreshError = AuthException('offline', code: 'network_unreachable');
        final manager = AuthManager(
          strategy: strategy,
          tokenStore: InMemoryTokenStore(),
          autoRefreshAhead: const Duration(minutes: 5),
          autoRefreshRetryDelay: const Duration(seconds: 30),
          clock: () => now,
        );

        manager.login(const Credentials(username: 'user', password: 'user'));
        async.flushMicrotasks();
        expect(strategy.refreshCount, 1); // immediate, because already expired

        async.elapse(const Duration(seconds: 30));
        expect(strategy.refreshCount, 2);
        async.elapse(const Duration(seconds: 60));
        expect(strategy.refreshCount, 3);
        async.elapse(const Duration(seconds: 90));
        expect(strategy.refreshCount, 4);

        // maxRetries reached (3 retries on top of the first attempt).
        async.elapse(const Duration(hours: 2));
        expect(strategy.refreshCount, 4);

        unawaited(manager.dispose());
      });
    });
  });

  group('AuthManagerGroup robustness', () {
    AuthManagerGroup build({TokenStore Function(String)? storeFactory}) =>
        AuthManagerGroup(
          strategyFactory: (id) => FakeAuthStrategy(session: session()),
          storeFactory: storeFactory ?? (id) => InMemoryTokenStore(),
        );

    test('remove disposes the manager even when logout fails', () async {
      final group = build(storeFactory: (id) => _UndeletableStore());
      final manager = group.addAccount('alice');
      await manager.login(
        const Credentials(username: 'user', password: 'user'),
      );

      await expectLater(group.remove('alice'), throwsA(isA<AuthException>()));
      expect(group.accountIds, isEmpty);

      // Disposal happened despite the failed logout. `refresh()` throws
      // synchronously, so it must be wrapped in a closure.
      // 尽管登出失败，释放仍然发生了。`refresh()` 是同步抛出，因此要用闭包包住。
      expect(
        () => manager.refresh(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.code,
            'code',
            'manager_disposed',
          ),
        ),
      );
      await group.disposeAll();
    });

    test('usage after disposeAll is rejected', () async {
      final group = build();
      await group.disposeAll();

      expect(
        () => group.addAccount('alice'),
        throwsA(
          isA<AuthException>().having((e) => e.code, 'code', 'group_disposed'),
        ),
      );
      expect(() => group.switchTo('alice'), throwsA(isA<AuthException>()));
      expect(() => group.state, throwsA(isA<AuthException>()));
      // disposeAll stays idempotent.
      await group.disposeAll();
    });

    test('restoreAll can drop accounts that are no longer known', () async {
      final group = build();
      await group
          .addAccount('alice')
          .login(const Credentials(username: 'alice', password: 'pw'));
      await group
          .addAccount('carol')
          .login(const Credentials(username: 'carol', password: 'pw'));

      await group.restoreAll(['alice'], activeId: 'alice', dropOthers: true);

      expect(group.accountIds, ['alice']);
      expect(group.activeId, 'alice');
      await group.disposeAll();
    });
  });
}
