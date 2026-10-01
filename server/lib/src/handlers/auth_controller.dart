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
    if (body == null) return _badBody(request);

    final username = _stringField(body, 'username')?.trim();
    final password = _stringField(body, 'password');
    if (username == null || password == null) {
      await _missingCredentials(request);
      return;
    }

    switch (auth.login(username, password)) {
      case AuthOk(:final value):
        await _sendTokens(request, value);
      case AuthErr(:final failure):
        await _fail(request, 401, failure);
    }
  }

  /// POST /register, body: {username, password, displayName?}
  ///
  /// The account lives in the in-memory `UserStore`, so it disappears when the
  /// process restarts — which is all the demo needs.
  Future<void> register(HttpRequest request) async {
    final body = await readJsonBody(request);
    if (body == null) return _badBody(request);

    final username = _stringField(body, 'username')?.trim();
    final password = _stringField(body, 'password');
    if (username == null || password == null) {
      await _missingCredentials(request);
      return;
    }
    final displayName = _stringField(body, 'displayName');

    switch (auth.register(username, password, displayName: displayName)) {
      case AuthOk(:final value):
        await _sendTokens(request, value);
      case AuthErr(:final failure):
        // 400 for a malformed request, 409 when the name is genuinely taken —
        // the client needs to tell those two apart.
        // 格式错误回 400，用户名真的被占用回 409 —— 客户端需要区分这两者。
        await _fail(
          request,
          failure.code == 'bad_request' ? 400 : 409,
          failure,
        );
    }
  }

  /// POST /refresh, body: {refreshToken}
  Future<void> refresh(HttpRequest request) async {
    final body = await readJsonBody(request);
    if (body == null) return _badBody(request);

    final token = _stringField(body, 'refreshToken');
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
  ///
  /// Without a token the server cannot revoke anything, but the client has
  /// already dropped the session locally, so this still answers 200.
  Future<void> logout(HttpRequest request) async {
    final body = await readJsonBody(request);
    final token = body == null ? null : _stringField(body, 'refreshToken');
    auth.logout(token ?? bearerToken(request));
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

  /// Reads a string field, or `null` when it is absent or of the wrong type.
  ///
  /// A hard `as String?` cast here would turn `{"username": 123}` into a 500;
  /// this makes it a 400 instead.
  /// 读取字符串字段，缺失或类型不符时返回 `null`。
  ///
  /// 若这里用硬转换 `as String?`，`{"username": 123}` 会变成 500；这样写则是 400。
  String? _stringField(Map<String, dynamic> body, String key) {
    final value = body[key];
    return value is String ? value : null;
  }

  Future<void> _missingCredentials(HttpRequest request) => _fail(
        request,
        400,
        const AuthFailure(
          code: 'bad_request',
          message: '"username" and "password" must be strings',
        ),
      );

  Future<void> _badBody(HttpRequest request) => _fail(
        request,
        400,
        const AuthFailure(
          code: 'bad_request',
          message: 'Expected a JSON object body of at most 64 KiB',
        ),
      );

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
