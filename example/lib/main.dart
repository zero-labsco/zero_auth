import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:zero_auth/zero_auth.dart';

import 'dio_interceptor.dart';

/// Demo entry. [DemoApp] builds its own [AuthManager] + [Dio] and offers a toggle
/// to either use the offline fake backend ([_DemoStrategy]) or a real Dart
/// backend ([_HttpAuthStrategy], see `../../server`).
void main() => runApp(const DemoApp());

/// Offline backend double — no real network needed.
///
/// It enforces the same rule as the real demo backend (password must be
/// [_validPassword]), so the failure path is reachable without a server.
class _DemoStrategy implements AuthStrategy {
  static const _validUsername = 'user';
  static const _validPassword = 'user';

  @override
  Future<AuthSession> login(Credentials credentials) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (credentials.username != _validUsername ||
        credentials.password != _validPassword) {
      throw AuthException(
        'Invalid username or password',
        code: 'invalid_credentials',
      );
    }
    // Mirrors the real backend: a short-lived access token plus a refresh
    // token, so the renewal paths stay reachable offline too.
    return AuthSession(
      accessToken: 'demo-access-${DateTime.now().millisecondsSinceEpoch}',
      refreshToken: const RefreshToken('demo-refresh-token'),
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      userId: _validUsername,
      displayName: '$_validUsername@demo',
    );
  }

  @override
  Future<AuthSession> register(RegistrationInput input) async =>
      login(Credentials(username: input.username, password: input.password));

  @override
  Future<void> logout(SessionHandle handle) async {}

  @override
  Future<AuthSession> refresh(RefreshToken token) async => login(
        const Credentials(username: _validUsername, password: _validPassword),
      );
}

/// Real HTTP backend strategy. Talks to the Dart server in `../../server`.
class _HttpAuthStrategy implements AuthStrategy {
  _HttpAuthStrategy(this.baseUrl);

  final String baseUrl;
  final Dio _dio = Dio();

  Map<String, dynamic> _data(Response<dynamic> res) =>
      res.data as Map<String, dynamic>;

  AuthSession _toSession(Map<String, dynamic> data) => AuthSession(
        accessToken: data['accessToken'] as String,
        refreshToken: RefreshToken(data['refreshToken'] as String),
        expiresAt: data['expiresIn'] != null
            ? DateTime.now().add(Duration(seconds: data['expiresIn'] as int))
            : null,
        userId: data['userId'] as String,
        displayName: data['displayName'] as String,
      );

  @override
  Future<AuthSession> login(Credentials credentials) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$baseUrl/login',
        data: {
          'username': credentials.username,
          'password': credentials.password,
        },
      );
      return _toSession(_data(res));
    } catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<AuthSession> register(RegistrationInput input) async =>
      login(Credentials(username: input.username, password: input.password));

  @override
  Future<void> logout(SessionHandle handle) async {
    try {
      await _dio.post('$baseUrl/logout');
    } catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<AuthSession> refresh(RefreshToken token) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$baseUrl/refresh',
        data: {'refreshToken': token.value},
      );
      return _toSession(_data(res));
    } catch (e) {
      throw _mapError(e);
    }
  }

  /// Turn transport/HTTP failures into the shared [AuthException] vocabulary so
  /// the UI shows something actionable instead of "Unexpected auth failure".
  AuthException _mapError(Object e) {
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionError:
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
          return AuthException(
            'Cannot reach the backend at $baseUrl — run "dart run" in server/ first',
            code: 'network_unreachable',
            cause: e,
          );
        default:
          final data = e.response?.data;
          if (data is Map && data['message'] is String) {
            return AuthException(
              data['message'] as String,
              code: (data['code'] as String?) ?? 'http_error',
              cause: e,
            );
          }
          return AuthException(
            e.message ?? 'Request failed',
            code: 'http_error',
            cause: e,
          );
      }
    }
    return AuthException('Unexpected auth failure', cause: e);
  }
}

class DemoApp extends StatefulWidget {
  const DemoApp({super.key});

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  static const _baseUrl = 'http://localhost:8080';

  /// Defaults to the real Dart backend in `../../server`; flip the AppBar
  /// switch to fall back to the offline double.
  bool _useBackend = true;
  late AuthManager _auth;
  late Dio _dio;

  final _username = TextEditingController(text: 'user');
  final _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _init() {
    _auth = AuthManager(
      strategy: _useBackend ? _HttpAuthStrategy(_baseUrl) : _DemoStrategy(),
      tokenStore: InMemoryTokenStore(),
    );
    // Interceptor references this same [_auth], so it always reads the live
    // token and renews it before it expires.
    _dio = Dio()..interceptors.add(RefreshingAuthInterceptor(_auth));
    unawaited(_auth.restore());
  }

