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

  const SessionHandle({required this.userId});

  @override
  bool operator ==(Object other) =>
      other is SessionHandle && other.userId == userId;

  @override
  int get hashCode => userId.hashCode;
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
  bool get isExpired =>
      expiresAt == null ? false : expiresAt!.isBefore(DateTime.now());

  /// Serialize to a JSON-safe map. Drives persistence (e.g. a [TokenStore] that
  /// writes to disk or secure storage). `null` fields are omitted.
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
      other.displayName == displayName;

  @override
  int get hashCode =>
      Object.hash(accessToken, refreshToken, expiresAt, userId, displayName);
}
