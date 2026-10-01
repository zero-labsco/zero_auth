import 'token_service.dart';
import 'user_store.dart';

/// The outcome of a successful rotation.
final class Rotation {
  const Rotation({required this.user, required this.refreshToken});

  final UserRecord user;

  /// The replacement refresh token; the presented one is now dead.
  final String refreshToken;
}

/// Server-side bookkeeping for refresh tokens.
///
/// Refresh tokens are rotated on every use: the presented token is consumed and
/// a replacement is issued in the same family. Presenting an already-consumed
/// token means a replay or theft, so the whole family is revoked. This is the
/// standard mitigation for stolen refresh tokens, and it is why the client must
/// persist the replacement token instead of reusing the old one.
final class RefreshTokenStore {
  RefreshTokenStore({required this.tokens, required this.ttl});

  final TokenService tokens;
  final Duration ttl;

  final Map<String, _Entry> _active = {};

  /// Already-consumed token ids, mapped to their family and to the instant the
  /// replay window for that id closes.
  ///
  /// Bounded on purpose: a rotation happens on every refresh, so an unbounded
  /// map here would grow for as long as the process lives.
  /// 已使用的令牌 id，映射到其 family 以及该 id 的重放窗口关闭时刻。
  ///
  /// 刻意设有上限：每次续期都会发生轮换，若这里的映射无界，就会随进程存活时间一直增长。
  final Map<String, _Consumed> _consumed = {};

  /// Issues a refresh token for [user], optionally continuing a family.
  String issue(UserRecord user, {String? family}) {
    final tokenFamily = family ?? tokens.newId(8);
    final jti = tokens.newId();
    final token = tokens.sign(
      subject: user.id,
      displayName: user.displayName,
      type: TokenType.refresh,
      ttl: ttl,
      tokenId: jti,
      family: tokenFamily,
    );
    _active[jti] = _Entry(
      userId: user.id,
      displayName: user.displayName,
      family: tokenFamily,
      expiresAt: DateTime.now().add(ttl),
    );
    return token;
  }

  /// Consumes [token] and returns its replacement.
  ///
  /// Returns `null` when the token is unknown, expired, revoked or replayed.
  Rotation? rotate(String token) {
    final claims = tokens.verify(token, expectedType: TokenType.refresh);
    if (claims == null) return null;

    final jti = TokenService.claimOf(claims, Claims.tokenId);
    final family = TokenService.claimOf(claims, Claims.family);
    if (jti == null || family == null) return null;

    // Replay: this token was already exchanged. Revoke its whole family.
    final replayed = _consumed[jti];
    if (replayed != null) {
      revokeFamily(replayed.family);
      return null;
    }

    final entry = _active.remove(jti);
    if (entry == null) return null;
    if (entry.expiresAt.isBefore(DateTime.now())) return null;

    _consumed[jti] = _Consumed(
      family: entry.family,
      expiresAt: DateTime.now().add(ttl),
    );
    final user = UserRecord(id: entry.userId, displayName: entry.displayName);
    return Rotation(
      user: user,
      refreshToken: issue(user, family: entry.family),
    );
  }

  /// Revokes a single token plus every other token in its family.
  void revoke(String token) {
    final claims = tokens.verify(token, expectedType: TokenType.refresh);
    if (claims == null) return;
    final family = TokenService.claimOf(claims, Claims.family);
    if (family == null) return;
    revokeFamily(family);
  }

  /// Revokes every token sharing [family].
  ///
  /// The revoked ids are also recorded as consumed, so presenting one later is
  /// detected as a replay rather than shrugged off as an unknown token. That
  /// keeps revocation and replay detection symmetric.
  /// 吊销共享同一 [family] 的所有令牌。
  ///
  /// 被吊销的 id 也会记录为「已使用」，因此之后再出示会被判定为重放，而不是被当作
  /// 未知令牌放过。这让吊销与重放检测保持对称。
  void revokeFamily(String family) {
    final expiresAt = DateTime.now().add(ttl);
    final revoked = <String>[];
    _active.removeWhere((jti, entry) {
      if (entry.family != family) return false;
      revoked.add(jti);
      return true;
    });
    for (final jti in revoked) {
      _consumed[jti] = _Consumed(family: family, expiresAt: expiresAt);
    }
  }

  /// Drops expired bookkeeping. Returns how many entries were removed.
  ///
  /// Both maps are swept: `_consumed` grows on every rotation, so purging only
  /// `_active` would leak one entry per refresh for the life of the process.
  /// 清理过期的簿记，返回被移除的条目数。
  ///
  /// 两张表都会清扫：`_consumed` 每次轮换都会增长，只清 `_active` 会让每次续期都泄漏
  /// 一条记录，直到进程结束。
  int purgeExpired() {
    final now = DateTime.now();
    final activeBefore = _active.length;
    _active.removeWhere((_, entry) => entry.expiresAt.isBefore(now));

    final consumedBefore = _consumed.length;
    _consumed.removeWhere((_, consumed) => consumed.expiresAt.isBefore(now));

    return (activeBefore - _active.length) +
        (consumedBefore - _consumed.length);
  }

  /// Active token count, surfaced by `/health`.
  int get activeCount => _active.length;
}

/// A consumed token id, kept only until its replay window closes.
/// 已使用的令牌 id，只保留到其重放窗口关闭为止。
final class _Consumed {
  _Consumed({required this.family, required this.expiresAt});

  final String family;
  final DateTime expiresAt;
}

final class _Entry {
  _Entry({
    required this.userId,
    required this.displayName,
    required this.family,
    required this.expiresAt,
  });

  final String userId;
  final String displayName;
  final String family;
  final DateTime expiresAt;
}
