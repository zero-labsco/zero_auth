import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Largest request body accepted, so a demo server cannot be asked to buffer
/// unbounded input.
/// 接受的最大请求体，避免演示服务端被要求缓冲无限大的输入。
const int maxBodyBytes = 64 * 1024;

/// Reads and parses a JSON object body, tolerating an empty body.
///
/// Returns `null` when the body is too large, is not valid JSON, or is not a
/// JSON object; the caller turns that into a `400`. Casting fields inside the
/// parsed map is the handler's job — see `AuthController._stringField`.
/// 读取并解析 JSON 对象请求体，允许空体。
///
/// 请求体过大、不是合法 JSON 或不是 JSON 对象时返回 `null`，由调用方转成 `400`。
/// 解析后各字段的类型转换由处理器负责 —— 参见 `AuthController._stringField`。
Future<Map<String, dynamic>?> readJsonBody(
  HttpRequest request, {
  int maxBytes = maxBodyBytes,
}) async {
  // `contentLength` is -1 for chunked bodies, which are checked after reading.
  // 分块传输时 `contentLength` 为 -1，这类请求在读完后再检查。
  if (request.contentLength > maxBytes) return null;

  final List<int> raw;
  try {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
      // Stop the moment the budget is blown instead of buffering the rest: a
      // chunked body declares no length, so reading it whole first would let
      // an unbounded stream sit in memory until the check below ran.
      // 预算一超限即刻停止，而不是把剩余部分也缓冲进来：分块请求体不声明长度，
      // 先整体读入会让无边界的流一直占用内存，直到下面的检查才运行。
      if (builder.length > maxBytes) return null;
    }
    raw = builder.takeBytes();
  } on Object {
    // Client disconnected mid-body, or the encoding was invalid.
    return null;
  }
  if (raw.length > maxBytes) return null;

  final String text;
  try {
    text = utf8.decode(raw);
  } on Object {
    // Not valid UTF-8.
    return null;
  }
  if (text.trim().isEmpty) return <String, dynamic>{};

  try {
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
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
