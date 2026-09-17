# Zero Auth - Agent Guide

This file defines the architecture, coding conventions, and required workflows for the `zero_auth` package. AI coding agents (CodeBuddy, Trae, Cursor, Claude Code, GitHub Copilot, Codex, etc.) should read and follow it for any task in this repository. It is the single source of truth for project conventions.

## Overview
`zero_auth` is a **pure-Dart, headless auth state machine & session lifecycle** library: it models "is the user logged in, who are they, and how did they log in / out / recover". It deliberately ships **no** native code, backend SDK, HTTP client, UI, or state-management framework. Consumers bring their own backend via `AuthStrategy` and their own persistence via `TokenStore`.

## When to apply
- Implementing features, fixing bugs, or changing the public API in `lib/` (the published surface).
- Updating the example app (`example/`) or the demo backend (`server/`).
- Opening pull requests (English-only Conventional Commits title) or cutting a release / publishing to pub.dev.
- Editing `pubspec.yaml`, `analysis_options.yaml`, `README.md` / `README_zh.md`, or `CHANGELOG.md`.

## Architecture
- `lib/zero_auth.dart` — the **only** public barrel. Every public symbol must be re-exported here; consumers must never import `lib/src/` directly.
- `lib/src/`:
  - `auth_manager.dart` — `AuthManager`: the orchestrator. Owns the state machine, `restore()` / `login()` / `register()` / `logout()` / `refresh()` / `dispose()`, plus `current`, `state` (replay-last broadcast stream), `currentSession` and `accessToken` (it *is* an `AuthTokenSource`). Pass `autoRefreshAhead` to enable opt-in proactive refresh that renews tokens before expiry.
  - `auth_state.dart` — sealed `AuthState`: `Unauthenticated` / `Authenticating` / `Authenticated` / `AuthError` (+ `AuthFail` payload).
  - `auth_session.dart` — `AuthSession` (access/refresh token, expiry, user id, display name, raw claims) and `SessionHandle`.
  - `auth_strategy.dart` — `AuthStrategy` (the backend boundary), `Credentials`, `RegistrationInput`, `RefreshToken`.
  - `token_store.dart` — `TokenStore` (the only persistence boundary) + `InMemoryTokenStore`.
  - `auth_token_source.dart` — `AuthTokenSource`: read-only token source for network layers.
  - `exceptions.dart` — `AuthException` (auth-specific failures).
  - `error/` — the error kernel: `app_exception.dart` (`AppException`), `result.dart` (`Result<T>` = `Ok` / `Err`), `error.dart` (barrel).
- `test/` — unit tests written with `package:test` (NOT `flutter_test`); `fake_async` is used for timer-driven refresh behaviour; `fake_strategy.dart` is the shared test double.
- `example/` — Flutter example app (Android / iOS / Web / Windows). `main.dart` (state machine UI + backend toggle), `dio_interceptor.dart` (`AuthInterceptor`, a ready-to-copy Dio integration), `secure_token_store.dart` (`flutter_secure_storage` reference `TokenStore`; not wired into `main.dart`, it is reference material for consumers).
- `server/` — a layered `dart:io` demo backend used by the example (`dart run bin/server.dart`, port `8080`); endpoints `/login`, `/refresh`, `/logout`, `/me`, `/health`. It issues real HMAC-SHA256 JWTs (via the `crypto` package) with refresh-token rotation, family revocation and replay detection, and logs every request with status and duration. Credentials are `user` / `user`; CORS enabled. Structure: `bin/server.dart` only bootstraps, everything else lives under `lib/` (`config`, `logging`, `http`, `auth`, `handlers`). It is repo-only and **not** shipped to pub.dev (excluded via `.pubignore`).
- `zero_auth_design.md` — repo-internal design notes (excluded from the published package).
- `website/` — the **Nextra + Next.js** documentation site (Animal-Crossing theme, copied from the `zero_inspector_kit` site). Source lives under `website/pages/*.md`; it builds to `website/out/` and is then synced into `docs/` (the GitHub Pages root) by `website/scripts/sync-docs.mjs` (run automatically via a git pre-commit hook installed with `npm --prefix website run setup-hook`). `website/` is excluded from the pub package via `.pubignore`. The homepage is `website/pages/index.md`; version strings use the `__ZERO_AUTH_VERSION__` placeholder, injected from `pubspec.yaml` at build time.

