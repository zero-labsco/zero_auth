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
