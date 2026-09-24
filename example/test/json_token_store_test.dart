import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_auth/zero_auth.dart';
import 'package:zero_auth_example/json_token_store.dart';

/// The reference stores in `lib/` are consumer-facing sample code: they ship
/// without being wired into `main.dart`, so nothing else would catch a
/// regression in them. This file keeps the file-backed one honest.
///
/// `SecureTokenStore` is deliberately not covered: it needs the
/// `flutter_secure_storage` platform channel, which has no implementation in a
/// unit test.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('zero_auth_store'));

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  AuthSession session([String token = 'access']) => AuthSession(
        accessToken: token,
        refreshToken: const RefreshToken('refresh'),
        expiresAt: DateTime.parse('2030-01-01T00:00:00.000Z'),
        userId: 'u1',
        displayName: 'User One',
        claims: const {'role': 'admin'},
      );

  JsonTokenStore store() => JsonTokenStore(File('${dir.path}/session.json'));

  test('a missing file reads as "not signed in"', () async {
    expect(await store().load(), isNull);
  });

  test('round-trips every field', () async {
    final s = store();
    await s.save(session());

    final loaded = await s.load();
    expect(loaded, isNotNull);
    expect(loaded!.accessToken, 'access');
    expect(loaded.refreshToken?.value, 'refresh');
    expect(loaded.expiresAt, DateTime.parse('2030-01-01T00:00:00.000Z'));
    expect(loaded.userId, 'u1');
    expect(loaded.displayName, 'User One');
    expect(loaded.claims, {'role': 'admin'});
  });

  test('save overwrites the previous session', () async {
    final s = store();
    await s.save(session('first'));
    await s.save(session('second'));

    expect((await s.load())?.accessToken, 'second');
  });

  test('clear removes the file and leaves nothing behind', () async {
    final s = store();
    await s.save(session());
    await s.clear();

    expect(await s.load(), isNull);
    expect(File('${dir.path}/session.json').existsSync(), isFalse);
  });

  test('clear is safe when nothing was ever saved', () async {
    await expectLater(store().clear(), completes);
  });

  test('corrupt contents read as "not signed in" instead of throwing',
      () async {
    final file = File('${dir.path}/session.json')
      ..writeAsStringSync('{"accessToken": 42}');
    // A partial write or a hand-edited file must not crash a cold start.
    expect(await JsonTokenStore(file).load(), isNull);
  });

  test('a session without a refresh token survives', () async {
    final s = store();
    await s.save(const AuthSession(accessToken: 'access'));

    final loaded = await s.load();
    expect(loaded?.refreshToken, isNull);
    expect(loaded?.expiresAt, isNull);
  });
}
