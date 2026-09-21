import 'dart:io';

/// Runtime configuration for the demo backend.
///
/// Every value can be overridden through environment variables so the demo can
/// be pointed at another port, or given different token lifetimes, without
/// editing code.
final class ServerConfig {
  const ServerConfig({
    required this.host,
    required this.port,
    required this.secret,
    required this.accessTtl,
    required this.refreshTtl,
    required this.usingDefaultSecret,
  });

  /// Reads configuration from the process environment, falling back to demo
  /// defaults.
  factory ServerConfig.fromEnvironment() {
    final secret = Platform.environment['DEMO_SECRET'];
    return ServerConfig(
      host: Platform.environment['HOST'] ?? '0.0.0.0',
      port: int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080,
      secret: secret ?? _defaultSecret,
      accessTtl: _durationFromEnv('ACCESS_TTL_SECONDS', 120),
      refreshTtl: _durationFromEnv('REFRESH_TTL_SECONDS', 604800),
      usingDefaultSecret: secret == null || secret.isEmpty,
    );
  }

  static const _defaultSecret = 'demo-secret-change-me';

  static Duration _durationFromEnv(String key, int defaultSeconds) => Duration(
    seconds: int.tryParse(Platform.environment[key] ?? '') ?? defaultSeconds,
  );

  final String host;
  final int port;

  /// HMAC key used to sign tokens. Override with `DEMO_SECRET` anywhere the
  /// server is shared.
  final String secret;

  /// Lifetime of an access token. Short on purpose, so the example app
  /// exercises refresh and rotation during a normal demo session.
  final Duration accessTtl;

  /// Lifetime of a refresh token.
  final Duration refreshTtl;

  /// `true` when the built-in demo secret is in use, which is worth warning
  /// about at startup.
  final bool usingDefaultSecret;

  /// Bind address. `0.0.0.0` listens on every interface.
  InternetAddress get address => InternetAddress.anyIPv4;
}