  void _toggleBackend(bool value) => setState(() {
        _useBackend = value;
        _init();
      });

  /// Runs an auth action and swallows the rethrown error: [AuthManager] already
  /// surfaces it as an [AuthError] state, so there is nothing left to handle.
  Future<void> _invoke(Future<dynamic> Function() action) async {
    try {
      await action();
    } catch (_) {
      // Intentionally ignored — the AuthError state drives the UI.
    }
  }

  Future<void> _callMe(BuildContext context) async {
    try {
      final res = await _dio.get('$_baseUrl/me');
      if (!context.mounted) return;
      _snack(context, 'GET /me -> ${res.data}');
    } catch (e) {
      if (!context.mounted) return;
      _snack(context, 'GET /me failed: $e');
    }
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Debug: tell the backend to reject every access token issued so far, so
  /// `Call /me` starts failing until the session is refreshed.
  Future<void> _expireTokenNow(BuildContext context) async {
    try {
      final res = await _dio.post('$_baseUrl/debug/expire-access');
      if (!context.mounted) return;
      _snack(context, 'expired -> ${res.data} (now press Call /me)');
    } catch (e) {
      if (!context.mounted) return;
      _snack(context, 'expire failed: $e');
    }
  }

  /// Debug: shorten the lifetime of newly issued tokens to [seconds], then
  /// refresh so the active token really does expire that soon. Pressing
  /// `Call /me` afterwards shows the transparent renewal.
  Future<void> _expireTokenSoon(BuildContext context, int seconds) async {
    try {
      await _dio.post(
        '$_baseUrl/debug/access-ttl',
        data: {'seconds': seconds},
      );
      await _auth.refresh();
      if (!context.mounted) return;
      _snack(
        context,
        'token now expires in ${seconds}s — press Call /me to watch renewal',
      );
    } catch (e) {
      if (!context.mounted) return;
      _snack(context, 'shorten failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = _auth;
    final theme = Theme.of(context).textTheme;
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('zero_auth demo'),
          actions: [
            Row(
              children: [
                const Text('Live backend'),
                Switch(value: _useBackend, onChanged: _toggleBackend),
              ],
            ),
          ],
        ),
        body: StreamBuilder<AuthState>(
          initialData: auth.current,
          stream: auth.state,
          builder: (context, snapshot) {
            final state = snapshot.data;
            // isAuthenticated stays true during Refreshing, so the UI never
            // bounces back to the login form while the session renews.
            final authed = state?.isAuthenticated ?? false;
            final busy = state?.isBusy ?? false;
            final session = auth.currentSession;
            final error = state is AuthError ? state.error : null;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('state: ${state.runtimeType}', style: theme.titleMedium),
                  if (busy) Text('busy: ${state.runtimeType} in flight'),
                  const SizedBox(height: 4),
                  Text(
                    _useBackend
                        ? 'backend: $_baseUrl'
                        : 'backend: offline fake',
                    style: theme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  if (session != null) ...[
                    Text('userId: ${session.userId}'),
                    Text('displayName: ${session.displayName}'),
                    Text('accessToken: ${auth.accessToken}'),
                    Text('isExpired: ${session.isExpired}'),
                    const SizedBox(height: 8),
                  ],
                  if (error != null)
                    Text(
                      'error: ${error.message} (${error.code})',
                      style: const TextStyle(color: Colors.red),
                    ),
                  const SizedBox(height: 24),
                  if (!authed) ...[
                    TextField(
                      controller: _username,
                      decoration: const InputDecoration(labelText: 'username'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'password (use "user")',
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => unawaited(
                        _invoke(
                          () => auth.login(
                            Credentials(
                              username: _username.text,
                              password: _password.text,
                            ),
                          ),
                        ),
                      ),
                      child: const Text('Login'),
                    ),
                  ] else ...[
                    ElevatedButton(
                      onPressed: () => unawaited(_invoke(() => auth.refresh())),
                      child: const Text('Refresh'),
                    ),
                    ElevatedButton(
                      onPressed: () => unawaited(_invoke(() => auth.logout())),
                      child: const Text('Logout'),
                    ),
                    // Debug hooks of the demo backend; only meaningful against
                    // the real server.
                    if (_useBackend) ...[
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () => _expireTokenNow(context),
                        child: const Text('Expire token now'),
                      ),
                      ElevatedButton(
                        onPressed: () => _expireTokenSoon(context, 10),
                        child: const Text('Expire in 10s'),
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => _callMe(context),
                    child: const Text('Call /me'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