### Hard constraints on `lib/`
- **Pure Dart only.** No `dart:io`, no `dart:html`/`package:web`, no platform channels, no Flutter widgets, no HTTP client. It must run unchanged on Flutter, server and CLI.
- **No hidden state.** The manager holds no UI, no backend and no native code; every side effect goes through `AuthStrategy` or `TokenStore`.
- **Errors never escape raw.** Every failure surfaced publicly is an `AppException` (typically `AuthException`); raw `Exception`s must not cross the public surface.
- **Single-flight refresh.** Concurrent `refresh()` callers must keep sharing one backend call (`_refreshCompleter`); do not "simplify" it into independent calls.
- **Rethrow after emit.** `login()` / `register()` emit `AuthError` and then rethrow; callers (and the example app) must handle or deliberately swallow that rethrow.

## Dependencies and SDK constraints
- Dart SDK `^3.4.0` (sealed classes) is the **only** SDK constraint. The package is pure Dart and does **not** declare `flutter:` in `environment` — declaring it would mis-tag the package as "Flutter" on pub.dev and force pure-Dart (CLI/server) consumers to install the Flutter SDK for no reason. A Dart package is usable from Flutter projects automatically, so no Flutter constraint is needed.
- Runtime deps: `meta` only. Resist adding dependencies; the package must stay backend- and framework-agnostic.
- Dev deps: `test`, `fake_async` (refresh timers), `flutter_lints ^4` (required by `analysis_options.yaml`).
- Keep caret (`^`) constraints; do not pin exact versions without reason.
- License: **MPL-2.0**. Do not relicense without the maintainer's explicit decision.

## Coding conventions
- Follow `effective_dart`; `analysis_options.yaml` additionally enables `always_declare_return_types`, `prefer_single_quotes`, `require_trailing_commas`, `unawaited_futures`, `use_rethrow_when_possible`, etc. Style is enforced by `dart analyze` / `flutter analyze`.
- **Doc comments are bilingual, EN-primary / ZH-secondary** in `lib/` (English paragraph first, then the Chinese one) — see `lib/zero_auth.dart`.
- **`example/` and `server/` are English-only.** UI strings, error messages and code comments there must not contain Chinese text.
- `README.md` (EN) and `README_zh.md` (ZH) are parallel documents; any content change to one must be mirrored in the other (install snippets, version strings, the "🔔 Upgrade recommended" / "🔔 推荐升级" callout, feature lists, tables).
- Conventional Commits for **both** commit messages and PR titles: `feat:`, `fix:`, `docs:`, `style:`, `refactor:`, `perf:`, `test:`, `build:`, `ci:`, `chore:`, `revert:`.
- Do not break the public API without a major version bump; add new public symbols to `lib/zero_auth.dart` only.

## Workflows

### Branching and PRs
- Branch from `main` with a typed prefix: `feat/`, `fix/`, `docs/`, `ci/`, `chore/`, `release/`, etc. `release/vX.Y.Z` is the immutable branch for a shipped version (see "Release and publish").
- Never push directly to `main`.
- PR titles are **English-only** and MUST follow Conventional Commits.

### Pull request body template / PR 正文模板

AI coding agents (CodeBuddy, Trae, Cursor, Claude Code, GitHub Copilot, Codex, etc.) and contributors SHOULD follow the body template below when opening PRs. Keep the `###` section structure; fill in real content. Use English as the primary language and Chinese as the secondary language (EN-primary, ZH-secondary) for each section. Brand the assistant with **Zero Buddy** (two words, NOT "ZeroBuddy") at the end.

AI 协作工具（CodeBuddy、Trae、Cursor、Claude Code、GitHub Copilot、Codex 等）与贡献者开 PR 时应遵循以下正文模板。保留 `###` 章节结构并填入真实内容。每个章节采用英文为主、中文为辅（EN-primary, ZH-secondary）。文末以 **Zero Buddy**（两个单词，不要写成 "ZeroBuddy"）署名。

```markdown
### Summary / 摘要

<one-line plain-English summary> + <对应中文一句话摘要>

### Changes / 变更

- <change bullet, EN> / <中文说明>
- <change bullet, EN> / <中文说明>

### Context / 背景

<why this change is needed, EN> / <改动背景的中文说明>

### Checklist / 检查项

- [ ] Title follows Conventional Commits / 标题符合约定式提交
- [ ] `dart analyze` + `flutter test` pass / 静态分析与测试通过
- [ ] `README.md` and `README_zh.md` kept in sync / 中英文档同步更新

## Test plan

- [ ] <how to verify, EN> / <验证方式>

🤖 Generated with [Zero Buddy](https://www.zerolabsco.com)
```

Notes / 说明:
- The PR **title** stays English-only and MUST follow Conventional Commits. Bilingual content goes in the body only. PR **标题**仅用英文，且必须符合约定式提交；双语内容只放在正文。

