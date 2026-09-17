import 'dart:convert';
import 'dart:io';

/// Reads and parses a JSON request body, tolerating an empty body.
Future<Map<String, dynamic>> readJsonBody(HttpRequest request) async {
  final raw = await utf8.decoder.bind(request).join();
  if (raw.trim().isEmpty) return <String, dynamic>{};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    return <String, dynamic>{};
  } on FormatException {
    return <String, dynamic>{};
  }
}

/// Writes a JSON response and closes it.
Future<void> sendJson(
  HttpRequest request,
  int statusCode,
  Map<String, Object?> body,
) async {
  request.response
    ..statusCode = statusCode
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  await request.response.close();
}
