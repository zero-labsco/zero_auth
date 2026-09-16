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
      expect(const Unauthenticated().isAuthenticated, isFalse);
      expect(const Authenticating().isAuthenticated, isFalse);
      expect(
        const Authenticated(AuthSession(accessToken: 'x')).isAuthenticated,
        isTrue,
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
