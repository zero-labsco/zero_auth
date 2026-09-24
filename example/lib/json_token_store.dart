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
    // tryFromJson, not fromJson: a partial write or a hand-edited file must read
    // as "not signed in", not throw a FormatException at startup.
    return AuthSession.tryFromJson(jsonDecode(content));
  }

  @override
  Future<void> clear() async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}
