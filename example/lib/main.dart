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
/// It enforces the same rule as the real demo backend, so the failure path is
/// reachable without a server.
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
            'Cannot reach the backend at $baseUrl. Run "dart run" in server/ first.',
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

  /// Defaults to the real Dart backend in `../../server`; flip the switch to
  /// fall back to the offline double.
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
    unawaited(_auth.dispose());
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _init() {
    _auth = AuthManager(
      strategy: _useBackend ? _HttpAuthStrategy(_baseUrl) : _DemoStrategy(),
      tokenStore: InMemoryTokenStore(),
    );
    // The interceptor references this same [_auth], so it always reads the live
    // token and renews it before it expires.
    _dio = Dio()..interceptors.add(RefreshingAuthInterceptor(_auth));
    unawaited(_auth.restore());
  }

  void _toggleBackend(bool value) => setState(() {
        unawaited(_auth.dispose());
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
      _snack(context, 'expired -> ${res.data}. Now press Call /me.');
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
      await _dio.post('$_baseUrl/debug/access-ttl', data: {'seconds': seconds});
      await _invoke(() => _auth.refresh());
      if (!context.mounted) return;
      _snack(
        context,
        'token now expires in ${seconds}s. Press Call /me to watch renewal.',
      );
    } catch (e) {
      if (!context.mounted) return;
      _snack(context, 'shorten failed: $e');
    }
  }

  /// Debug: restore the configured token lifetime and clear simulated expiry.
  Future<void> _resetDebug(BuildContext context) async {
    try {
      await _dio.post('$_baseUrl/debug/reset');
      if (!context.mounted) return;
      _snack(context, 'debug backend reset');
    } catch (e) {
      if (!context.mounted) return;
      _snack(context, 'reset failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'zero_auth demo',
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: Scaffold(
          appBar: AppBar(title: const Text('zero_auth demo')),
          body: SafeArea(
            child: StreamBuilder<AuthState>(
              initialData: _auth.current,
              stream: _auth.state,
              builder: (context, snapshot) => _DemoBody(
                state: snapshot.data,
                auth: _auth,
                useBackend: _useBackend,
                baseUrl: _baseUrl,
                username: _username,
                password: _password,
                onToggleBackend: _toggleBackend,
                onLogin: () => _invoke(
                  () => _auth.login(
                    Credentials(
                        username: _username.text, password: _password.text),
                  ),
                ),
                onRefresh: () => _invoke(() => _auth.refresh()),
                onLogout: () => _invoke(() => _auth.logout()),
                onCallMe: () => _callMe(context),
                onExpireNow: () => _expireTokenNow(context),
                onExpireSoon: () => _expireTokenSoon(context, 10),
                onResetDebug: () => _resetDebug(context),
              ),
            ),
          ),
        ),
      );

  /// One seed colour drives the whole palette; widgets read shades from the
  /// theme instead of hardcoding colors.
  static ThemeData _theme(Brightness brightness) => ThemeData(
        useMaterial3: true,
        brightness: brightness,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00695C),
          brightness: brightness,
        ),
      );
}

/// The scrollable demo surface. Adapts to the viewport: a full-width column on
/// phones, and a centred, width-constrained column from 600dp up.
class _DemoBody extends StatelessWidget {
  const _DemoBody({
    required this.state,
    required this.auth,
    required this.useBackend,
    required this.baseUrl,
    required this.username,
    required this.password,
    required this.onToggleBackend,
    required this.onLogin,
    required this.onRefresh,
    required this.onLogout,
    required this.onCallMe,
    required this.onExpireNow,
    required this.onExpireSoon,
    required this.onResetDebug,
  });

