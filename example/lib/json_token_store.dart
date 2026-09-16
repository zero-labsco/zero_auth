import 'dart:convert';
import 'dart:io';

import 'package:zero_auth/zero_auth.dart';

/// A [TokenStore] backed by a JSON file on disk.
///
/// It uses [AuthSession.toJson] / [AuthSession.fromJson], so it is portable to
/// any Dart target that has `dart:io` (server, CLI, desktop). For Flutter
/// mobile use the encrypted [SecureTokenStore] instead — a plaintext file is not
/// a secure location for refresh tokens.
///
/// 基于磁盘 JSON 文件的 [TokenStore]。
///
/// 它使用 [AuthSession.toJson] / [AuthSession.fromJson]，因此可移植到任何具备
/// `dart:io` 的 Dart 目标（服务端、CLI、桌面）。在 Flutter 移动端请改用加密的
/// [SecureTokenStore]——明文文件并非刷新令牌的安全存放位置。
final class FileTokenStore implements TokenStore {
  FileTokenStore(this.file);

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
    return AuthSession.fromJson(jsonDecode(content) as Map<String, Object?>);
  }

  @override
  Future<void> clear() async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}
