# Known Risks & Post-release Watchlist / 已知风险与发版后观察清单

> Scope / 适用范围: `zero_auth` **1.1.0**.
> 本文件记录发版时**有意接受**的风险与需要观察的项 —— 它们不是已知缺陷（缺陷见
> `CHANGELOG.md` 的 1.1.0 "Fixed" 段），而是"当前判断下性价比最高的选择"。
> Each entry states what could go wrong, how to notice it, and what to do if it
> does. 每条都写清：会出什么问题、如何察觉、真发生了怎么办。
>
> **Risk ids are never reused** — R1–R4, R8, R10 and R12 were addressed in
> `1.1.0` and removed from this file, so the ids below are deliberately not
> contiguous. A new risk always takes the next unused number.
> **风险编号不会复用** —— R1–R4、R8、R10、R12 已在 `1.1.0` 兑现并从本文件移除，
> 因此下方编号刻意不连续。新增风险一律取下一个未使用的编号。
>
> Repo-internal: this file is **not** published to pub.dev (see `.pubignore`).
> 仓库内部文档，**不**随包发布（见 `.pubignore`）。

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

## R9. Duplicate-state suppression can swallow a genuine re-login / 状态去重会吞掉一次真实的重新登录

| | |
|---|---|
| Risk / 风险 | `_emit` drops a state equal to the current one. If the backend returns a **byte-identical** session (same token, expiry and claims — a replayed login, or a reused token), a second `login()` emits nothing: the state is already `Authenticated`, so a UI driven purely by the stream never rebuilds. `_emit` 会丢弃与当前值相等的状态。若后端返回**完全相同**的会话（令牌、过期、claims 都一样 —— 重放登录或复用令牌），第二次 `login()` 不会发出任何状态：状态早已是 `Authenticated`，只依赖流的界面不会重建。 |
| Why accepted / 为何接受 | Suppression is what keeps `Refreshing → Authenticated` from rebuilding the tree on every renewal, and an identical session means there is nothing new to render. 去重正是避免每次续期都因 `Refreshing → Authenticated` 重建整棵树的原因；而完全相同的会话本就没有新内容可渲染。 |
| Trigger / 触发条件 | A backend that hands out reusable / deterministic sessions, or logging in twice with the same identity. 后端签发可复用 / 确定性会话，或用同一身份连续登录两次。 |
| Watch / 观察 | "I pressed log in and nothing happened" while `current` already reads `Authenticated`. 「点了登录没反应」，而 `current` 已经是 `Authenticated`。 |
| Mitigation today / 当前缓解 | Trust the return value: `login()` / `register()` / `loginWith()` always return the `Authenticated` they installed, even when the stream stays quiet. 以返回值为准：`login()` / `register()` / `loginWith()` 总会返回它安装的 `Authenticated`，即便流保持安静。 |
| Plan / 计划 | None — intended behaviour. Keep as-is in 1.x. 无需变更，这是预期行为，1.x 保持。 |

---

## R11. `preserveSessionDetails` keeps an identity the backend no longer vouches for / 保留身份字段会留下后端已不再背书的身份

| | |
|---|---|
| Risk / 风险 | With the default `true`, a renewal that returns tokens only carries the previous `userId` / `displayName` / `claims` onto the new session. If the backend changed a name or a permission inside that window but answers with tokens alone, the UI keeps showing the stale `claims` — for example a `role` that was revoked. 默认 `true` 时，只返回令牌的续期会把上一个会话的 `userId` / `displayName` / `claims` 带到新会话。若后端在这个窗口内改了名称或权限却只回令牌，界面会继续显示过期的 `claims` —— 例如一个已被撤销的 `role`。 |
| Why accepted / 为何接受 | Losing the identity is worse: it empties `SessionHandle.userId` on logout and blanks the UI. Most backends keep permissions out of the renewal response anyway. 丢失身份的代价更大：它会使登出时的 `SessionHandle.userId` 变空、界面显示空白；且多数后端本就不在续期响应里放权限。 |
| Trigger / 触发条件 | A backend that returns tokens only **and** whose claims can change between renewals. 后端续期只返回令牌，**且**其 claims 会在两次续期之间变化。 |
| Watch / 观察 | A display name or permission that does not update until the next full login. 显示名或权限直到下次完整登录才更新。 |
| Mitigation today / 当前缓解 | Documented on the Configuration page. Pull authoritative claims with `updateSession()` when you need them, or set `preserveSessionDetails: false` to take the backend answer verbatim. 已写入配置页。需要权威 claims 时用 `updateSession()` 拉一次，或把 `preserveSessionDetails` 设为 `false`，原样采用后端响应。 |
| Plan / 计划 | Keep the default; revisit at `1.1.0` on feedback. 保留默认值；`1.1.0` 依反馈复查。 |

---

## Post-release review cadence / 发版后复查节奏

- **First 7 days / 前 7 天**: watch issues for the signals listed above —
  `resurrected session`, `signed out after restart`, `refresh loop`,
  `activeId null`, `slow startup`. 按上面的信号关注 issue。
- **Day 30 / 第 30 天**: any item with **no** reports drops to "accepted, no action";
  any item with a report becomes a `fix/` branch plus a regression test, released
  as `1.1.x`. 无报告项降为「已接受」；有报告项转为 `fix/` 分支 + 回归测试，发 `1.1.x`。
- **Every release / 每个版本**: re-read this file and update it — an accepted risk
  that no longer applies should be deleted, not left to rot.
  每次发版复查并更新本文件：不再适用的风险应删除，而不是留着腐烂。

## Reporting / 上报

Use the bug template and quote the risk id (`R5`–`R7`, `R9`, `R11`) if it matches:
提交 bug 时若匹配某项，请引用风险编号（`R5`–`R7`、`R9`、`R11`）：

- 🐛 [Report a Bug](https://github.com/zero-labsco/zero_auth/issues/new?template=bug_report.md)
