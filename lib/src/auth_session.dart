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
  /// 序列化为 JSON 安全映射，供持久化使用（如写入磁盘或安全存储的 [TokenStore]）。
  /// 为 `null` 的字段会被省略。
  ///
  /// [claims] 会被原样写入，因此只能包含 JSON 安全的值（String、num、bool、null、
  /// List、Map）。放入 `DateTime` 或自定义对象会让存储层的 `jsonEncode` 抛错。
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

  /// Deserialize from a map produced by [toJson], or return `null` when the map
  /// does not describe a valid session.
  ///
  /// Prefer this over [fromJson] whenever the map comes from disk, secure
  /// storage or the network: a schema change, a partial write or a hand-edited
  /// value makes [fromJson] throw a [FormatException] / [TypeError] — a failure
  /// outside the `AppException` vocabulary this package promises.
  /// 从 [toJson] 生成的映射反序列化；映射无法描述合法会话时返回 `null`。
  ///
  /// 只要映射来自磁盘、安全存储或网络，就应优先使用它而非 [fromJson]：schema 变更、
  /// 写入中断或人为改值都会让 [fromJson] 抛出 [FormatException] / [TypeError] ——
  /// 那是本包承诺的 `AppException` 词汇之外的失败。
  static AuthSession? tryFromJson(Object? json) {
    if (json is! Map) return null;

    final accessToken = json['accessToken'];
    if (accessToken is! String) return null;

    final refreshToken = json['refreshToken'];
    if (refreshToken != null && refreshToken is! String) return null;

    DateTime? expiresAt;
    final rawExpiry = json['expiresAt'];
    if (rawExpiry != null) {
      if (rawExpiry is! String) return null;
      expiresAt = DateTime.tryParse(rawExpiry);
      if (expiresAt == null) return null;
    }

    final userId = json['userId'];
    if (userId != null && userId is! String) return null;

    final displayName = json['displayName'];
    if (displayName != null && displayName is! String) return null;

    final claims = json['claims'];
    if (claims != null && claims is! Map) return null;

    return AuthSession(
      accessToken: accessToken,
      refreshToken:
          refreshToken == null ? null : RefreshToken(refreshToken as String),
      expiresAt: expiresAt,
      userId: userId as String?,
      displayName: displayName as String?,
      claims: (claims as Map?)?.cast<String, Object?>(),
    );
  }

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
  /// suppressed as a duplicate. Nested maps and lists are compared structurally.
  /// claims 参与相等性比较，这样仅 claims 发生变化的会话也算新值，
  /// 否则该次状态通知会被当作重复值抑制。嵌套的 Map 与 List 按内容比较。
  static bool _claimsEqual(Map<String, Object?>? a, Map<String, Object?>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (!_deepEqual(entry.value, b[entry.key])) return false;
    }
    return true;
  }

  /// Structural equality for JSON-shaped values: nested maps and lists are
  /// compared by content, everything else falls back to `==`.
  /// 面向 JSON 形状值的结构化相等：嵌套 Map / List 按内容比较，其余回落到 `==`。
  static bool _deepEqual(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key)) return false;
        if (!_deepEqual(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEqual(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  static int _claimsHash(Map<String, Object?>? claims) {
    if (claims == null) return 0;
    var hash = 0;
    for (final entry in claims.entries) {
      hash ^= Object.hash(entry.key, _deepHash(entry.value));
    }
    return hash;
  }

  /// Mirrors [_deepEqual]: two values that compare equal must hash alike, so
  /// nested maps and lists are hashed by content too.
  /// 与 [_deepEqual] 对应：相等的值必须有相同的哈希，因此嵌套 Map / List 也按内容取哈希。
  static int _deepHash(Object? value) {
    if (value == null) return 0;
    if (value is Map) {
      var hash = 0;
      for (final entry in value.entries) {
        hash ^= Object.hash(entry.key, _deepHash(entry.value));
      }
      return hash;
    }
    if (value is List) {
      var hash = 0;
      for (final item in value) {
        hash ^= _deepHash(item);
      }
      return hash;
    }
    return value.hashCode;
  }
}
