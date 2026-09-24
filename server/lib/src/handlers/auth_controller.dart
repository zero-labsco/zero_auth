import 'dart:io';

import '../auth/auth_service.dart';
import '../http/middleware.dart';
import '../http/response.dart';
import '../logging/logger.dart';

/// HTTP adapter for [AuthService]: reads requests and maps results onto status
/// codes and JSON bodies.
///
/// Failures use the `code` vocabulary the `zero_auth` client maps onto typed
/// exceptions, so a rejected refresh surfaces as `SessionExpiredException` and
/// the default failure policy signs the user out.
final class AuthController {
  AuthController({required this.auth, required this.logger});

  final AuthService auth;
  final Logger logger;

  /// POST /login, body: {username, password}
  Future<void> login(HttpRequest request) async {
    final body = await readJsonBody(request);
    final username = (body['username'] as String?)?.trim() ?? '';
    final password = body['password'] as String? ?? '';

    switch (auth.login(username, password)) {
      case AuthOk(:final value):
        await _sendTokens(request, value);
      case AuthErr(:final failure):
        await _fail(request, 401, failure);
    }
  }

  /// POST /register, body: {username, password, displayName?}
  ///
  /// The account lives in the in-memory [UserStore], so it disappears when the
  /// process restarts — which is all the demo needs.
  Future<void> register(HttpRequest request) async {
    final body = await readJsonBody(request);
    final username = (body['username'] as String?)?.trim() ?? '';
    final password = body['password'] as String? ?? '';
    final displayName = body['displayName'] as String?;

    switch (auth.register(username, password, displayName: displayName)) {
      case AuthOk(:final value):
        await _sendTokens(request, value);
      case AuthErr(:final failure):
        // 409, not 401: the caller is not unauthenticated, the name is taken.
        await _fail(request, 409, failure);
    }
  }

  /// POST /refresh, body: {refreshToken}
  Future<void> refresh(HttpRequest request) async {
    final body = await readJsonBody(request);
    final token = body['refreshToken'] as String?;
    if (token == null || token.isEmpty) {
      await _fail(
        request,
        401,
        const AuthFailure(
          code: 'invalid_grant',
          message: 'Missing refresh token',
        ),
      );
      return;
    }

    switch (auth.refresh(token)) {
      case AuthOk(:final value):
        await _sendTokens(request, value);
      case AuthErr(:final failure):
        await _fail(request, 401, failure);
    }
  }

  /// POST /logout, optional body: {refreshToken}
  Future<void> logout(HttpRequest request) async {
    final body = await readJsonBody(request);
    auth.logout(body['refreshToken'] as String? ?? bearerToken(request));
    await sendJson(request, 200, {'ok': true});
  }

  /// GET /me, requires `Authorization: Bearer <access token>`
  Future<void> me(HttpRequest request) async {
    final token = bearerToken(request);
    if (token == null) {
      await _fail(
        request,
        401,
        const AuthFailure(
          code: 'invalid_token',
          message: 'Missing bearer token',
        ),
      );
      return;
    }

    final user = auth.userForAccessToken(token);
    if (user == null) {
      await _fail(
        request,
        401,
        const AuthFailure(
          code: 'invalid_token',
          message: 'Access token is invalid or expired',
        ),
      );
      return;
    }

    await sendJson(request, 200, {
      'userId': user.id,
      'displayName': user.displayName,
    });
  }

  /// GET /health, liveness plus a couple of counters.
  Future<void> health(HttpRequest request) async {
    await sendJson(request, 200, {
      'status': 'ok',
      'activeRefreshTokens': auth.refreshTokens.activeCount,
    });
  }

  /// Shared token-pair shape for `/login`, `/register` and `/refresh`.
  Future<void> _sendTokens(HttpRequest request, AuthSuccess value) =>
      sendJson(request, 200, {
        'accessToken': value.accessToken,
        'refreshToken': value.refreshToken,
        'expiresIn': value.expiresIn,
        'userId': value.user.id,
        'displayName': value.user.displayName,
      });

  Future<void> _fail(
    HttpRequest request,
    int status,
    AuthFailure failure,
  ) async {
    logger.debug('responding $status ${failure.code}: ${failure.message}');
    await sendJson(request, status, {
      'code': failure.code,
      'message': failure.message,
    });
  }
}
