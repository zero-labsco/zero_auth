import 'auth_session.dart';

/// Persistence boundary for the active session.
/// 当前会话的持久化边界。
abstract class TokenStore {
  /// Persist the active session.
  /// 持久化当前会话。
  Future<void> save(AuthSession session);

  /// Load the persisted session, or `null` if none.
  /// 载入持久化会话，无则返回 `null`。
  Future<AuthSession?> load();

  /// Remove any persisted session.
  /// 移除持久化会话。
  Future<void> clear();
}

/// In-memory store used by default and in tests. Not durable across restarts.
/// 默认与测试用的内存存储，重启不保留。
final class InMemoryTokenStore implements TokenStore {
  AuthSession? _session;

  @override
  Future<void> save(AuthSession session) async => _session = session;

  @override
  Future<AuthSession?> load() async => _session;

  @override
  Future<void> clear() async => _session = null;
}
