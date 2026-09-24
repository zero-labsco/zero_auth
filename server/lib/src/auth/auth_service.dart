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
  ///
  /// Mutable so the debug endpoints can shorten it on demand and watch the
  /// client renew.
  Duration accessTtl;

  /// Access tokens issued at or before this moment are rejected, which is how
  /// the debug "expire now" endpoint simulates expiry for tokens that are
  /// otherwise still inside their lifetime.
  DateTime? _accessTokensInvalidatedBefore;

  /// Rejects every access token issued so far. The next login or refresh clears
  /// the watermark by producing a token issued afterwards.
  void invalidateAccessTokens() {
    _accessTokensInvalidatedBefore = DateTime.now();
    logger.warn('debug: access tokens issued so far are now rejected');
  }

  /// Clears the invalidation watermark.
  void clearInvalidation() {
    _accessTokensInvalidatedBefore = null;
    logger.info('debug: access token invalidation cleared');
  }

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

  /// Creates an account and returns its first token pair.
  ///
  /// Fails with `username_taken` when the name is already registered, which the
  /// client maps onto `InvalidCredentialsException`-style handling.
  AuthResult register(
    String username,
    String password, {
    String? displayName,
  }) {
    final user = users.register(username, password, displayName: displayName);
    if (user == null) {
      logger.warn('registration rejected for username="$username"');
      return const AuthErr(
        AuthFailure(
          code: 'username_taken',
          message: 'Username is already taken, or the credentials are empty',
        ),
      );
    }
    logger.info('registration succeeded user=${user.id}');
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

    // Simulated expiry: the token is valid, but was issued before the debug
    // watermark, so it must be treated as dead.
    //
    // Compared in milliseconds: `iat` is whole seconds, so two tokens issued in
    // the same second as the invalidation could not otherwise be told apart.
    final watermark = _accessTokensInvalidatedBefore;
    if (watermark != null) {
      final issuedAtMillis = claims[Claims.issuedAtMillis];
      if (issuedAtMillis is! int ||
          issuedAtMillis < watermark.millisecondsSinceEpoch) {
        return null;
      }
    }

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
