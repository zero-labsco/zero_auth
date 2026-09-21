# Known Risks & Post-release Watchlist / 已知风险与发版后观察清单

> Scope / 适用范围: `zero_auth` **1.0.0**.
> 本文件记录发版时**有意接受**的风险与需要观察的项 —— 它们不是已知缺陷（缺陷见
> `CHANGELOG.md` 的 1.0.0 "Fixed" 段），而是"当前判断下性价比最高的选择"。
> Each entry states what could go wrong, how to notice it, and what to do if it
> does. 每条都写清：会出什么问题、如何察觉、真发生了怎么办。
>
> Repo-internal: this file is **not** published to pub.dev (see `.pubignore`).
> 仓库内部文档，**不**随包发布（见 `.pubignore`）。

---

## R1. `AuthManagerGroup.restoreAll()` restores accounts serially / 顺序恢复账号

| | |
|---|---|
| Risk / 风险 | Every account's `TokenStore.load()` (and the renewal that may follow) waits for the previous one, so startup cost is the **sum**, not the max. 每个账号的存储读取（以及可能的续期）都要等前一个完成，启动耗时是**累加**而非取最大值。 |
| Why accepted / 为何接受 | Account counts are small (usually 1–5) and serial restores keep error attribution exact: a failure is reported for a known account, in a known order. 账号数量通常是个位数；串行恢复让错误归属精确 —— 失败能定位到具体账号与顺序。 |
| Trigger / 触发条件 | Many saved accounts **and** a slow store (Keychain / encrypted storage / network-backed). 账号较多**且**存储较慢（Keychain、加密存储、网络型存储）。 |
| Watch / 观察 | Startup traces: time from app start to first `Authenticated` scales linearly with account count. Issue reports of "slow startup with several accounts". 启动埋点：从冷启动到首个 `Authenticated` 的时间随账号数线性增长；issue 中出现「多账号启动慢」。 |
| Mitigation today / 当前缓解 | Restore outside the critical path, or call `forAccount(id).restore()` yourself with your own concurrency. 把恢复移出关键路径，或自行并发调用 `forAccount(id).restore()`。 |
| Plan / 计划 | `1.1.0`: additive `restoreAll(..., {bool parallel = true})` (or a sibling `restoreAllConcurrently`), keeping the serial default. `1.1.0` 以追加方式提供并发开关，串行仍是默认。 |

---

## R2. Extreme timing interleavings are reasoned about, not exhaustively tested / 极端时序交错靠推理，未穷举测试

| | |
|---|---|
| Risk / 风险 | Combinations such as "a refresh resolves in the same microtask as a `logout()`", or "a proactive timer fires in the same frame as `dispose()`", are guarded by the epoch mechanism but have no dedicated test. 诸如「刷新与 `logout()` 在同一微任务中落地」「主动刷新定时器与 `dispose()` 同帧触发」这类组合，由 epoch 机制守卫，但没有专门的测试。 |
| Why accepted / 为何接受 | Such tests are inherently flaky (they race the event loop); the invariants they would check are enforced structurally: every session-writing path calls `_invalidateInFlight()`, and single-flight sharing is epoch-scoped. 这类测试天生易 flaky；而它们要验证的不变量已由结构保证：所有写会话的路径都调用 `_invalidateInFlight()`，单飞共享限定在同一 epoch 内。 |
| Trigger / 触发条件 | Rapid login → logout → login, or app teardown while a renewal is in flight. 快速连续 登录 → 登出 → 登录，或续期进行中时应用销毁。 |
| Watch / 观察 | Reports of a "resurrected" session (still signed in after logout), or `Authenticated` emitted after `Unauthenticated`. 出现「会话复活」（登出后仍处于登录态）或 `Unauthenticated` 之后又发出 `Authenticated` 的报告。 |
| Mitigation today / 当前缓解 | `logout()` invalidates in-flight work **before** calling the backend; a late refresh completes with `NoActiveSessionException` instead of writing. `logout()` 在调用后端**之前**就让进行中的工作失效；迟到的刷新以 `NoActiveSessionException` 结束而不是写入。 |
| Plan / 计划 | If a single report lands, add a targeted regression test first, then harden. Otherwise revisit at `1.1.0`. 一旦出现真实报告，先补定向回归测试再加固；否则 `1.1.0` 时复查。 |

---

