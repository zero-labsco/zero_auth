import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:zero_auth/zero_auth.dart';

/// A [TokenStore] backed by `flutter_secure_storage`.
///
/// Stores each session field under its own key so no (de)serialization library
/// is required. Swap for your own codec as needed.
final class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kAccess = 'za_access';
  static const _kRefresh = 'za_refresh';
  static const _kExpiry = 'za_expiry';
  static const _kUserId = 'za_userId';
  static const _kName = 'za_name';

  @override
  Future<void> save(AuthSession session) async {
    await _storage.write(key: _kAccess, value: session.accessToken);
    if (session.refreshToken != null) {
      await _storage.write(key: _kRefresh, value: session.refreshToken!.value);
    }
    if (session.expiresAt != null) {
      await _storage.write(
        key: _kExpiry,
        value: session.expiresAt!.toIso8601String(),
      );
    }
    if (session.userId != null) {
      await _storage.write(key: _kUserId, value: session.userId!);
    }
    if (session.displayName != null) {
      await _storage.write(key: _kName, value: session.displayName!);
    }
  }

  @override
  Future<AuthSession?> load() async {
    final access = await _storage.read(key: _kAccess);
    if (access == null) return null;
    final refresh = await _storage.read(key: _kRefresh);
    final expiry = await _storage.read(key: _kExpiry);
    final userId = await _storage.read(key: _kUserId);
    final name = await _storage.read(key: _kName);
    return AuthSession(
      accessToken: access,
      refreshToken: refresh == null ? null : RefreshToken(refresh),
      expiresAt: expiry == null ? null : DateTime.tryParse(expiry),
      userId: userId,
      displayName: name,
    );
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kExpiry);
    await _storage.delete(key: _kUserId);
    await _storage.delete(key: _kName);
  }
}
