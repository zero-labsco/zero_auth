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
      final session = AuthSession(accessToken: 'a');
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

    test('equality compares the identity fields', () {
      final a = AuthSession(
        accessToken: 'a',
        userId: 'u1',
        displayName: 'User',
      );
      final b = AuthSession(
        accessToken: 'a',
        userId: 'u1',
        displayName: 'User',
      );
      final c = AuthSession(
        accessToken: 'a',
        userId: 'u2',
        displayName: 'User',
      );
      expect(a, b);
      expect(a, isNot(c));
    });

    test('carries optional refresh token, claims and identity', () {
      final session = AuthSession(
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

  group('AuthSession serialization', () {
    test('toJson / fromJson round-trips all fields', () {
      final expiresAt = DateTime.utc(2030, 1, 1, 12, 0, 0);
      final session = AuthSession(
        accessToken: 'a',
        refreshToken: RefreshToken('r'),
        expiresAt: expiresAt,
        userId: 'u1',
        displayName: 'User',
        claims: {'role': 'admin', 'n': 2},
      );

      final json = session.toJson();
      final restored = AuthSession.fromJson(json);

      expect(restored.accessToken, 'a');
      expect(restored.refreshToken, const RefreshToken('r'));
      expect(restored.expiresAt, expiresAt);
      expect(restored.userId, 'u1');
      expect(restored.displayName, 'User');
      expect(restored.claims, {'role': 'admin', 'n': 2});
    });

    test('omits null fields', () {
      final session = AuthSession(accessToken: 'a');
      final json = session.toJson();

      expect(json.containsKey('refreshToken'), isFalse);
      expect(json.containsKey('expiresAt'), isFalse);
      expect(json.containsKey('userId'), isFalse);
      expect(json.containsKey('displayName'), isFalse);
      expect(json.containsKey('claims'), isFalse);
      expect(AuthSession.fromJson(json).accessToken, 'a');
    });
  });

  group('AuthState', () {
    test('isAuthenticated is true for Authenticated and Refreshing', () {
      final s = AuthSession(accessToken: 'a');
      expect(const Unauthenticated().isAuthenticated, isFalse);
      expect(const Authenticating().isAuthenticated, isFalse);
      expect(AuthError(AuthException('e')).isAuthenticated, isFalse);
      expect(Authenticated(s).isAuthenticated, isTrue);
      // Refreshing keeps the previous session usable, so it stays authenticated.
      // Refreshing 期间旧会话仍然可用，因此仍算已认证。
      expect(Refreshing(s).isAuthenticated, isTrue);
      expect(LoggingOut(s).isAuthenticated, isFalse);
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

  group('claims immutability', () {
    test('mutating the map handed in does not change the session', () {
      final claims = <String, Object?>{'role': 'admin'};
      final session = AuthSession(accessToken: 'a', claims: claims);

      claims['role'] = 'user';
      claims['extra'] = 1;

      // A session is a value object: what the caller does to their own map
      // afterwards is none of its business.
      expect(session.claims, {'role': 'admin'});
    });

    test('claims cannot be modified through the session', () {
      final session = AuthSession(
        accessToken: 'a',
        claims: <String, Object?>{'role': 'admin'},
      );

      expect(
        () => session.claims?['role'] = 'user',
        throwsA(isA<UnsupportedError>()),
      );
      expect(() => session.claims?.clear(), throwsA(isA<UnsupportedError>()));
      expect(
        () => session.claims?.remove('role'),
        throwsA(isA<UnsupportedError>()),
      );
      expect(session.claims, {'role': 'admin'});
    });

    test('nested maps and lists are frozen too', () {
      final nested = <String, Object?>{'n': 1};
      final list = <Object?>[1, 2];
      final session = AuthSession(
        accessToken: 'a',
        claims: <String, Object?>{
          'nested': nested,
          'list': list,
        },
      );

      nested['n'] = 2;
      list.add(3);

      expect(session.claims?['nested'], {'n': 1});
      expect(session.claims?['list'], [1, 2]);
      expect(
        () => (session.claims?['list'] as List).add(4),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('claims still compare by content against a plain map', () {
      // Freezing must not silently turn `session.claims == {...}` into an
      // identity check that always fails.
      final session = AuthSession(
        accessToken: 'a',
        claims: <String, Object?>{
          'role': 'admin',
          'n': <Object?>[1],
        },
      );

      expect(
        session.claims ==
            {
              'role': 'admin',
              'n': <Object?>[1],
            },
        isTrue,
      );
      expect(session.claims == {'role': 'admin'}, isFalse);
    });

    test('nested containers compare by content too', () {
      // The same rule the top-level map follows, one level down: freezing must
      // not change how a nested value compares against a plain literal.
      // 顶层映射遵循的规则向下延伸一层：冻结不能改变嵌套值与普通字面量的比较结果。
      final session = AuthSession(
        accessToken: 'a',
        claims: <String, Object?>{
          'address': <String, Object?>{'city': 'x'},
          'roles': <Object?>['admin', 'dev'],
        },
      );

      expect(session.claims?['address'], <String, Object?>{'city': 'x'});
      expect(
        session.claims?['address'] == <String, Object?>{'city': 'x'},
        isTrue,
      );
      expect(
        session.claims?['address'] == <String, Object?>{'city': 'y'},
        isFalse,
      );
      expect(session.claims?['roles'], <Object?>['admin', 'dev']);
      expect(session.claims?['roles'] == <Object?>['admin', 'dev'], isTrue);
      expect(session.claims?['roles'] == <Object?>['admin'], isFalse);

      // A map is never equal to a list, frozen or not.
      expect(session.claims?['address'] == <Object?>['admin'], isFalse);
    });

    test('nested containers cannot be mutated', () {
      final session = AuthSession(
        accessToken: 'a',
        claims: <String, Object?>{
          'address': <String, Object?>{'city': 'x'},
          'roles': <Object?>['admin'],
        },
      );

      expect(
        () => (session.claims?['address'] as Map)['city'] = 'y',
        throwsA(isA<UnsupportedError>()),
      );
      expect(
        () => (session.claims?['roles'] as List).add('ops'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('nested containers keep a stable, content-based hash', () {
      AuthSession build(Object? nested) =>
          AuthSession(accessToken: 'a', claims: <String, Object?>{'n': nested});

      final mapA = build(<String, Object?>{'k': 'v'});
      final mapB = build(<String, Object?>{'k': 'v'});
      expect(mapA.hashCode, mapB.hashCode);

      final listA = build(<Object?>[1, 2]);
      final listB = build(<Object?>[1, 2]);
      expect(listA.hashCode, listB.hashCode);

      expect(
        build(<String, Object?>{'k': 'v'}).hashCode,
        isNot(build(<String, Object?>{'k': 'w'}).hashCode),
      );
    });

    test('nested containers survive serialization', () {
      final session = AuthSession(
        accessToken: 'a',
        claims: <String, Object?>{
          'address': <String, Object?>{'city': 'x'},
          'roles': <Object?>['admin'],
        },
      );

      final restored = AuthSession.fromJson(session.toJson());

      expect(restored.claims?['address'], <String, Object?>{'city': 'x'});
      expect(restored.claims?['roles'], <Object?>['admin']);
      expect(restored, session);
    });

    test('the hash stays stable and matches an equal session', () {
      final a = AuthSession(
        accessToken: 'a',
        claims: <String, Object?>{'role': 'admin'},
      );
      final b = AuthSession(
        accessToken: 'a',
        claims: <String, Object?>{'role': 'admin'},
      );

      expect(a.hashCode, b.hashCode);
      // Cached: identical on every read, and equal sessions share a bucket.
      expect(a.hashCode, a.hashCode);
      expect({a, b}.length, 1);
    });

    test('sessions with different claims are different values', () {
      final a = AuthSession(
        accessToken: 'a',
        claims: <String, Object?>{'role': 'admin'},
      );
      final b = AuthSession(
        accessToken: 'a',
        claims: <String, Object?>{'role': 'user'},
      );

      expect(a == b, isFalse);
      expect({a, b}.length, 2);
    });
  });
}