  final AuthState? state;
  final AuthManager auth;
  final bool useBackend;
  final String baseUrl;
  final TextEditingController username;
  final TextEditingController password;
  final ValueChanged<bool> onToggleBackend;
  final VoidCallback onLogin;
  final VoidCallback onRefresh;
  final VoidCallback onLogout;
  final VoidCallback onCallMe;
  final VoidCallback onExpireNow;
  final VoidCallback onExpireSoon;
  final VoidCallback onResetDebug;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 600;
    final gutter = compact ? 16.0 : 24.0;
    final session = auth.currentSession;
    final error = state is AuthError ? (state! as AuthError).error : null;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SingleChildScrollView(
          // Extra bottom room keeps the last control clear of the keyboard.
          padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatusCard(state: state, session: session),
              if (error != null) ...[
                const SizedBox(height: 12),
                _ErrorCard(error: error),
              ],
              const SizedBox(height: 12),
              _BackendCard(
                useBackend: useBackend,
                baseUrl: baseUrl,
                onChanged: onToggleBackend,
              ),
              const SizedBox(height: 12),
              if (session == null)
                _LoginCard(
                  username: username,
                  password: password,
                  busy: state?.isBusy ?? false,
                  onLogin: onLogin,
                )
              else
                _SessionCard(
                  auth: auth,
                  session: session,
                  busy: state?.isBusy ?? false,
                  onCallMe: onCallMe,
                  onRefresh: onRefresh,
                  onLogout: onLogout,
                ),
              if (session != null && useBackend) ...[
                const SizedBox(height: 12),
                _DebugCard(
                  onExpireNow: onExpireNow,
                  onExpireSoon: onExpireSoon,
                  onReset: onResetDebug,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Current machine state plus a signed-in / working indicator.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state, required this.session});

  final AuthState? state;
  final AuthSession? session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final signedIn = state?.isAuthenticated ?? false;
    final busy = state?.isBusy ?? false;
    final current = session;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  signedIn ? Icons.lock_open : Icons.lock_outline,
                  size: 20,
                  color: signedIn ? colors.primary : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'state: ${state?.runtimeType ?? 'Unknown'}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Badge(
                  label: signedIn ? 'signed in' : 'signed out',
                  color: signedIn ? colors.primary : colors.outline,
                  onColor: signedIn ? colors.onPrimary : colors.onSurface,
                ),
                if (busy)
                  _Badge(
                    label: 'working',
                    color: colors.secondary,
                    onColor: colors.onSecondary,
                  ),
              ],
            ),
            // Local copy: fields are not promoted by `if (session != null)`.
            if (current != null) ...[
              const Divider(height: 24),
              _InfoRow(label: 'user', value: current.userId ?? '-'),
              _InfoRow(label: 'name', value: current.displayName ?? '-'),
              const SizedBox(height: 8),
              _TokenBlock(token: current.accessToken),
              const SizedBox(height: 8),
              _LabeledRow(
                label: 'expires in',
                child: _ExpiryCountdown(expiresAt: current.expiresAt),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Live "time until expiry" readout.
///
/// Remaining time depends on the wall clock, so it has to be recomputed on a
/// timer: the auth state stream only emits when the session itself changes,
/// which is why building this value once left it frozen.
class _ExpiryCountdown extends StatefulWidget {
  const _ExpiryCountdown({required this.expiresAt});

  final DateTime? expiresAt;

  @override
  State<_ExpiryCountdown> createState() => _ExpiryCountdownState();
}

class _ExpiryCountdownState extends State<_ExpiryCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTicking();
  }

  @override
  void didUpdateWidget(covariant _ExpiryCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expiresAt != widget.expiresAt) {
      _stopTicking();
      _startTicking();
    }
  }

  @override
  void dispose() {
    _stopTicking();
    super.dispose();
  }

  void _startTicking() {
    // Nothing to count down when the session carries no expiry.
    if (widget.expiresAt == null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopTicking() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expiresAt = widget.expiresAt;
    if (expiresAt == null) {
      return Text('no expiry', style: theme.textTheme.bodyMedium);
    }

    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.isNegative) {
      return Text(
        'expired',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.error,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    return Text('${remaining.inSeconds}s', style: theme.textTheme.bodyMedium);
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.color,
    required this.onColor,
  });

  final String label;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color,
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        child: Text(
          label,
          style:
              Theme.of(context).textTheme.labelMedium?.copyWith(color: onColor),
        ),
      );
}

/// The complete access token, wrapped over as many lines as it needs.
///
/// A JWT is a single unbreakable word: it contains no spaces, so the text
/// layout has nowhere to break it and a plain [Text] overflows its box. Zero
/// width spaces are inserted periodically to create break opportunities without
/// changing what is rendered.
class _TokenBlock extends StatelessWidget {
  const _TokenBlock({required this.token});

