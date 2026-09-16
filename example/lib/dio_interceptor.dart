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
