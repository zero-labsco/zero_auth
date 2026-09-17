// Entry point only: read configuration, wire the graph, serve.
//
// All behaviour lives under lib/ so it can be reused or tested without booting
// a socket. Run with `dart run bin/server.dart` from this folder.
import 'dart:async';
import 'dart:io';

import 'package:zero_auth_example_server/server.dart';
import 'package:zero_auth_example_server/src/auth/auth_service.dart';
import 'package:zero_auth_example_server/src/auth/refresh_token_store.dart';
import 'package:zero_auth_example_server/src/auth/token_service.dart';
import 'package:zero_auth_example_server/src/auth/user_store.dart';

Future<void> main() async {
  final config = ServerConfig.fromEnvironment();
  final logger = Logger(
    minimum: Platform.environment['LOG_LEVEL'] == 'debug'
        ? LogLevel.debug
        : LogLevel.info,
  );

  final tokens = TokenService(secret: config.secret);
  final auth = AuthService(
    users: UserStore(),
    tokens: tokens,
    refreshTokens: RefreshTokenStore(tokens: tokens, ttl: config.refreshTtl),
    logger: logger,
    accessTtl: config.accessTtl,
  );

  final server = AuthServer(config: config, logger: logger, auth: auth);
  await server.start();

  // Shut down cleanly on Ctrl-C / SIGTERM so the port is released.
  // SIGTERM is unsupported on Windows, so it is only watched elsewhere.
  final signals = <ProcessSignal>[
    ProcessSignal.sigint,
    if (!Platform.isWindows) ProcessSignal.sigterm,
  ];
  final stop = <StreamSubscription<ProcessSignal>>[];
  for (final signal in signals) {
    stop.add(
      signal.watch().listen((_) async {
        logger.info('shutdown signal received');
        await server.stop();
        for (final sub in stop) {
          await sub.cancel();
        }
        exit(0);
      }),
    );
  }

  logger.info('Android emulator should use http://10.0.2.2:${config.port}');
}
