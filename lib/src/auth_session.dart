/// A refresh-token value object.
/// 刷新令牌值对象。
final class RefreshToken {
  final String value;

  const RefreshToken(this.value);

  /// Serialize to its raw string value.
  /// 序列化为原始字符串值。
  String toJson() => value;

  /// Deserialize from a raw string value.
  /// 从原始字符串值反序列化。
  factory RefreshToken.fromJson(Object? json) => RefreshToken(json as String);

  @override
  bool operator ==(Object other) =>
      other is RefreshToken && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// A handle that identifies a session for backend operations (e.g. logout).
/// 用于后端操作（如登出）标识会话的句柄。
final class SessionHandle {
  final String userId;

  /// Present when the session carries one, so backends that revoke by refresh
  /// token can still act when [userId] is empty.
  /// 会话携带刷新令牌时可用；这样即使 [userId] 为空，按令牌吊销的后端也能处理。
  final RefreshToken? refreshToken;

  const SessionHandle({required this.userId, this.refreshToken});

  @override
  bool operator ==(Object other) =>
      other is SessionHandle &&
      other.userId == userId &&
      other.refreshToken == refreshToken;

  @override
  int get hashCode => Object.hash(userId, refreshToken);
}

/// The active session: tokens, expiry, identity and raw claims.
/// 当前活动会话：令牌、过期时间、身份与原始 claims。
final class AuthSession {
  final String accessToken;
  final RefreshToken? refreshToken;
  final DateTime? expiresAt;
  final String? userId;
  final String? displayName;
  final Map<String, Object?>? claims;

  const AuthSession({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.userId,
    this.displayName,
    this.claims,
  });

  /// Whether the access token is expired. Sessions without an [expiresAt] are
  /// treated as still valid (no expiry known).
  /// 访问令牌是否已过期。未提供 [expiresAt] 视为仍有效（无过期信息）。
  bool get isExpired => isExpiredAt(DateTime.now());

  /// Same as [isExpired], evaluated against [now] instead of the wall clock.
  /// Lets hosts inject their own clock (tests, clock-skew tolerance) instead of
  /// being tied to [DateTime.now].
  /// 与 [isExpired] 相同，只是针对 [now] 而非系统时钟判断。便于宿主注入自己的时钟
  /// （测试、时钟偏移容错），而不必受制于 [DateTime.now]。
  bool isExpiredAt(DateTime now) =>
      expiresAt == null ? false : expiresAt!.isBefore(now);

  /// Returns a copy of this session with the given fields replaced.
  /// 返回本会话的副本，仅替换指定字段。
  ///
  /// Like most hand-written `copyWith` implementations, passing `null` **keeps
  /// the current value** — it does not clear the field. To remove a field
  /// (for example the refresh token), construct a new [AuthSession].
  /// 与多数手写 `copyWith` 一样，传入 `null` 表示**保留当前值**，而不是清空该字段。
  /// 若要移除某字段（例如刷新令牌），请直接构造新的 [AuthSession]。
  ///
  /// ```dart
  /// await auth.updateSession((s) => s.copyWith(displayName: 'New Name'));
  /// ```
  AuthSession copyWith({
    String? accessToken,
    RefreshToken? refreshToken,
    DateTime? expiresAt,
    String? userId,
    String? displayName,
    Map<String, Object?>? claims,
  }) =>
      AuthSession(
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        expiresAt: expiresAt ?? this.expiresAt,
        userId: userId ?? this.userId,
        displayName: displayName ?? this.displayName,
        claims: claims ?? this.claims,
      );

  /// How long until the access token expires, or `null` when there is no expiry.
  /// 距离访问令牌过期还有多久；无过期时间时为 `null`。
  Duration? timeUntilExpiry([DateTime? now]) {
    final expiry = expiresAt;
    if (expiry == null) return null;
    return expiry.difference(now ?? DateTime.now());
  }

  /// Whether the token expires within [window] — useful for renewing a little
  /// before it actually dies.
  /// 令牌是否会在 [window] 内过期 —— 便于在真正失效前提前续期。
  bool isExpiringWithin(Duration window, [DateTime? now]) {
    final left = timeUntilExpiry(now);
    if (left == null) return false;
    return left <= window;
  }

  /// Serialize to a JSON-safe map. Drives persistence (e.g. a [TokenStore] that
  /// writes to disk or secure storage). `null` fields are omitted.
  ///
  /// [claims] is written verbatim, so it must only contain JSON-safe values
  /// (String, num, bool, null, List, Map). A `DateTime` or a custom object there
  /// would make `jsonEncode` throw at the storage layer.
  /// [claims] 会被原样写入，因此只能包含 JSON 安全的值（String、num、bool、null、
  /// List、Map）。放入 `DateTime` 或自定义对象会让存储层的 `jsonEncode` 抛错。
  /// 序列化为 JSON 安全映射，供持久化使用（如写入磁盘或安全存储的 [TokenStore]）。
  /// 为 `null` 的字段会被省略。
  Map<String, Object?> toJson() => {
        'accessToken': accessToken,
        if (refreshToken != null) 'refreshToken': refreshToken!.value,
        if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
        if (userId != null) 'userId': userId,
        if (displayName != null) 'displayName': displayName,
        if (claims != null) 'claims': claims,
      };

  /// Deserialize from a map produced by [toJson].
  /// 从 [toJson] 生成的映射反序列化。
  factory AuthSession.fromJson(Map<String, Object?> json) => AuthSession(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] == null
            ? null
            : RefreshToken(json['refreshToken'] as String),
        expiresAt: json['expiresAt'] == null
            ? null
            : DateTime.parse(json['expiresAt'] as String),
        userId: json['userId'] as String?,
        displayName: json['displayName'] as String?,
        claims: (json['claims'] as Map?)?.cast<String, Object?>(),
      );

  @override
  bool operator ==(Object other) =>
      other is AuthSession &&
      other.accessToken == accessToken &&
      other.refreshToken == refreshToken &&
      other.expiresAt == expiresAt &&
      other.userId == userId &&
      other.displayName == displayName &&
      _claimsEqual(other.claims, claims);

  @override
  int get hashCode => Object.hash(
        accessToken,
        refreshToken,
        expiresAt,
        userId,
        displayName,
        _claimsHash(claims),
      );

  /// Claims participate in equality so a session whose *only* change is in
  /// `claims` still counts as new — otherwise a state emission could be
  /// suppressed as a duplicate.
  /// claims 参与相等性比较，这样仅 claims 发生变化的会话也算新值，
  /// 否则该次状态通知会被当作重复值抑制。
  static bool _claimsEqual(Map<String, Object?>? a, Map<String, Object?>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == null && b == null;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  static int _claimsHash(Map<String, Object?>? claims) {
    if (claims == null) return 0;
    var hash = 0;
    for (final entry in claims.entries) {
      hash ^= Object.hash(entry.key, entry.value);
    }
    return hash;
  }
}
