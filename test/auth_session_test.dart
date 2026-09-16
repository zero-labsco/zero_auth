import 'package:test/test.dart';
import 'package:zero_auth/zero_auth.dart';

void main() {
  group('RefreshToken', () {
    test('equality is value-based', () {
      expect(const RefreshToken('a'), const RefreshToken('a'));
      expect(const RefreshToken('a'), isNot(const RefreshToken('b')));
    });
  });

  group('SessionHandle', () {
    test('equality is value-based', () {
      expect(
        const SessionHandle(userId: 'u1'),
        const SessionHandle(userId: 'u1'),
      );
      expect(
        const SessionHandle(userId: 'u1'),
        isNot(const SessionHandle(userId: 'u2')),
      );
    });
  });

  group('AuthSession', () {
    test('isExpired is false when expiresAt is null', () {
      const session = AuthSession(accessToken: 'a');
      expect(session.isExpired, isFalse);
    });

    test('isExpired is true only after expiresAt', () {
      final past = AuthSession(
        accessToken: 'a',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      final future = AuthSession(
        accessToken: 'a',
        expiresAt: DateTime.now().add(const Duration(minutes: 1)),
      );
      expect(past.isExpired, isTrue);
      expect(future.isExpired, isFalse);
    });

    test('equality ignores claims but compares identity fields', () {
      const a = AuthSession(
        accessToken: 'a',
        userId: 'u1',
        displayName: 'User',
      );
      const b = AuthSession(
        accessToken: 'a',
        userId: 'u1',
        displayName: 'User',
      );
      const c = AuthSession(
        accessToken: 'a',
        userId: 'u2',
        displayName: 'User',
      );
      expect(a, b);
      expect(a, isNot(c));
    });

    test('carries optional refresh token, claims and identity', () {
      const session = AuthSession(
        accessToken: 'a',
        refreshToken: RefreshToken('r'),
        userId: 'u1',
        displayName: 'User',
        claims: {'role': 'admin'},
      );
      expect(session.refreshToken, const RefreshToken('r'));
      expect(session.userId, 'u1');
      expect(session.displayName, 'User');
      expect(session.claims, {'role': 'admin'});
    });
  });

  group('AuthState', () {
    test('isAuthenticated is only true for Authenticated', () {
      expect(const Unauthenticated().isAuthenticated, isFalse);
      expect(const Authenticating().isAuthenticated, isFalse);
      expect(AuthError(AuthException('e')).isAuthenticated, isFalse);
      expect(
        const Authenticated(AuthSession(accessToken: 'a')).isAuthenticated,
        isTrue,
      );
    });

    test('AuthError holds the mapped AppException', () {
      final error = AuthException('boom', code: 'x');
      expect(AuthError(error).error, error);
    });

    test('AuthFail carries message, code and cause', () {
      final cause = Exception('root');
      const fail = AuthFail('msg', code: 'c', cause: null);
      expect(fail.message, 'msg');
      expect(fail.code, 'c');
      // cause is preserved when provided
      final failWithCause = AuthFail('msg', code: 'c', cause: cause);
      expect(failWithCause.cause, cause);
    });
  });
}
