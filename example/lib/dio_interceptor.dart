import 'package:dio/dio.dart';
import 'package:zero_auth/zero_auth.dart';

/// Dio interceptor that attaches `Authorization: Bearer <token>` when a session
/// is active, and skips the header when unauthenticated.
final class AuthInterceptor extends Interceptor {
  AuthInterceptor(this.source);

  final AuthTokenSource source;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = source.accessToken;
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}

/// Retries a request once after a transparent refresh.
///
/// Use this when your backend rejects an expired token with 401 even though the
/// client still believed the token was valid (for example the server revoked it
/// early). It refreshes through the manager (single-flight) and replays the
/// request exactly once, so a retry loop cannot form.
final class AuthRetryInterceptor extends QueuedInterceptor {
  AuthRetryInterceptor({required this.manager, required this.dio});

  final AuthManager manager;
  final Dio dio;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode != 401) {
      handler.next(err);
      return;
    }

    final options = err.requestOptions;
    // Only one retry per request: a second 401 means refreshing did not help.
    if (options.extra['retried'] == true) {
      handler.next(err);
      return;
    }

    try {
      await manager.refresh();
      final token = await manager.validAccessToken();
      if (token == null) {
        handler.next(err);
        return;
      }
      options.headers['Authorization'] = 'Bearer $token';
      options.extra['retried'] = true;
      handler.resolve(await dio.fetch(options));
    } on Object {
      handler.next(err);
    }
  }
}

/// Variant that never sends an expired token: when the session has expired it
/// transparently renews it through [AuthManager.validAccessToken] (which reuses
/// the single-flight refresh) before attaching the header.
///
/// Extends [QueuedInterceptor] so concurrent requests wait for one shared
/// refresh instead of each triggering its own.
final class RefreshingAuthInterceptor extends QueuedInterceptor {
  RefreshingAuthInterceptor(this.manager);

  final AuthManager manager;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await manager.validAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}
