import 'package:test/test.dart';
import 'package:zero_auth/zero_auth.dart';

import 'fake_strategy.dart';

void main() {
  group('AuthStrategy (FakeAuthStrategy)', () {
    test('login returns a session', () async {
      final s = FakeAuthStrategy();
      final session =
          await s.login(const Credentials(username: 'a', password: 'b'));
      expect(session.accessToken, isNotEmpty);
      expect(s.logoutCalled, isFalse);
    });

    test('logout sets the flag', () async {
      final s = FakeAuthStrategy();
      await s.logout(const SessionHandle(userId: 'u1'));
      expect(s.logoutCalled, isTrue);
    });
  });
}
