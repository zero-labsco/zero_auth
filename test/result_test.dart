import 'package:test/test.dart';
import 'package:zero_auth/zero_auth.dart';

void main() {
  group('Ok', () {
    test('getOrThrow returns the value', () {
      expect(const Ok<int>(42).getOrThrow, 42);
    });

    test('map transforms the success value', () {
      expect(const Ok<int>(2).map((v) => v * 2), const Ok<int>(4));
    });

    test('isOk / isErr flags', () {
      expect(const Ok<int>(1).isOk, isTrue);
      expect(const Ok<int>(1).isErr, isFalse);
    });

    test('equality is value-based', () {
      expect(const Ok<int>(1), const Ok<int>(1));
      expect(const Ok<int>(1), isNot(const Ok<int>(2)));
      expect(const Ok<int>(1), isNot(const Err<int>(1)));
    });
  });

  group('Err', () {
    test('getOrThrow throws the contained error', () {
      final error = AuthException('boom', code: 'x');
      expect(() => Err<int>(error).getOrThrow, throwsA(error));
    });

    test('map leaves the failure untouched', () {
      final error = AuthException('boom');
      expect(Err<int>(error).map((v) => v * 2), Err<int>(error));
    });

    test('isOk / isErr flags', () {
      expect(Err<int>(AuthException('e')).isOk, isFalse);
      expect(Err<int>(AuthException('e')).isErr, isTrue);
    });

    test('equality is error-based', () {
      final a = AuthException('a');
      final b = AuthException('b');
      expect(Err<int>(a), Err<int>(a));
      expect(Err<int>(a), isNot(Err<int>(b)));
    });
  });
}