## R3. `clockSkew` (default 30s) amplifies renewal for very short-lived tokens / 默认 30 秒的时钟容差会放大短寿命令牌的续期

| | |
|---|---|
| Risk / 风险 | When access tokens live **shorter than the skew**, nearly every `validAccessToken()` read renews first — turning one request into one refresh. 当访问令牌寿命**短于容差**时，几乎每次 `validAccessToken()` 都会先续期 —— 一次请求伴随一次刷新。 |
| Why accepted / 为何接受 | 30s is the right default for the common 5–15 minute access token: it absorbs a device clock that runs ahead plus request latency. Shorter TTLs are a deliberate configuration choice. 30 秒对常见的 5–15 分钟令牌是正确的默认值，可吸收设备时钟偏快与请求延迟；更短 TTL 属于显式的配置选择。 |
| Trigger / 触发条件 | `expiresIn` under ~60s, or a backend that mints per-request tokens. `expiresIn` 小于约 60 秒，或后端签发一次性/每请求令牌。 |
| Watch / 观察 | Refresh-endpoint QPS tracking request QPS 1:1; users reporting "it refreshes on every call". 刷新端点 QPS 与请求 QPS 接近 1:1；用户反馈「每次调用都在刷新」。 |
| Mitigation today / 当前缓解 | Documented: lower `clockSkew` (e.g. 5s) or pass `Duration.zero` (README, `Configuration` page). 已写入文档：调小 `clockSkew`（如 5 秒）或传 `Duration.zero`。 |
| Plan / 计划 | `1.1.0`: consider clamping the effective skew to a fraction of the observed token lifetime. `1.1.0` 考虑把有效容差钳制为令牌寿命的一个比例。 |

---

## R4. A throwing `onStateChanged` observer is swallowed / 观察者抛出的异常会被吞掉

