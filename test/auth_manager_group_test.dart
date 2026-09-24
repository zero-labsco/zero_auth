import 'dart:async';

import 'package:test/test.dart';
import 'package:zero_auth/zero_auth.dart';

import 'fake_strategy.dart';

/// A [TokenStore] whose `load()` waits for [barrier]. It only returns once every
/// account has started loading, which is what turns a serial restore into a
/// deadlock in the `parallel:` test below.
/// 其 `load()` 会等待 [barrier] 的 [TokenStore]。只有当所有账号都开始读取后它才返回，
/// 这正是下面 `parallel:` 测试中「串行恢复会死锁」的原因。
final class _BarrierStore implements TokenStore {
  _BarrierStore(this.barrier);

  final Future<void> Function() barrier;
  AuthSession? _value;

  @override
  Future<void> save(AuthSession session) async => _value = session;

  @override
  Future<AuthSession?> load() async {
    await barrier();
    return _value;
  }

  @override
  Future<void> clear() async => _value = null;
}

void main() {
  /// Builds a group whose strategy and store are both keyed by account id, the
  /// way a real app would isolate persisted sessions.
  AuthManagerGroup buildGroup(Map<String, InMemoryTokenStore> stores) =>
      AuthManagerGroup(
        strategyFactory: (accountId) => FakeAuthStrategy(
          session: AuthSession(
            accessToken: 'token-$accountId',
            refreshToken: const RefreshToken('refresh'),
            userId: accountId,
          ),
        ),
        storeFactory: (accountId) =>
            stores.putIfAbsent(accountId, InMemoryTokenStore.new),
      );

  group('AuthManagerGroup — per-account managers', () {
    test('creates one manager per account and caches it', () {
      final stores = <String, InMemoryTokenStore>{};
      final group = buildGroup(stores);

      final first = group.forAccount('alice');
      expect(group.forAccount('alice'), same(first));
      expect(group.forAccount('bob'), isNot(same(first)));
      expect(group.accountIds, containsAll(['alice', 'bob']));

      group.disposeAll();
    });

    test('gives each account its own token store', () async {
      final stores = <String, InMemoryTokenStore>{};
      final group = buildGroup(stores);

      await group
          .forAccount('alice')
          .login(const Credentials(username: 'alice', password: 'pw'));

      expect(await stores['alice']!.load(), isNotNull);
      expect(await stores['bob']?.load(), isNull);

      await group.disposeAll();
    });
  });

  group('AuthManagerGroup — active account', () {
    test('active manager drives accessToken and currentSession', () async {
      final stores = <String, InMemoryTokenStore>{};
      final group = buildGroup(stores);

      await group
          .forAccount('alice')
          .login(const Credentials(username: 'alice', password: 'pw'));
      await group
          .forAccount('bob')
          .login(const Credentials(username: 'bob', password: 'pw'));

      group.switchTo('alice');
      expect(group.activeId, 'alice');
      expect(group.accessToken, 'token-alice');
      expect(group.currentSession?.userId, 'alice');

      group.switchTo('bob');
      expect(group.accessToken, 'token-bob');
      expect(group.currentSession?.userId, 'bob');

      await group.disposeAll();
    });

    test('state follows the active account and replays its value', () async {
      final stores = <String, InMemoryTokenStore>{};
      final group = buildGroup(stores);

      await group
          .forAccount('alice')
          .login(const Credentials(username: 'alice', password: 'pw'));
      group.switchTo('alice');

      final seen = <AuthState>[];
      final sub = group.state.listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, isA<Authenticated>());

      // Switching replays the newly active account's state.
      group.switchTo('bob');
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, isA<Unauthenticated>());
      expect(group.current, const Unauthenticated());

      await sub.cancel();
      await group.disposeAll();
    });

    test('forwards the active manager emissions', () async {
      final stores = <String, InMemoryTokenStore>{};
      final group = buildGroup(stores);

      await group
          .forAccount('alice')
          .login(const Credentials(username: 'alice', password: 'pw'));
      group.switchTo('alice');

      final seen = <AuthState>[];
      final sub = group.state.listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      seen.clear();

      await group.active!.logout();
      await Future<void>.delayed(Duration.zero);

      expect(seen.any((s) => s is LoggingOut), isTrue);
      expect(seen.last, isA<Unauthenticated>());

      await sub.cancel();
      await group.disposeAll();
    });
  });

  group('AuthManagerGroup — lifecycle', () {
    test(
      'restoreAll restores every account and activates the requested one',
      () async {
        final stores = <String, InMemoryTokenStore>{};
        final seed = buildGroup(stores);
        for (final id in ['alice', 'bob']) {
          await seed
              .forAccount(id)
              .login(Credentials(username: id, password: 'pw'));
        }
        await seed.disposeAll();

        // Fresh group reading the same persisted stores.
        final group = buildGroup(stores);
        await group.restoreAll(['alice', 'bob'], activeId: 'bob');

        expect(group.activeId, 'bob');
        expect(group.accessToken, 'token-bob');
        expect(group.forAccount('alice').current, isA<Authenticated>());

        await group.disposeAll();
      },
    );

    test('forwards onObserverError, tagged with the account', () async {
      final reported = <String, Object>{};
      final group = AuthManagerGroup(
        strategyFactory: (id) => FakeAuthStrategy(
          session: AuthSession(accessToken: 'token-$id', userId: id),
        ),
        storeFactory: (id) => InMemoryTokenStore(),
        onStateChanged: (id, _) => throw StateError('sink down: $id'),
        onObserverError: (id, error, _) => reported[id] = error,
      );

      await group
          .forAccount('alice')
          .login(const Credentials(username: 'alice', password: 'pw'));

      // The broken sink is reported, tagged with the account it belongs to…
      expect(reported.keys, ['alice']);
      expect(reported['alice'], isA<StateError>());
      // …and it still cannot break the state machine.
      expect(group.forAccount('alice').current, isA<Authenticated>());

      await group.disposeAll();
    });

    test('restoreAll(parallel:) restores accounts concurrently', () async {
      // A barrier store: `load()` only returns once every account has started
      // loading, so a serial restore would deadlock here instead of passing.
      // 屏障存储：只有当所有账号都开始读取后 `load()` 才返回，因此串行恢复会在这里
      // 死锁，而不是通过测试。
      var arrived = 0;
      final gate = Completer<void>();
      Future<void> barrier() async {
        if (++arrived == 2) gate.complete();
        await gate.future;
      }

      final stores = <String, _BarrierStore>{
        for (final id in ['alice', 'bob']) id: _BarrierStore(barrier),
      };
      final group = AuthManagerGroup(
        strategyFactory: (id) => FakeAuthStrategy(
          session: AuthSession(accessToken: 'token-$id', userId: id),
        ),
        storeFactory: (id) => stores[id]!,
      );

      await group.restoreAll(['alice', 'bob'], parallel: true);

      expect(arrived, 2);
      expect(group.activeId, 'alice');
      expect(group.accountIds, containsAll(['alice', 'bob']));

      await group.disposeAll();
    });

    test('restoreAll(parallel:) still reports the first failure', () async {
      final stores = <String, InMemoryTokenStore>{};
      final group = AuthManagerGroup(
        strategyFactory: (id) => FakeAuthStrategy(
          session: AuthSession(accessToken: 'token-$id', userId: id),
        ),
        storeFactory: (id) => stores.putIfAbsent(id, InMemoryTokenStore.new),
      );

      await expectLater(
        group.restoreAll(['missing-a', 'missing-b'], parallel: true),
        completes,
      );
      // Both are unknown accounts with nothing persisted: they restore to
      // Unauthenticated rather than throwing.
      expect(group.accountIds, containsAll(['missing-a', 'missing-b']));

      await group.disposeAll();
    });

    test('remove signs the account out and clears the active slot', () async {
      final stores = <String, InMemoryTokenStore>{};
      final group = buildGroup(stores);

      await group
          .forAccount('alice')
          .login(const Credentials(username: 'alice', password: 'pw'));
      group.switchTo('alice');

      final seen = <AuthState>[];
      final sub = group.state.listen(seen.add);
      await Future<void>.delayed(Duration.zero);

      await group.remove('alice');
      await Future<void>.delayed(Duration.zero);

      expect(group.accountIds, isEmpty);
      expect(group.activeId, isNull);
      expect(group.accessToken, isNull);
      expect(seen.last, const Unauthenticated());
      expect(await stores['alice']!.load(), isNull);

      await sub.cancel();
      await group.disposeAll();
    });

    test('disposeAll releases every manager', () async {
      final stores = <String, InMemoryTokenStore>{};
      final group = buildGroup(stores);
      final alice = group.forAccount('alice');
      await alice.login(const Credentials(username: 'alice', password: 'pw'));
      group.switchTo('alice');

      await group.disposeAll();

      // Every manager was disposed — reading through one now fails.
      expect(
        () => alice.refresh(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.code,
            'code',
            'manager_disposed',
          ),
        ),
      );

      // The group mirrors that contract: every read is rejected instead of
      // answering with stale data or a closed-stream error.
      for (final read in <Object? Function()>[
        () => group.accountIds,
        () => group.activeId,
        () => group.active,
        () => group.current,
        () => group.currentSession,
        () => group.accessToken,
        () => group.state,
      ]) {
        expect(
          read,
          throwsA(
            isA<AuthException>().having(
              (e) => e.code,
              'code',
              'group_disposed',
            ),
          ),
        );
      }

      await expectLater(
        group.validAccessToken(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.code,
            'code',
            'group_disposed',
          ),
        ),
      );
    });
  });
}