### CI
- CI lives in `.github/workflows/` and mirrors the sibling project `zero_network_kit`. Keep the two in sync when a workflow changes.
  CI 位于 `.github/workflows/`，与兄弟项目 `zero_network_kit` 保持一致；改动时请同步两边。
  - `ci.yml` — `path-filter` (dorny/paths-filter) → `analyze-and-test` (package: `dart format` + `dart analyze` + `dart test`; example: `flutter analyze` + `flutter test`), `server-check` (only when `server/**` changed), `pana-check` (pana score ≥ 120). Docs-only PRs still trigger the workflow but the heavy jobs skip green, so branch-protection required checks always resolve.
  - `pr-title-check.yml` — `amannn/action-semantic-pull-request@v6`, allowed types `feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert`; skips the `github-actions[bot]` sync commit from the format bot.
  - `dart-format-fix.yml` — auto-runs `dart format` on PRs (package + `example/` + `server/`) and pushes fixes back.
  - `link-check.yml` — lychee scan of `README.md`, `README_zh.md`, `USAGE.md`, `CHANGELOG.md`, `docs/**`.
  - `dependabot-pr-bilingual.yml` — appends a bilingual (EN/ZH) body to Dependabot PRs; `.github/dependabot.yml` tracks pub deps (root weekly, `example/` monthly) and GitHub Actions (weekly).
  - `stale.yml` — marks issues/PRs stale after 60 days.
  - `pub-publish.yml` — triggered by the `vX.Y.Z` **tag**; reuses `ci.yml`, verifies `pubspec.yaml` version == tag and that `CHANGELOG.md` has a `## X.Y.Z` entry, then publishes via `k-paxian/dart-package-publisher@v1.6` with the `PUB_CREDENTIALS_JSON` secret (do NOT pass OIDC fields) and creates the GitHub Release.
- **Pinned toolchain:** every workflow that runs `dart format` pins Flutter `3.41.7` (`subosito/flutter-action@v2`). Keep all pins identical, otherwise the format bot and CI disagree and loop forever.
  固定工具链：所有跑 `dart format` 的 workflow 都固定 Flutter `3.41.7`；必须保持一致，否则格式化机器人与 CI 会互相打架、无限循环。
- Whether or not CI exists, always run the local checks in "Release and publish" before pushing.

### Local verification (always run before pushing)
```powershell
cd d:\FlutterProgram\zero_auth
dart format .                 # must report no changes
dart analyze                  # pure-Dart package: no errors
cd example && flutter analyze && flutter test
cd ..\server && dart analyze  # demo backend
cd d:\FlutterProgram\zero_auth && dart pub publish --dry-run   # 0 warnings
```

> `server/` is a separate package and is **excluded from the root `dart analyze`**
> (see `analyzer.exclude` in `analysis_options.yaml`). Analysing it from the root
> fails on its `package:zero_auth_example_server/...` imports. Always analyse it
> from inside the folder, as the line above does.
>
> `server/` 是独立 package，已被**排除在根目录的 `dart analyze` 之外**（见
> `analysis_options.yaml` 的 `analyzer.exclude`）。在根目录分析会因
> `package:zero_auth_example_server/...` 导入而失败，请始终在其目录内分析。

### Docs site preflight (always run before pushing `website/**`)

The Pages site is **pre-built**: `pages.yml` uploads `docs/` verbatim and never
builds `website/`. `docs/` is regenerated only by the git pre-commit hook, so an
uninstalled hook silently ships a stale site — missing pages, and an outdated
version on the Installation page because `__ZERO_AUTH_VERSION__` is injected at
build time.
文档站是**预先构建**的：`pages.yml` 原样上传 `docs/`，从不构建 `website/`。`docs/`
只由 git pre-commit hook 重建，hook 未安装会导致线上静默停留在旧站点——缺页面，且安装
页版本号过期（`__ZERO_AUTH_VERSION__` 是在构建时注入的）。

```powershell
# Once per clone — installs the hook that rebuilds & syncs docs/.
# 每个克隆仅需一次——安装负责重建并同步 docs/ 的 hook。
npm --prefix website run setup-hook

# Sanity check — this must return True.
# 检查——必须返回 True。
Test-Path .git\hooks\pre-commit

# Recovery — website/ already committed and docs/ still stale.
# 补救——website/ 改动已提交、docs/ 仍是旧的。
node website/scripts/sync-docs.mjs --force
```

> **Symptom → cause / 症状 → 原因:** you changed `website/**` (or bumped the
> version) but `git status` shows no `docs/` changes ⇒ the hook is missing. Run
> the setup command above, then the `--force` sync once to catch up.
>
> 你改了 `website/**`（或升了版本号）而 `git status` 里没有 `docs/` 变化 ⇒ hook 未安装。
> 先执行上面的安装命令，再跑一次 `--force` 补构建。

