import 'dart:io';

import '../auth/auth_service.dart';
import '../http/response.dart';
import '../logging/logger.dart';

/// Debug-only endpoints that make token lifetimes observable in the example app.
///
/// They exist purely so a demo can show what happens when a token dies, or when
/// it is about to, without waiting for a real expiry. Remove this controller (and
/// its routes) if you ever turn this backend into something real.
final class DebugController {
  DebugController({required this.auth, required this.logger});

  final AuthService auth;
  final Logger logger;

  /// POST /debug/expire-access
  ///
  /// Every access token issued so far is rejected from now on, which is the
  /// fastest way to watch a client fall back to refresh.
  Future<void> expireAccess(HttpRequest request) async {
    auth.invalidateAccessTokens();
    await sendJson(request, 200, {
      'ok': true,
      'note': 'access tokens issued so far are now rejected',
    });
  }

  /// POST /debug/access-ttl, body: {seconds}
  ///
  /// Changes the lifetime granted to *newly issued* access tokens. Combined with
  /// a refresh, this yields a token that expires in a few seconds, so the
  /// auto-renewal path can be watched without waiting.
  Future<void> setAccessTtl(HttpRequest request) async {
    final body = await readJsonBody(request);
    final seconds = body['seconds'];
    if (seconds is! int || seconds < 1) {
      await sendJson(request, 400, {
        'code': 'bad_request',
        'message': 'Provide {"seconds": <positive integer>}',
      });
      return;
    }

    auth.accessTtl = Duration(seconds: seconds);
    logger.warn('debug: access token lifetime set to ${seconds}s');
    await sendJson(request, 200, {'ok': true, 'accessTtlSeconds': seconds});
  }

  /// POST /debug/reset
  ///
  /// Restores the configured token lifetime and clears any simulated expiry.
  Future<void> reset(HttpRequest request, Duration configuredTtl) async {
    auth
      ..accessTtl = configuredTtl
      ..clearInvalidation();
    logger.info(
      'debug: reset (access ${configuredTtl.inSeconds}s, expiry cleared)',
    );
    await sendJson(request, 200, {
      'ok': true,
      'accessTtlSeconds': configuredTtl.inSeconds,
    });
  }
}
