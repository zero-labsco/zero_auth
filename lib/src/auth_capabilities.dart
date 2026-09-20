/// Optional capabilities a strategy may implement on top of [AuthStrategy].
///
/// The core contract stays at four methods so every backend can satisfy it.
/// Anything else your app needs — password reset, password change,
/// re-authentication — is opt-in: implement one of these interfaces and detect it
/// with `AuthManager.supports<T>()`.
/// 策略可以在 [AuthStrategy] 之上实现的可选能力。
///
/// 核心契约保持在四个方法，以便任何后端都能满足。其它需求（密码重置、修改密码、
/// 重新认证）都是可选的：实现这里的某个接口，再用 `AuthManager.supports<T>()` 检测。
///
/// ```dart
/// class MyAuthStrategy implements AuthStrategy, SupportsPasswordReset { ... }
///
/// if (auth.supports<SupportsPasswordReset>()) {
///   await (auth.strategy as SupportsPasswordReset).requestPasswordReset(email);
/// }
/// ```
library;

import 'auth_session.dart';
import 'auth_strategy.dart';

/// Sends a password-reset request for the given identifier (email, phone…).
/// 为给定标识（邮箱、手机号等）发起密码重置请求。
abstract interface class SupportsPasswordReset {
  /// Asks the backend to start a password reset; the user completes it out of
  /// band (email link, SMS code).
  /// 请求后端启动密码重置，由用户在带外完成（邮件链接、短信验证码）。
  Future<void> requestPasswordReset(String identifier);
}

/// Changes the password of the signed-in user.
/// 修改已登录用户的密码。
abstract interface class SupportsPasswordChange {
  /// Verifies [currentPassword] and replaces it with [newPassword].
  /// 校验 [currentPassword] 并将其替换为 [newPassword]。
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });
}

/// Re-authenticates a user before a sensitive action.
/// 在敏感操作前重新认证用户。
abstract interface class SupportsReauthentication {
  /// Confirms the user's credentials again and returns a fresh session.
  /// 再次确认用户凭据并返回新的会话。
  Future<AuthSession> reauthenticate(Credentials credentials);
}