### Running the demo end to end
```powershell
# Terminal 1 — demo backend
cd d:\FlutterProgram\zero_auth\server
dart run bin/server.dart      # http://localhost:8080

# Terminal 2 — example app
cd d:\FlutterProgram\zero_auth\example
flutter run
```
- The example defaults to the **real backend** (`_useBackend = true`); the AppBar switch falls back to the offline double `_DemoStrategy`.
- The demo account is `user` / `user`. A wrong password shows the `AuthError` path; `Call /me` proves the bearer header reaches the backend. Access tokens live 120s, so pressing **Refresh** (or calling `/me` after expiry) shows renewal and rotation in the logs.
- On an Android emulator use `http://10.0.2.2:8080` (`_baseUrl` in `example/lib/main.dart`).

### Release and publish
1. Bump `version` in `pubspec.yaml` (semver; major bump for breaking public API).
   **Mandatory version-bump checklist — every item MUST be updated to the new `X.Y.Z` (old string fully removed):**
   - [ ] `pubspec.yaml` → `version: X.Y.Z`
   - [ ] `README.md`: the `^X.Y.Z` dependency constraint, the `` `X.Y.Z` `` placeholder in the GitHub install snippet, the `ref: release/vX.Y.Z` git ref, and the "🔔 Upgrade recommended" callout (summarize **only** what the current release changed; never reference previous versions).
   - [ ] `README_zh.md`: the same four spots (`^X.Y.Z`, `` `X.Y.Z` ``, `ref: release/vX.Y.Z`, "🔔 推荐升级：" callout).
   - [ ] `CHANGELOG.md`: add a new `## X.Y.Z` section at the top, bilingual (EN bullet + indented ZH bullet) — see the existing `0.1.0` section for the house style.
   - Grep sanity check: `grep -rn "old_version" README.md README_zh.md CHANGELOG.md` must return nothing but legitimate history.
2. **Changelog scope rule / 变更日志范围规则:** only changes to `lib/` (the published runtime behaviour) earn a CHANGELOG entry. Pure documentation updates (`README*.md`) and `example/` / `server/` changes must NOT get a CHANGELOG entry — they do not change the released package's behaviour. The single exception is a pure version-bump commit.
3. Verify locally (see "Local verification" above), including `dart pub publish --dry-run` reporting **0 warnings**.
4. Merge the version bump to `main` (via PR, or directly if the maintainer permits).
5. Cut the release branch from `main`: `git checkout -b release/vX.Y.Z main`. The `release/vX.Y.Z` branch is the immutable source for that version; post-release hotfixes are applied here and re-tagged, never on `main`.
6. Tag to publish on the release branch: `git tag vX.Y.Z && git push origin release/vX.Y.Z && git push origin vX.Y.Z`. The `vX.Y.Z` **tag** (not a branch) triggers `pub-publish.yml` and publishes to pub.dev — this action is **irreversible**. Always use the `release/vX.Y.Z` prefix for the branch so it never collides with the `vX.Y.Z` tag refspec.
- `.pubignore` keeps `server/` (demo backend), `docs/`, `build/`, `.codebuddy/`, `AGENTS.md`, `CONTRIBUTING.md`, `TODO.md`, `wiki/` and `zero_auth_design.md` out of the published tarball. `example/` is intentionally published so consumers can browse a working integration. After touching `.pubignore`, re-check with `dart pub publish --dry-run` (must report **0 warnings**).

## New feature development checklist
- [ ] Confirm the change against `effective_dart` and the existing `lib/src/` structure (no `dart:io`, no Flutter imports in `lib/`).
- [ ] Expose any new public symbol through `lib/zero_auth.dart` **only**, with bilingual doc comments.
- [ ] Add or update unit tests under `test/` (`package:test`, `fake_async` for timers).
- [ ] Map every new failure mode to `AppException` / `AuthException`; never leak raw exceptions.
- [ ] Run `dart format .`, `dart analyze`, `flutter analyze`, `flutter test` locally.
- [ ] Use a typed branch (`feat/...`) and an English Conventional Commits PR title.
- [ ] Mirror user-facing changes in `README.md` **and** `README_zh.md`.
- [ ] For releases, follow the **Mandatory version-bump checklist** above, cut `release/vX.Y.Z` from `main`, and tag `vX.Y.Z` to publish.

## Known gaps (do not "fix" silently — raise with the maintainer)
- No branch protection ruleset is configured yet, so the CI required checks are advisory only.
- `README.md` / `README_zh.md` link to `CONTRIBUTING.md`, which now exists (added alongside the docs site).
- GitHub Pages docs site: a `.github/workflows/pages.yml` (official Actions deploy, bypassing Jekyll) exists and is pushed. Deployment still needs a one-time manual step — set **Settings → Pages → Source = GitHub Actions** — then trigger the workflow. Until then `pubspec.yaml`'s `documentation:` URL is not live.
