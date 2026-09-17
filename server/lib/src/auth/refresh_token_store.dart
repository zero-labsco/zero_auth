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

  /// Already-consumed token ids, mapped to their family.
  final Map<String, String> _consumed = {};

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
    final replayedFamily = _consumed[jti];
    if (replayedFamily != null) {
      revokeFamily(replayedFamily);
      return null;
    }

    final entry = _active.remove(jti);
    if (entry == null) return null;
    if (entry.expiresAt.isBefore(DateTime.now())) return null;

    _consumed[jti] = entry.family;
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
  void revokeFamily(String family) {
    _active.removeWhere((_, entry) => entry.family == family);
  }

  /// Drops expired bookkeeping. Returns how many entries were removed.
  int purgeExpired() {
    final now = DateTime.now();
    final before = _active.length;
    _active.removeWhere((_, entry) => entry.expiresAt.isBefore(now));
    return before - _active.length;
  }

  /// Active token count, surfaced by `/health`.
  int get activeCount => _active.length;
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
