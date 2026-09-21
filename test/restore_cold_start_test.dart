import 'package:test/test.dart';
import 'package:zero_auth/zero_auth.dart';

/// Cold-start with the backend offline.
///
/// In a unit test we cannot literally kill the OS process, so a persistent
/// store is *simulated* by reusing one [TokenStore] instance across two
/// [AuthManager] instances: the first logs in (session hits "disk"), then a
/// fresh manager is built on the same store — that is the restart — while the
/// strategy now throws, modelling an unreachable backend.
///
/// A real app would back the store with `SecureTokenStore`
/// (flutter_secure_storage) from `example/lib/secure_token_store.dart`; the
/// `InMemoryTokenStore` used by the example app does NOT survive a real
/// restart, so it cannot demonstrate this scenario on its own.
/// 断网冷启动。
///
/// 单元测试里无法真正杀掉 OS 进程，所以用「同一个 [TokenStore] 实例被两个
/// [AuthManager] 复用」来模拟持久化存储跨重启存活：第一个管理器登录（会话落盘），
/// 再用同一份存储新建一个管理器 —— 这就是重启 —— 而此时 strategy 抛错，模拟后端不可达。
///
/// 真实 app 应当用 `example/lib/secure_token_store.dart` 里的 `SecureTokenStore`
/// （基于 flutter_secure_storage）来支撑存储；示例默认用的 `InMemoryTokenStore`
/// 不跨重启存活，因此本身演示不出该场景。
void main() {
  const credentials = Credentials(username: 'user', password: 'user');
  final now = DateTime.utc(2026, 1, 1, 12);

  group('cold start with backend offline', () {
    test('keeps the persisted session instead of signing the user out',
        () async {
      final store = _DiskStore();

      // Phase 1 — previous run, backend reachable, user logs in.
      // 阶段一：上一次运行，后端可达，用户登录。
      final live = _Backend(ok: true, now: now);
      final m1 =
          AuthManager(strategy: live, tokenStore: store, clock: () => now);
      await m1.login(credentials);
      expect(await store.load(), isNotNull);
      await m1.dispose();

      // Phase 2 — app restarted, backend down, fresh manager on the same store.
      // 阶段二：应用重启、后端宕机，用同一份存储新建管理器。
      final offline = _Backend(ok: false, now: now);
      final m2 =
          AuthManager(strategy: offline, tokenStore: store, clock: () => now);

      await m2.restore();

      // The fix: a transient backend failure at cold start must NOT clear the
      // store or push the user to Unauthenticated.
      // 修复点：冷启动时的瞬时后端失败绝不能清空存储，也不能把用户推到未登录。
      expect(m2.current, isA<Authenticated>());
      expect(m2.currentSession?.accessToken, 'persisted-access');
      expect(await store.load(), isNotNull);
      await m2.dispose();
    });

    test('validAccessToken retries the renewal and keeps the session',
        () async {
      final store = _DiskStore();

      final m1 = AuthManager(
        strategy: _Backend(ok: true, now: now),
        tokenStore: store,
        clock: () => now,
      );
      await m1.login(credentials);
      await m1.dispose();

      // Backend still down after the restart.
      // 重启后后端仍然宕机。
      final offline = _Backend(ok: false, now: now);
      final m2 =
          AuthManager(strategy: offline, tokenStore: store, clock: () => now);
      await m2.restore();
      expect(m2.current, isA<Authenticated>());

      // The expired token cannot be made valid: refresh fails, validAccessToken
      // returns null, but the session is kept so a later attempt can retry.
      // 过期令牌无法变有效：刷新失败，validAccessToken 返回 null，但会话被保留，
      // 以便后续重试。
      expect(await m2.validAccessToken(), isNull);
      expect(m2.current, isA<Authenticated>());

      // Backend recovers: the next attempt renews.
      // 后端恢复：下一次尝试完成续期。
      offline.ok = true;
      expect(await m2.validAccessToken(), 'refreshed-access');
      expect(m2.current, isA<Authenticated>());
      await m2.dispose();
    });
  });
}

/// Strategy that answers or fails as a whole, modelling a reachable/unreachable
/// backend. Login/refresh return an *expired* session so cold-start renewal is
/// actually exercised.
/// 整体可用或整体失败的 strategy，模拟后端可达/不可达。login/refresh 返回的是
/// 已过期会话，从而真正走到冷启动续期路径。
final class _Backend implements AuthStrategy {
  _Backend({required this.ok, required this.now});

  bool ok;
  final DateTime now;

  AuthSession get _expiredSession => AuthSession(
        accessToken: 'persisted-access',
        refreshToken: const RefreshToken('refresh'),
        expiresAt: now.subtract(const Duration(minutes: 5)),
        userId: 'u1',
        displayName: 'User',
      );

  @override
  Future<AuthSession> login(Credentials credentials) async {
    if (!ok) throw AuthException('offline', code: 'network_unreachable');
    return _expiredSession;
  }

  @override
  Future<AuthSession> register(RegistrationInput input) async =>
      _expiredSession;

  @override
  Future<void> logout(SessionHandle handle) async {}

  @override
  Future<AuthSession> refresh(RefreshToken token) async {
    if (!ok) throw AuthException('offline', code: 'network_unreachable');
    return _expiredSession.copyWith(accessToken: 'refreshed-access');
  }
}

/// A store that survives "process restart" because it is the same object handed
/// to the new manager — standing in for disk/secure storage.
/// 跨「进程重启」存活的存储：它被同一个对象交给了新管理器，等价于磁盘/安全存储。
final class _DiskStore implements TokenStore {
  AuthSession? _value;

  @override
  Future<void> save(AuthSession session) async => _value = session;

  @override
  Future<AuthSession?> load() async => _value;

  @override
  Future<void> clear() async => _value = null;
}