| | |
|---|---|
| Risk / 风险 | Since 1.0.0 the observer is a true side channel: its error cannot corrupt the state machine, but it also becomes **invisible** — a broken logger/analytics sink fails silently. 自 1.0.0 起观察者是真正的旁路：它的错误不会破坏状态机，但也因此**不可见** —— 坏掉的日志/埋点会静默失败。 |
| Why accepted / 为何接受 | A callback that can break authentication is far worse than one that fails quietly. 一个能破坏认证流程的回调，远比一个安静失败的回调危险。 |
| Trigger / 触发条件 | Any exception inside `onStateChanged` (or the group's `(accountId, state)` variant). `onStateChanged`（或分组的 `(accountId, state)` 版本）内部抛出任何异常。 |
| Watch / 观察 | Missing analytics rows while auth events clearly occur. 认证事件明显发生，但埋点/日志缺失。 |
| Mitigation today / 当前缓解 | Wrap your own observer body in `try/catch` and log there. 在自己的观察者内部 `try/catch` 并记录。 |
| Plan / 计划 | `1.1.0`: additive `onObserverError(Object error, StackTrace stack)` hook, defaulting to silence. `1.1.0` 追加 `onObserverError` 钩子，默认仍然静默。 |

---

## R5. The group now forgets a manager disposed outside it / 分组会遗忘在外部被释放的管理器

| | |
|---|---|
| Risk / 风险 | `_onActiveClosed()` removes the account and clears `activeId` when that manager's stream closes — including when **your own code** disposed it, not `group.remove()`. This is a behaviour change from 0.x. 当某个 manager 的流关闭时，`_onActiveClosed()` 会移除该账号并清空 `activeId` —— 包括**你自己**释放它（而非通过 `group.remove()`）的情况。这是相对 0.x 的行为变化。 |
| Why accepted / 为何接受 | Holding a released manager is a latent crash (`manager_disposed` on every later read); forgetting it is strictly safer. 持有已释放的管理器是潜伏崩溃（之后每次读取都是 `manager_disposed`）；将其遗忘显然更安全。 |
| Trigger / 触发条件 | Mixing lifecycles: a manager created by the group but disposed by a provider/scope of your own. 生命周期混用：由分组创建、却被你自己的 provider/作用域释放。 |
| Watch / 观察 | `activeId` unexpectedly `null`, or an account disappearing from `accountIds`. `activeId` 意外变成 `null`，或某个账号从 `accountIds` 中消失。 |
| Mitigation today / 当前缓解 | Always release accounts through `group.remove(id)` / `group.disposeAll()`. 始终通过 `group.remove(id)` / `group.disposeAll()` 释放。 |
| Plan / 计划 | None — intended behaviour. Keep as-is in 1.x. 无需变更，这是预期行为，1.x 保持。 |

---

## R6. Freezing the API means some future needs cost a major / 冻结 API 的代价：部分需求将需要 major 版本

| | |
|---|---|
| Risk / 风险 | `AuthState` is sealed: adding a subtype (say `Restoring`) after 1.0.0 is a breaking change, so it waits for 2.0. `AuthState` 是密封类：1.0.0 之后新增子类（如 `Restoring`）属于破坏性变更，只能等到 2.0。 |
| Why accepted / 为何接受 | 1.0.0 exists precisely to make that promise. Consumers can rely on exhaustive switches. 1.0.0 的意义就在于给出这个承诺，使用方可以放心写穷举 switch。 |
| Trigger / 触发条件 | A future feature that genuinely needs a new state (e.g. "restoring…" as a distinct UI state). 未来某个特性确实需要新状态（例如把「恢复中」做成独立 UI 状态）。 |
| Watch / 观察 | Feature requests asking for new states or for `AuthStrategy` to grow beyond four methods. 要求新增状态、或要求 `AuthStrategy` 突破四个方法的 feature request。 |
| Mitigation today / 当前缓解 | Express variation additively: `AuthState.session`, `isBusy`, `AuthError.error.code`, optional capability interfaces via `supports<T>()`. 用可追加的方式表达变化：`AuthState.session`、`isBusy`、`AuthError.error.code`，以及用 `supports<T>()` 检测的可选能力接口。 |
| Plan / 计划 | Track such requests; batch them into a single 2.0 if the pattern repeats. 收集此类需求；若形成模式，集中到 2.0 一次解决。 |

---

## R7. Proactive throttling follows the injected `clock` / 主动刷新的节流跟随注入的时钟

| | |
|---|---|
| Risk / 风险 | `_throttleWait()` measures `clock().difference(last)`. With a **fixed/injected** clock (common in tests, or a clock that only advances per request), the elapsed time stays 0, so an already-due renewal always waits the full `autoRefreshMinInterval`. `_throttleWait()` 用 `clock().difference(last)` 计算。若时钟是**固定/注入**的（测试常见，或只在请求时才推进），间隔恒为 0，于是「已到期」的续期总是等待完整的 `autoRefreshMinInterval`。 |
| Why accepted / 为何接受 | A real wall clock always advances; the fixed-clock case is a test fixture, and the behaviour there is still deterministic and safe. 真实的墙钟总会推进；固定时钟属于测试夹具，而该场景下的行为依然确定且安全。 |
| Trigger / 触发条件 | Tests or hosts that inject a non-advancing `clock` while relying on immediate re-renewal. 注入了不推进的 `clock`，却又依赖「立即再次续期」的测试或宿主。 |
| Watch / 观察 | A test that expects N renewals within one fake-clock instant. 某个测试期望在同一个 fake 时钟瞬间内发生 N 次续期。 |
| Mitigation today / 当前缓解 | Advance the injected clock between renewals, or assert on the timer rather than the count. 在两次续期之间推进注入时钟，或改为断言定时器而非次数。 |
| Plan / 计划 | None unless a real host reports it. 除非真实宿主报告，否则不变更。 |

---

## Post-release review cadence / 发版后复查节奏

- **First 7 days / 前 7 天**: watch issues for the signals listed above —
  `resurrected session`, `signed out after restart`, `refresh loop`,
  `activeId null`, `slow startup`. 按上面的信号关注 issue。
- **Day 30 / 第 30 天**: any item with **no** reports drops to "accepted, no action";
  any item with a report becomes a `fix/` branch plus a regression test, released
  as `1.0.x`. 无报告项降为「已接受」；有报告项转为 `fix/` 分支 + 回归测试，发 `1.0.x`。
- **Every release / 每个版本**: re-read this file and update it — an accepted risk
  that no longer applies should be deleted, not left to rot.
  每次发版复查并更新本文件：不再适用的风险应删除，而不是留着腐烂。

## Reporting / 上报

Use the bug template and quote the risk id (`R1`…`R7`) if it matches:
提交 bug 时若匹配某项，请引用风险编号（`R1`…`R7`）：

- 🐛 [Report a Bug](https://github.com/zero-labsco/zero_auth/issues/new?template=bug_report.md)
