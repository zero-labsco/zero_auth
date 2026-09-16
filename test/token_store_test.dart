import 'package:test/test.dart';
import 'package:zero_auth/zero_auth.dart';

void main() {
  group('InMemoryTokenStore', () {
    test('save / load / clear', () async {
      final store = InMemoryTokenStore();
      expect(await store.load(), isNull);

      const session = AuthSession(accessToken: 'a', userId: 'u');
      await store.save(session);
      expect(await store.load(), session);

      await store.clear();
      expect(await store.load(), isNull);
    });
  });
}