  final String token;

  static const _chunk = 24;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'token',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _breakable(token),
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            height: 1.5,
          ),
        ),
      ],
    );
  }

  static String _breakable(String value) {
    if (value.length <= _chunk) return value;
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i += _chunk) {
      final end = i + _chunk < value.length ? i + _chunk : value.length;
      if (i > 0) buffer.write('\u200B');
      buffer.write(value.substring(i, end));
    }
    return buffer.toString();
  }
}

/// A fixed-width label next to any value widget.
class _LabeledRow extends StatelessWidget {
  const _LabeledRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Convenience form of [_LabeledRow] for plain text.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => _LabeledRow(
        label: label,
        child: Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium,
          overflow: TextOverflow.ellipsis,
        ),
      );
}

/// Failure surface. Uses the theme's error container rather than literal red,
/// so it stays legible in dark mode too.
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error});

  final AppException error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 20, color: colors.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    error.message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onErrorContainer,
                    ),
                  ),
                  if (error.code != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'code: ${error.code}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onErrorContainer,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Backend choice, as a properly labelled control with a full-width tap target.
class _BackendCard extends StatelessWidget {
  const _BackendCard({
    required this.useBackend,
    required this.baseUrl,
    required this.onChanged,
  });

  final bool useBackend;
  final String baseUrl;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Card(
        child: SwitchListTile.adaptive(
          value: useBackend,
          onChanged: onChanged,
          title: const Text('Live backend'),
          subtitle: Text(useBackend ? baseUrl : 'offline double, no server'),
          secondary: const Icon(Icons.cloud_outlined),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      );
}

/// Sign-in form. The password can be revealed, and submitting from the keyboard
/// triggers the same action as the button.
class _LoginCard extends StatefulWidget {
  const _LoginCard({
    required this.username,
    required this.password,
    required this.busy,
    required this.onLogin,
  });

  final TextEditingController username;
  final TextEditingController password;
  final bool busy;
  final VoidCallback onLogin;

  @override
  State<_LoginCard> createState() => _LoginCardState();
}

class _LoginCardState extends State<_LoginCard> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Sign in', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            TextField(
              controller: widget.username,
              enabled: !widget.busy,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.password,
              enabled: !widget.busy,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => widget.onLogin(),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.key_outlined),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscure ? Icons.visibility_outlined : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Demo account: user / user',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              // Disabling while a request is in flight prevents double submits.
              onPressed: widget.busy ? null : widget.onLogin,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: widget.busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Log in'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Actions available once a session exists.
class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.auth,
    required this.session,
    required this.busy,
    required this.onCallMe,
    required this.onRefresh,
    required this.onLogout,
  });

  final AuthManager auth;
  final AuthSession session;
  final bool busy;
  final VoidCallback onCallMe;
  final VoidCallback onRefresh;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Session', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Requests carry the bearer token; an expired one is renewed '
              'transparently before it is sent.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onCallMe,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Call /me'),
            ),
            const SizedBox(height: 12),
            // Wrap keeps actions side by side on wide screens and stacked on
            // narrow ones, without overflowing either way.
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton(
                  onPressed: busy ? null : onRefresh,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(140, 48),
                  ),
                  child: const Text('Refresh'),
                ),
                TextButton(
                  onPressed: busy ? null : onLogout,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(140, 48),
                    foregroundColor: colors.error,
                  ),
                  child: const Text('Log out'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Debug hooks of the demo backend, visually separated from real actions.
class _DebugCard extends StatelessWidget {
  const _DebugCard({
    required this.onExpireNow,
    required this.onExpireSoon,
    required this.onReset,
  });

  final VoidCallback onExpireNow;
  final VoidCallback onExpireSoon;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.bug_report_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text('Debug', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Force token expiry without waiting for it to happen.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton(
                  onPressed: onExpireNow,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(140, 48),
                  ),
                  child: const Text('Expire now'),
                ),
                OutlinedButton(
                  onPressed: onExpireSoon,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(140, 48),
                  ),
                  child: const Text('Expire in 10s'),
                ),
                TextButton(
                  onPressed: onReset,
                  style: TextButton.styleFrom(minimumSize: const Size(120, 48)),
                  child: const Text('Reset'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
