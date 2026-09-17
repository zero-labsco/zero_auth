import 'package:test/test.dart';
import 'package:zero_auth/zero_auth.dart';

void main() {
  group('AuthState', () {
    test('value equality', () {
      const a = Authenticated(AuthSession(accessToken: 'x'));
      const b = Authenticated(AuthSession(accessToken: 'x'));
      expect(a, equals(b));
      expect(const Unauthenticated(), const Unauthenticated());
      expect(const Authenticating(), const Authenticating());
    });

    test('isAuthenticated reflects the state', () {
      const s = AuthSession(accessToken: 'x');
      expect(const Unauthenticated().isAuthenticated, isFalse);
      expect(const Authenticating().isAuthenticated, isFalse);
      expect(const Authenticated(s).isAuthenticated, isTrue);
      expect(const Refreshing(s).isAuthenticated, isTrue);
      expect(const LoggingOut(s).isAuthenticated, isFalse);
    });

    test('isBusy covers every in-flight state', () {
      const s = AuthSession(accessToken: 'x');
      expect(const Unauthenticated().isBusy, isFalse);
      expect(const Authenticated(s).isBusy, isFalse);
      expect(AuthError(AuthException('e')).isBusy, isFalse);
      expect(const Authenticating().isBusy, isTrue);
      expect(const Refreshing(s).isBusy, isTrue);
      expect(const LoggingOut(s).isBusy, isTrue);
    });

    test('Refreshing and LoggingOut have value equality', () {
      const a = AuthSession(accessToken: 'x');
      const b = AuthSession(accessToken: 'x');
      expect(const Refreshing(a), const Refreshing(b));
      expect(const LoggingOut(a), const LoggingOut(b));
      expect(const Refreshing(a), isNot(const LoggingOut(a)));
      expect(
        const Refreshing(a).hashCode,
        const Refreshing(b).hashCode,
      );
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
}
