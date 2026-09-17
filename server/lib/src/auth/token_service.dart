import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Claim keys used by the tokens this backend issues.
abstract final class Claims {
  static const subject = 'sub';
  static const name = 'name';
  static const type = 'typ';
  static const tokenId = 'jti';
  static const family = 'fam';
  static const issuedAt = 'iat';
  static const expiresAt = 'exp';
}

/// Which kind of token a given JWT represents.
enum TokenType { access, refresh }

/// Issues and verifies HMAC-SHA256 JSON Web Tokens.
///
/// These are real, verifiable tokens: signed with a secret and carrying
/// standard claims (`sub`, `iat`, `exp`, `jti`) that the server checks on every
/// request. Signing uses the `crypto` package. The demo backend is repo-only
/// and never published, so this dependency never reaches `zero_auth` consumers.
final class TokenService {
  TokenService({
    required String secret,
    Duration clockSkew = const Duration(seconds: 5),
    Random? random,
  })  : _secret = utf8.encode(secret),
        _clockSkew = clockSkew,
        _random = random ?? Random.secure();

  final List<int> _secret;
  final Duration _clockSkew;
  final Random _random;

  /// Signs a new token.
  String sign({
    required String subject,
    required String displayName,
    required TokenType type,
    required Duration ttl,
    required String tokenId,
    String? family,
  }) {
    final now = DateTime.now();
    return _encode(<String, Object?>{
      Claims.subject: subject,
      Claims.name: displayName,
      Claims.type: type.name,
      Claims.tokenId: tokenId,
      Claims.family: family,
      Claims.issuedAt: _seconds(now),
      Claims.expiresAt: _seconds(now.add(ttl)),
    });
  }

  /// Verifies signature and expiry.
  ///
  /// Returns the claims, or `null` when the token is malformed, tampered with,
  /// expired, or of the wrong type.
  Map<String, dynamic>? verify(String token, {TokenType? expectedType}) {
    final parts = token.split('.');
    if (parts.length != 3) return null;

    if (!_constantTimeEquals(_signature('${parts[0]}.${parts[1]}'), parts[2])) {
      return null;
    }

    Map<String, dynamic> claims;
    try {
      claims =
          jsonDecode(utf8.decode(_decode(parts[1]))) as Map<String, dynamic>;
    } on Object {
      return null;
    }

    final exp = claims[Claims.expiresAt];
    if (exp is! int) return null;
    if (_seconds(DateTime.now()) - _clockSkew.inSeconds > exp) return null;

    if (expectedType != null && claims[Claims.type] != expectedType.name) {
      return null;
    }
    return claims;
  }

  /// Reads a claim from an already-verified token.
  static String? claimOf(Map<String, dynamic> claims, String key) =>
      claims[key] as String?;

  /// A fresh, unguessable identifier for `jti` and token families.
  String newId([int bytes = 16]) {
    final buffer = StringBuffer();
    for (var i = 0; i < bytes; i++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  String _encode(Map<String, Object?> payload) {
    final header = _encodeSegment({'alg': 'HS256', 'typ': 'JWT'});
    final body = _encodeSegment(payload);
    return '$header.$body.${_signature('$header.$body')}';
  }

  String _encodeSegment(Object value) =>
      _encodeBytes(utf8.encode(jsonEncode(value)));

  String _encodeBytes(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  List<int> _decode(String segment) {
    var padded = segment;
    final remainder = padded.length % 4;
    if (remainder != 0) padded += '=' * (4 - remainder);
    return base64Url.decode(padded);
  }

  String _signature(String data) =>
      _encodeBytes(Hmac(sha256, _secret).convert(utf8.encode(data)).bytes);

  static int _seconds(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;

  /// Length-tolerant comparison that does not leak timing information.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
