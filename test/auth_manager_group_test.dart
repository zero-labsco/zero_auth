import 'package:test/test.dart';
import 'package:zero_auth/zero_auth.dart';

import 'fake_strategy.dart';

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
        storeFactory: (accountId) => stores.putIfAbsent(
          accountId,
          InMemoryTokenStore.new,
        ),
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

      await group.forAccount('alice').login(
            const Credentials(username: 'alice', password: 'pw'),
          );

      expect(await stores['alice']!.load(), isNotNull);
      expect(await stores['bob']?.load(), isNull);

      await group.disposeAll();
    });
  });

  group('AuthManagerGroup — active account', () {
    test('active manager drives accessToken and currentSession', () async {
      final stores = <String, InMemoryTokenStore>{};
      final group = buildGroup(stores);

      await group.forAccount('alice').login(
            const Credentials(username: 'alice', password: 'pw'),
          );
      await group.forAccount('bob').login(
            const Credentials(username: 'bob', password: 'pw'),
          );

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

      await group.forAccount('alice').login(
            const Credentials(username: 'alice', password: 'pw'),
          );
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

      await group.forAccount('alice').login(
            const Credentials(username: 'alice', password: 'pw'),
          );
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
    test('restoreAll restores every account and activates the requested one',
        () async {
      final stores = <String, InMemoryTokenStore>{};
      final seed = buildGroup(stores);
      for (final id in ['alice', 'bob']) {
        await seed.forAccount(id).login(
              Credentials(username: id, password: 'pw'),
            );
      }
      await seed.disposeAll();

      // Fresh group reading the same persisted stores.
      final group = buildGroup(stores);
      await group.restoreAll(['alice', 'bob'], activeId: 'bob');

      expect(group.activeId, 'bob');
      expect(group.accessToken, 'token-bob');
      expect(group.forAccount('alice').current, isA<Authenticated>());

      await group.disposeAll();
    });

    test('remove signs the account out and clears the active slot', () async {
      final stores = <String, InMemoryTokenStore>{};
      final group = buildGroup(stores);

      await group.forAccount('alice').login(
            const Credentials(username: 'alice', password: 'pw'),
          );
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

      await group.forAccount('alice').login(
            const Credentials(username: 'alice', password: 'pw'),
          );
      group.switchTo('alice');

      await group.disposeAll();

      expect(group.accountIds, isEmpty);
      expect(group.active, isNull);
      expect(group.accessToken, isNull);
    });
  });
}
