/// `zero_auth` — backend-agnostic auth state machine & session lifecycle.
///
/// A pure-Dart, headless core that models "is the user logged in, who are they,
/// and how did they log in / out / recover". It does **not** ship native code,
/// a backend SDK, UI widgets, or a state-management framework. Wire your own
/// backend via [AuthStrategy], and your own persistence via [TokenStore].
///
/// 后端无关的认证状态机与会话生命周期编排。纯 Dart、无头（headless）内核，
/// 不内置原生代码、后端 SDK、UI 组件或状态管理框架；通过 [AuthStrategy] 接入自有
/// 后端，通过 [TokenStore] 接入自有持久化层。
library;

export 'src/auth_state.dart';
export 'src/auth_session.dart';
export 'src/auth_strategy.dart';
export 'src/auth_capabilities.dart';
export 'src/token_store.dart';
export 'src/auth_token_source.dart';
export 'src/auth_manager.dart';
export 'src/auth_manager_group.dart';
export 'src/exceptions.dart';
export 'src/error/error.dart';
