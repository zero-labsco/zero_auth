// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

/// A tiny standalone auth backend for the `zero_auth` example app.
///
/// Endpoints:
///   POST /login   {username, password}              -> 200 tokens, or 401 (password != 'b')
///   POST /refresh {refreshToken}                   -> 200 new tokens, or 401
///   POST /logout                                  -> 200 {ok: true}
///   GET  /me      (Authorization: `Bearer <token>`) -> 200 {userId, displayName}, or 401
///
/// Run with `dart run` from this folder, then start the example app.
/// On an Android emulator use http://10.0.2.2:8080 instead.
Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
  print('zero_auth demo backend listening on http://localhost:8080');
  print('Android emulator should use http://10.0.2.2:8080 instead.');
  await for (final request in server) {
    await _handle(request);
  }
}

Future<void> _handle(HttpRequest request) async {
  // CORS so the Flutter web build can call this backend.
  request.response.headers
    ..set('Access-Control-Allow-Origin', '*')
    ..set('Access-Control-Allow-Headers', 'Content-Type, Authorization')
    ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');

  if (request.method == 'OPTIONS') {
    request.response.statusCode = 204;
    await request.response.close();
    return;
  }

  try {
    switch ((request.method, request.uri.path)) {
      case ('POST', '/login'):
        final body = await _jsonBody(request);
        final password = body['password'] as String?;
        if (password == 'b') {
          _send(request, 200, {
            'accessToken': 'demo-access-token',
            'refreshToken': 'demo-refresh-token',
            'expiresIn': 3600,
            'userId': (body['username'] as String?) ?? 'demo-user',
            'displayName': 'Demo User',
          });
        } else {
          _send(request, 401, {
            'code': 'invalid_credentials',
            'message': 'Invalid password',
          });
        }
      case ('POST', '/refresh'):
        final body = await _jsonBody(request);
        final rt = body['refreshToken'] as String?;
        if (rt == 'demo-refresh-token') {
          _send(request, 200, {
            'accessToken': 'demo-access-token-refreshed',
            'refreshToken': 'demo-refresh-token',
            'expiresIn': 3600,
            'userId': 'demo-user',
            'displayName': 'Demo User',
          });
        } else {
          _send(request, 401, {
            'code': 'invalid_refresh_token',
            'message': 'Invalid refresh token',
          });
        }
      case ('POST', '/logout'):
        _send(request, 200, {'ok': true});
      case ('GET', '/me'):
        final auth = request.headers.value('authorization');
        if (auth != null && auth.startsWith('Bearer demo-')) {
          _send(request, 200, {
            'userId': 'demo-user',
            'displayName': 'Demo User',
          });
        } else {
          _send(request, 401, {
            'code': 'unauthorized',
            'message': 'Unauthorized',
          });
        }
      default:
        _send(request, 404, {'code': 'not_found', 'message': 'Not Found'});
    }
  } catch (e) {
    _send(request, 500, {'code': 'server_error', 'message': e.toString()});
  }
}

Future<Map<String, dynamic>> _jsonBody(HttpRequest request) async {
  final raw = await utf8.decoder.bind(request).join();
  if (raw.isEmpty) return <String, dynamic>{};
  return jsonDecode(raw) as Map<String, dynamic>;
}

void _send(HttpRequest request, int status, Map<String, dynamic> data) {
  request.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(data));
  request.response.close();
}
