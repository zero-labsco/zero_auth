import 'package:dio/dio.dart';
import 'package:zero_auth/zero_auth.dart';

/// Dio interceptor that attaches `Authorization: Bearer <token>` when a session
/// is active, and skips the header when unauthenticated.
///
/// NOTE: this reads the synchronous `accessToken`, which may already be expired.
/// Use [RefreshingAuthInterceptor] (or `validAccessToken()`) whenever the token
/// actually reaches a server.
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

/// Variant that never sends an expired token: it reads
/// [AuthTokenSource.validAccessToken], which renews the session first (reusing
/// the single-flight refresh) before attaching the header.
///
/// It accepts the interface rather than an [AuthManager], so any source can be
/// wired in — the manager, an [AuthManagerGroup], or your own.
///
/// Extends [QueuedInterceptor] so concurrent requests wait for one shared
/// refresh instead of each triggering its own.
final class RefreshingAuthInterceptor extends QueuedInterceptor {
  RefreshingAuthInterceptor(this.source);

  final AuthTokenSource source;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final token = await source.validAccessToken();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    } on Object catch (error) {
      // `handler.next` must always run: this method is `async`, so a thrown
      // error would become an unawaited future and leave the request hanging —
      // and since this is a `QueuedInterceptor`, one hanging request stalls
      // every request behind it.
      // `handler.next` 必须始终被调用：本方法是 `async`，抛出的异常会变成无人等待的
      // future，让请求永久挂起 —— 而它又是 `QueuedInterceptor`，一个挂起会堵住后面
      // 的所有请求。
      handler.reject(
        DioException.requestCancelled(
          requestOptions: options,
          reason: error,
        ),
      );
      return;
    }
    handler.next(options);
  }
}
