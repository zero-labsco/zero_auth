import 'dart:async';
import 'dart:io';

import 'auth/auth_service.dart';
import 'config.dart';
import 'handlers/auth_controller.dart';
import 'handlers/debug_controller.dart';
import 'http/middleware.dart';
import 'http/response.dart';
import 'http/router.dart';
import 'logging/logger.dart';

/// The assembled demo backend: owns the socket, the middleware chain and the
/// dependency graph.
final class AuthServer {
  AuthServer({required this.config, required this.logger, required this.auth}) {
    _router
      ..post('/login', _controller.login)
      ..post('/register', _controller.register)
      ..post('/refresh', _controller.refresh)
      ..post('/logout', _controller.logout)
      ..get('/me', _controller.me)
      ..get('/health', _controller.health)
      ..post('/debug/expire-access', _debug.expireAccess)
      ..post('/debug/access-ttl', _debug.setAccessTtl)
      ..post(
        '/debug/reset',
        (request) => _debug.reset(request, config.accessTtl),
      );
  }

  final ServerConfig config;
  final Logger logger;
  final AuthService auth;

  final Router _router = Router();
  late final AuthController _controller = AuthController(
    auth: auth,
    logger: logger,
  );

  late final DebugController _debug = DebugController(
    auth: auth,
    logger: logger,
  );

  HttpServer? _server;
  Timer? _janitor;

  /// Binds the socket and starts serving. Also schedules periodic cleanup of
  /// expired refresh-token bookkeeping.
  Future<HttpServer> start() async {
    final HttpServer server;
    try {
      server = await HttpServer.bind(config.address, config.port);
    } on SocketException catch (error) {
      logger.error(
        'cannot bind ${config.host}:${config.port} ($error). '
        'Another instance is probably still running on that port.',
      );
      rethrow;
    }
    _server = server;

    _janitor = Timer.periodic(const Duration(minutes: 5), (_) {
      final removed = auth.refreshTokens.purgeExpired();
      if (removed > 0) {
        logger.debug('purged $removed expired refresh token(s)');
      }
    });

    logger.info(
      'listening on http://${config.host}:${config.port} '
      '(access ${config.accessTtl.inSeconds}s, '
      'refresh ${config.refreshTtl.inSeconds}s)',
    );
    if (config.usingDefaultSecret) {
      logger.warn(
        'DEMO_SECRET is not set, using the built-in demo secret. '
        'Set DEMO_SECRET before sharing this server.',
      );
    }
    logger.info('demo credentials: user / user; POST /register adds more');

    server.listen(
      _handle,
      onError: (Object error) => logger.error('socket error: $error'),
    );
    return server;
  }

  Future<void> _handle(HttpRequest request) async {
    final stopwatch = Stopwatch()..start();
    final label = '${request.method} ${request.uri.path}';

    // CORS first: it owns OPTIONS preflights entirely.
    if (applyCors(request)) {
      stopwatch.stop();
      logger.debug('$label -> 204 (${stopwatch.elapsedMilliseconds}ms CORS)');
      return;
    }

    var status = 404;
    try {
      final handler = _router.match(request.method, request.uri.path);
      if (handler == null) {
        await sendJson(request, 404, {
          'code': 'not_found',
          'message': 'No route for ${request.method} ${request.uri.path}',
        });
        return;
      }
      await handler(request);
      status = request.response.statusCode;
    } catch (error, stack) {
      logger.error('$label failed: $error\n$stack');
      if (!request.response.headers.contentType.toString().contains('json')) {
        await sendJson(request, 500, {
          'code': 'server_error',
          'message': 'Unexpected server error',
        });
        status = 500;
      }
    } finally {
      stopwatch.stop();
      logger.info('$label -> $status (${stopwatch.elapsedMilliseconds}ms)');
    }
  }

  /// Releases the socket and timers.
  Future<void> stop() async {
    _janitor?.cancel();
    _janitor = null;
    await _server?.close(force: true);
    _server = null;
    logger.info('server stopped');
  }
}
