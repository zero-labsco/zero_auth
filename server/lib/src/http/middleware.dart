import 'dart:io';

/// CORS handling so Flutter Web, and any browser client, can call this backend.
///
/// Returns `true` when the request was a preflight and has already been
/// answered, meaning the caller must stop processing it.
bool applyCors(HttpRequest request) {
  final response = request.response;
  response.headers
    ..set('Access-Control-Allow-Origin', '*')
    ..set('Access-Control-Allow-Headers', 'Content-Type, Authorization')
    ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');

  if (request.method == 'OPTIONS') {
    response.statusCode = 204;
    response.close();
    return true;
  }
  return false;
}

/// Extracts `Authorization: Bearer <token>`, or `null` when absent or
/// malformed.
String? bearerToken(HttpRequest request) {
  final header = request.headers.value('authorization');
  if (header == null) return null;
  final parts = header.split(' ');
  if (parts.length != 2) return null;
  if (parts[0].toLowerCase() != 'bearer') return null;
  final token = parts[1].trim();
  return token.isEmpty ? null : token;
}
