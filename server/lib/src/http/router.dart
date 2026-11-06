import 'dart:io';

typedef RouteHandler = Future<void> Function(HttpRequest request);

/// Tiny method + path router.
///
/// A real backend would use shelf or dart_frog; this router stays minimal on
/// purpose. The demo backend has exactly one dependency: `crypto`, used only
/// for HMAC-SHA256 token signing.
final class Router {
  final Map<String, RouteHandler> _routes = {};

  void get(String path, RouteHandler handler) => _add('GET', path, handler);

  void post(String path, RouteHandler handler) => _add('POST', path, handler);

  void _add(String method, String path, RouteHandler handler) {
    _routes['$method $path'] = handler;
  }

  /// Returns the handler for [method] + [path], or `null` when no route matches.
  RouteHandler? match(String method, String path) => _routes['$method $path'];
}
