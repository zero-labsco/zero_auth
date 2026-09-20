import 'package:meta/meta.dart';
import 'package:zero_auth/zero_auth.dart';

/// An explicit success/failure wrapper.
/// 显式的成功 / 失败包装。
///
/// Useful when a caller wants to handle a domain failure without `try/catch`.
/// Prefer throwing an [AppException] for truly exceptional flows; use [Result]
/// when "no value" is an expected outcome.
/// 当调用方希望不借助 `try/catch` 处理领域失败时很有用。真正异常的路径建议抛 [AppException]；
/// 「无值」属于预期结果时再用 [Result]。
///
/// NOTE: kept under `src/error/` so the whole folder can later be lifted out
/// into a standalone `zero_error` package without touching any call sites.
/// 说明：置于 `src/error/`，便于日后整体抽离为独立 `zero_error` 包，而调用点保持不变。
@immutable
sealed class Result<T> {
  const Result();

  /// Returns the value or throws the contained [AppException].
  /// 返回值，或抛出内部持有的 [AppException]。
  T get getOrThrow;

  /// Maps a success value, leaving failures untouched.
  /// 映射成功值，失败保持不变。
  Result<R> map<R>(R Function(T value) transform);

  /// Returns `true` when this is a [Ok].
  /// 当为 [Ok] 时为 `true`。
  bool get isOk;

  /// Returns `true` when this is a [Err].
  /// 当为 [Err] 时为 `true`。
  bool get isErr;
}

/// Successful [Result] holding a value of type [T].
/// 持有类型 [T] 值的成功 [Result]。
final class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);

  @override
  T get getOrThrow => value;

  @override
  Result<R> map<R>(R Function(T value) transform) => Ok<R>(transform(value));

  @override
  bool get isOk => true;

  @override
  bool get isErr => false;

  @override
  bool operator ==(Object other) => other is Ok<T> && other.value == value;

  @override
  int get hashCode => Object.hash('Ok', value);
}

/// Failed [Result] holding the failure.
///
/// [error] is typed as [Object] so a caller can wrap non-[AppException] causes;
/// use [appException] when you specifically need the mapped domain error.
/// 失败 [Result]，持有失败原因。
///
/// [error] 类型为 [Object]，以便包装非 [AppException] 的底层原因；需要映射后的
/// 领域错误时请用 [appException]。
final class Err<T> extends Result<T> {
  final Object error;
  const Err(this.error);

  /// The failure as an [AppException], or `null` when it is not one.
  /// 作为 [AppException] 的失败原因；不是该类型时为 `null`。
  AppException? get appException =>
      error is AppException ? error as AppException : null;

  @override
  T get getOrThrow => throw error;

  @override
  Result<R> map<R>(R Function(T value) transform) => Err<R>(error);

  @override
  bool get isOk => false;

  @override
  bool get isErr => true;

  @override
  bool operator ==(Object other) => other is Err<T> && other.error == error;

  @override
  int get hashCode => Object.hash('Err', error);
}
