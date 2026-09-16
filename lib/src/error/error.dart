/// Unified error kernel for the `zero_foundation` series.
/// `zero_foundation` 系列的统一错误内核。
///
/// Exposes [AppException] as the single public error type that every `zero_*`
/// package maps its domain failures into, plus a small [Result] helper for
/// explicit success/failure returns.
/// 将 [AppException] 作为唯一的公共错误类型，供每个 `zero_*` 包把领域失败映射进来；
/// 另提供轻量 [Result] 辅助以显式表达成功 / 失败返回。
///
/// The entire `src/error/` folder is self-contained on purpose: to extract it
/// back into a standalone `zero_error` package later, just move this folder and
/// point callers at `package:zero_error` — no other edits required.
/// 整个 `src/error/` 目录刻意自包含：日后若要抽离为独立 `zero_error` 包，只需移动该目录
/// 并把调用方指向 `package:zero_error` 即可，无需改动其他代码。
library;

export 'app_exception.dart';
export 'result.dart';
