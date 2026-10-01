import 'package:test/test.dart';
import 'package:zero_auth/zero_auth.dart';

void main() {
  group('AuthState', () {
    test('value equality', () {
      final a = Authenticated(AuthSession(accessToken: 'x'));
      final b = Authenticated(AuthSession(accessToken: 'x'));
      expect(a, equals(b));
      expect(const Unauthenticated(), const Unauthenticated());
      expect(const Authenticating(), const Authenticating());
    });

    test('isAuthenticated reflects the state', () {
      final s = AuthSession(accessToken: 'x');
      expect(const Unauthenticated().isAuthenticated, isFalse);
      expect(const Authenticating().isAuthenticated, isFalse);
      expect(Authenticated(s).isAuthenticated, isTrue);
      expect(Refreshing(s).isAuthenticated, isTrue);
      expect(LoggingOut(s).isAuthenticated, isFalse);
    });

    test('isBusy covers every in-flight state', () {
      final s = AuthSession(accessToken: 'x');
      expect(const Unauthenticated().isBusy, isFalse);
      expect(Authenticated(s).isBusy, isFalse);
      expect(AuthError(AuthException('e')).isBusy, isFalse);
      expect(const Authenticating().isBusy, isTrue);
      expect(Refreshing(s).isBusy, isTrue);
      expect(LoggingOut(s).isBusy, isTrue);
    });

    test('Refreshing and LoggingOut have value equality', () {
      final a = AuthSession(accessToken: 'x');
      final b = AuthSession(accessToken: 'x');
      expect(Refreshing(a), Refreshing(b));
      expect(LoggingOut(a), LoggingOut(b));
      expect(Refreshing(a), isNot(LoggingOut(a)));
      expect(Refreshing(a).hashCode, Refreshing(b).hashCode);
    });

    test('AuthError holds the exception', () {
      final e = AuthException('boom', code: 'x');
      expect(AuthError(e).error, e);
    });

    test('AuthFail carries message / code / cause', () {
      const f = AuthFail('m', code: 'c', cause: 'k');
      expect(f.message, 'm');
      expect(f.code, 'c');
      expect(f.cause, 'k');
    });
  });

  group('Restoring', () {
    test('is busy but not authenticated', () {
      const state = Restoring();
      expect(state.isBusy, isTrue);
      // No session yet: a UI must not treat this as signed in.
      expect(state.isAuthenticated, isFalse);
      expect(state.session, isNull);
    });

    test('compares and hashes by value', () {
      expect(const Restoring(), const Restoring());
      expect(const Restoring().hashCode, const Restoring().hashCode);
      expect(const Restoring() == const Unauthenticated(), isFalse);
      expect(const Restoring() == const Authenticating(), isFalse);
    });

    test('is distinct from every other state', () {
      final s = AuthSession(accessToken: 'x');
      final others = <AuthState>[
        const Unauthenticated(),
        const Authenticating(),
        Authenticated(s),
        Refreshing(s),
        LoggingOut(s),
        Restoring(),
      ];
      // Distinct hash codes keep the sealed hierarchy usable as a key.
      expect(
        others.map((e) => e.runtimeType).toSet().length,
        others.length,
      );
    });
  });
}
