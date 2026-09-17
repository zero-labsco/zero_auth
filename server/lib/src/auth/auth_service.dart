import '../logging/logger.dart';
import 'refresh_token_store.dart';
import 'token_service.dart';
import 'user_store.dart';

/// A successful authentication: a fresh token pair for a user.
final class AuthSuccess {
  const AuthSuccess({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  final UserRecord user;
  final String accessToken;
  final String refreshToken;

  /// Access token lifetime in seconds, which is what the example expects.
  final int expiresIn;
}

/// A rejected authentication.
///
/// [code] is the vocabulary the `zero_auth` client maps onto typed exceptions,
/// for example `invalid_credentials` or `invalid_grant`.
final class AuthFailure {
  const AuthFailure({required this.code, required this.message});

  final String code;
  final String message;
}

/// The outcome of a login or refresh attempt.
sealed class AuthResult {
  const AuthResult();
}

final class AuthOk extends AuthResult {
  const AuthOk(this.value);

  final AuthSuccess value;
}

final class AuthErr extends AuthResult {
  const AuthErr(this.failure);

  final AuthFailure failure;
}

/// The authentication use cases: login, refresh, logout and access-token
/// validation.
///
/// Kept free of HTTP concerns so it can be reused by a CLI or a test without
/// booting a socket.
final class AuthService {
  AuthService({
    required this.users,
    required this.tokens,
    required this.refreshTokens,
    required this.logger,
    required this.accessTtl,
  });

  final UserStore users;
  final TokenService tokens;
  final RefreshTokenStore refreshTokens;
  final Logger logger;

  /// Lifetime granted to every access token this service issues.
  final Duration accessTtl;

  AuthResult login(String username, String password) {
    final user = users.authenticate(username, password);
    if (user == null) {
      logger.warn('login rejected for username="$username"');
      return const AuthErr(
        AuthFailure(
          code: 'invalid_credentials',
          message: 'Invalid username or password',
        ),
      );
    }
    logger.info('login succeeded user=${user.id}');
    return AuthOk(_issue(user));
  }

  AuthResult refresh(String refreshToken) {
    final rotation = refreshTokens.rotate(refreshToken);
    if (rotation == null) {
      logger.warn('refresh rejected: token is expired, revoked or replayed');
      return const AuthErr(
        AuthFailure(
          code: 'invalid_grant',
          message: 'Refresh token is invalid, expired or revoked',
        ),
      );
    }
    logger.info(
      'refresh succeeded user=${rotation.user.id} '
      '(rotated; previous token is now invalid)',
    );
    return AuthOk(_issue(rotation.user, rotation.refreshToken));
  }

  /// Invalidates the presented refresh token and its family.
  void logout(String? refreshToken) {
    if (refreshToken == null) return;
    refreshTokens.revoke(refreshToken);
    logger.info('logout revoked the refresh token family');
  }

  /// Validates an access token and resolves its user.
  UserRecord? userForAccessToken(String accessToken) {
    final claims = tokens.verify(accessToken, expectedType: TokenType.access);
    if (claims == null) return null;
    final subject = TokenService.claimOf(claims, Claims.subject);
    if (subject == null) return null;
    return users.findById(subject);
  }

  AuthSuccess _issue(UserRecord user, [String? refreshToken]) => AuthSuccess(
        user: user,
        accessToken: tokens.sign(
          subject: user.id,
          displayName: user.displayName,
          type: TokenType.access,
          ttl: accessTtl,
          tokenId: tokens.newId(),
        ),
        refreshToken: refreshToken ?? refreshTokens.issue(user),
        expiresIn: accessTtl.inSeconds,
      );
}
