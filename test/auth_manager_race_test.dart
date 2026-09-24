import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:zero_auth/zero_auth.dart';

/// Regression tests for the extreme timing interleavings once listed as R2 in
/// `KNOWN_RISKS.md`: a renewal landing in the same microtask as a `logout()`, or
/// still in flight when `dispose()` arrives.
///
/// They are deterministic on purpose — the strategy gates the renewal behind a
/// [Completer] instead of racing the event loop, so nothing here can go flaky.
/// 针对 `KNOWN_RISKS.md` 中曾列为 R2 的极端时序交错的回归测试：续期与 `logout()`
/// 在同一微任务落地，或 `dispose()` 到达时续期仍在飞行中。
///
/// 这里是刻意为确定性的 —— 策略用 [Completer] 把续期挡住，而不是去和事件循环赛跑，
/// 因此不会出现 flaky。
void main() {
  Future<void> pump() => Future<void>.delayed(Duration.zero);

  group('a late renewal can never win', () {
    test('a renewal landing after logout cannot resurrect the session',
        () async {
      final strategy = _GateStrategy();
      final store = InMemoryTokenStore();
      final manager = AuthManager(strategy: strategy, tokenStore: store);

      await manager.login(_credentials);

      // Start a renewal and hold it open.
      final renewal = manager.refresh();
      await pump();
      expect(manager.current, isA<Refreshing>());

      // The user signs out while that renewal is still in flight.
      await manager.logout();
      expect(manager.current, const Unauthenticated());

      // …and now the renewal lands.
      strategy.complete(_GateStrategy.gated('late'));
      await expectLater(renewal, throwsA(isA<AuthException>()));

      expect(manager.current, const Unauthenticated());
      expect(manager.currentSession, isNull);
      expect(await store.load(), isNull);

      await manager.dispose();
    });

    test('a renewal in flight when dispose lands completes quietly', () {
      FakeAsync().run((async) {
        final strategy = _GateStrategy();
        final store = _RecordingStore();
        final manager = AuthManager(strategy: strategy, tokenStore: store);

        unawaited(manager.login(_credentials));
        async.flushMicrotasks();

        final renewal = manager.refresh();
        unawaited(manager.dispose());
        async.flushMicrotasks();
        final savesAtDispose = store.saveCount;

        // The renewal lands after the manager is gone: it fails instead of
        // writing, and nothing escapes as an unhandled async error.
        var failed = false;
        renewal.catchError((Object _) {
          failed = true;
          return AuthSession(accessToken: 'unused');
        });
        strategy.complete(_GateStrategy.gated('late'));
        async.flushMicrotasks();

        expect(failed, isTrue);
        // The late session was never persisted.
        expect(store.saveCount, savesAtDispose);
      });
    });
  });
}

const Credentials _credentials = Credentials(username: 'u', password: 'p');

/// A store that counts writes, so a test can tell "nothing was persisted" apart
/// from "the same value was persisted again".
/// 记录写入次数的存储，便于测试区分「没有写入」与「又写了一次相同的值」。
final class _RecordingStore implements TokenStore {
  AuthSession? value;
  int saveCount = 0;

  @override
  Future<void> save(AuthSession session) async {
    saveCount++;
    value = session;
  }

  @override
  Future<AuthSession?> load() async => value;

  @override
  Future<void> clear() async => value = null;
}

/// A strategy whose `refresh` never completes until [complete] is called, so a
/// test can decide exactly when a renewal lands.
/// 其 `refresh` 在调用 [complete] 之前永不完成的策略，便于测试精确控制续期落地的时刻。
final class _GateStrategy implements AuthStrategy {
  Completer<AuthSession>? _gate;
  int refreshCount = 0;

  static AuthSession gated(String token) => AuthSession(
        accessToken: token,
        refreshToken: const RefreshToken('refresh'),
        userId: 'u1',
      );

  void complete(AuthSession session) => _gate?.complete(session);

  @override
  Future<AuthSession> login(Credentials credentials) async => gated('a');

  @override
  Future<AuthSession> register(RegistrationInput input) async => gated('a');

  @override
  Future<void> logout(SessionHandle handle) async {}

  @override
  Future<AuthSession> refresh(RefreshToken token) {
    refreshCount++;
    return (_gate ??= Completer<AuthSession>()).future;
  }
}
