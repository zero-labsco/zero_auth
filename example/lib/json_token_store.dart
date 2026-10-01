import 'dart:convert';
import 'dart:io';

import 'package:zero_auth/zero_auth.dart';

/// A [TokenStore] backed by a JSON file on disk.
///
/// It uses [AuthSession.toJson] / [AuthSession.fromJson], so it is portable to
/// any Dart target that has `dart:io` (server, CLI, desktop). For Flutter
/// mobile use the encrypted [SecureTokenStore] instead — a plaintext file is not
/// a secure location for refresh tokens.
final class JsonTokenStore implements TokenStore {
  JsonTokenStore(this.file);

  final File file;

  @override
  Future<void> save(AuthSession session) async {
    await file.writeAsString(jsonEncode(session.toJson()));
  }

  @override
  Future<AuthSession?> load() async {
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    if (content.isEmpty) return null;

    // Decode before validating: `jsonDecode` throws on a truncated file, so a
    // partial write has to be caught here — `tryFromJson` only guards the shape
    // of an already-decoded value.
    // 先解码再校验：`jsonDecode` 对截断文件会抛异常，因此写入中断必须在这里拦住 ——
    // `tryFromJson` 只负责校验已解码值的形状。
    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException {
      return null;
    }
    return AuthSession.tryFromJson(decoded);
  }

  @override
  Future<void> clear() async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}
