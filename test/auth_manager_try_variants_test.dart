import 'dart:async';

import 'package:test/test.dart';
import 'package:zero_auth/zero_auth.dart';

import 'test_doubles.dart';

void main() {
  group('AuthManager — Result-returning variants', () {
    test('tryRegister returns Ok with the installed state', () async {
      final manager = AuthManager(strategy: FnStrategy());
      final result = await manager.tryRegister(testRegistration);
      expect(result.isOk, isTrue);
      expect(result.getOrThrow.session.accessToken, 'access');
      await manager.dispose();
    });

    test('tryRegister maps a strategy failure into Err and emits AuthError',
        () async {
      final manager = AuthManager(
        strategy: FnStrategy(
          registerFn: (_) async =>
              throw AuthException('rejected', code: 'invalid_credentials'),
        ),
      );
      final states = <AuthState>[];
      final sub = manager.state.listen(states.add);
      final result = await manager.tryRegister(testRegistration);
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
      final manager = AuthManager(strategy: FnStrategy());
      final ok = await manager.tryLoginWith((_) async => testSession('oauth'));
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
      final manager = AuthManager(strategy: FnStrategy(), tokenStore: store);
      await manager.login(testCredentials);
      final result = await manager.tryLogout();
      expect(result.isOk, isTrue);
      expect(manager.current, const Unauthenticated());
      expect(await store.load(), isNull);
      await manager.dispose();
    });

    test('tryLogout reports a failing clear as Err but still signs out',
        () async {
      final manager = AuthManager(
        strategy: FnStrategy(),
        tokenStore: FailingClearStore(),
      );
      await manager.login(testCredentials);
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
        strategy: FnStrategy(
          logoutFn: (_) async => throw StateError('offline'),
        ),
      );
      await manager.login(testCredentials);
      expect((await manager.tryLogout()).isOk, isTrue);
      expect(manager.current, const Unauthenticated());
      await manager.dispose();
    });

    test('tryUpdateSession keeps the session when the callback fails',
        () async {
      final manager = AuthManager(strategy: FnStrategy());
      await manager.login(testCredentials);
      final result = await manager.tryUpdateSession(
        (_) => throw StateError('profile service down'),
      );
      expect(result.isErr, isTrue);
      expect(manager.current, isA<Authenticated>());
      expect(manager.currentSession?.accessToken, 'access');
      await manager.dispose();
    });

    test('tryUpdateSession returns Ok with the replaced session', () async {
      final manager = AuthManager(strategy: FnStrategy());
      await manager.login(testCredentials);
      final result = await manager.tryUpdateSession(
        (current) => current.copyWith(displayName: 'New Name'),
      );
      expect(result.isOk, isTrue);
      expect(result.getOrThrow.session.displayName, 'New Name');
      await manager.dispose();
    });

    test('all try* variants return Err after dispose instead of throwing',
        () async {
      final manager = AuthManager(strategy: FnStrategy());
      await manager.dispose();
      final results = <Result<dynamic>>[
        await manager.tryRegister(testRegistration),
        await manager.tryLoginWith((_) async => testSession()),
        await manager.tryLogout(),
        await manager.tryUpdateSession((current) => current),
        await manager.tryLogin(testCredentials),
        await manager.tryRefresh(),
        await manager.tryRestore(),
      ];
      for (final result in results) {
        expect(result.isErr, isTrue);
        expect((result as Err<dynamic>).appException?.code, 'manager_disposed');
      }
    });
  });
}
