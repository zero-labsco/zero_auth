import 'package:meta/meta.dart';

/// The single public error type shared across the `zero_foundation` series.
/// `zero_foundation` 系列共用的唯一公共错误类型。
///
/// Domain packages (e.g. `zero_auth`) never leak raw [Exception]s across their
/// public surface; instead they map internal failures into a subtype of
/// [AppException] so callers can present errors uniformly.
/// 领域包（如 `zero_auth`）绝不在公共面泄露裸 [Exception]；而是把内部失败映射为
/// [AppException] 的子类型，使调用方可以统一展示错误。
///
/// NOTE: kept under `src/error/` so the whole folder can later be lifted out
/// into a standalone `zero_error` package without touching any call sites.
/// 说明：置于 `src/error/`，便于日后整体抽离为独立 `zero_error` 包，而调用点保持不变。
@immutable
abstract class AppException implements Exception {
  /// Human-readable, user-facing message.
  /// 可读、面向用户的消息。
  final String message;

  /// Stable, machine-readable code (e.g. `'invalid_credentials'`).
  /// 稳定、机器可读的编码（如 `'invalid_credentials'`）。
  final String? code;

  /// The underlying cause, preserved for debugging/logging.
  /// 底层原因，保留用于调试 / 日志。
  final Object? cause;

  const AppException(
    this.message, {
    this.code,
    this.cause,
  });

  @override
  String toString() {
    final buffer = StringBuffer('AppException');
    if (code != null) buffer.write('($code)');
    buffer.write(': $message');
    return buffer.toString();
  }
}
