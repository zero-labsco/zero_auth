import 'package:test/test.dart';
import 'package:zero_auth/zero_auth.dart';

/// Concrete subclass so the abstract [AppException] can be exercised directly.
final class _TestException extends AppException {
  const _TestException(super.message, {super.code, super.cause});
}

void main() {
  group('AppException', () {
    test('toString omits the code when absent', () {
      expect(
        const _TestException('something failed').toString(),
        'AppException: something failed',
      );
    });

    test('toString includes the code when present', () {
      expect(
        const _TestException('bad', code: 'invalid_credentials').toString(),
        'AppException(invalid_credentials): bad',
      );
    });

    test('preserves message, code and cause', () {
      final cause = Exception('root');
      final ex = _TestException('msg', code: 'c', cause: cause);
      expect(ex.message, 'msg');
      expect(ex.code, 'c');
      expect(ex.cause, cause);
    });
  });

  group('AuthException', () {
    test('fromFail maps message, code and cause', () {
      final cause = Exception('root');
      final fail = AuthFail('nope', code: 'invalid_credentials', cause: cause);
      final ex = AuthException.fromFail(fail);
      expect(ex.message, 'nope');
      expect(ex.code, 'invalid_credentials');
      expect(ex.cause, cause);
      expect(ex.fail, fail);
    });

    test('convenience constructor builds an AuthFail internally', () {
      final ex = AuthException('denied', code: 'forbidden');
      expect(ex.message, 'denied');
      expect(ex.code, 'forbidden');
      expect(ex.fail, isA<AuthFail>());
    });
  });
}
