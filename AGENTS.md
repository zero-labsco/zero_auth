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
  - `auth_state.dart` — sealed `AuthState`: `Unauthenticated` / `Authenticating` / `Restoring` / `Authenticated` / `Refreshing` / `LoggingOut` / `AuthError` (+ `AuthFail` payload). Seven subtypes: adding an eighth is a breaking change, so it waits for a major.
  - `auth_session.dart` — `AuthSession` (access/refresh token, expiry, user id, display name, raw claims) and `SessionHandle`.
  - `auth_strategy.dart` — `AuthStrategy` (the backend boundary), `Credentials`, `RegistrationInput`, `RefreshToken`.
  - `auth_manager_group.dart` — `AuthManagerGroup`: optional multi-account coordination. Owns one `AuthManager` per account (`forAccount` / `addAccount` / `switchTo` / `restoreAll` / `remove` / `logoutAll` / `disposeAll`); implements `AuthTokenSource` for the active account. `AuthManager` itself stays single-session on purpose.
  - `auth_capabilities.dart` — optional capability interfaces (`SupportsPasswordReset`, `SupportsPasswordChange`, `SupportsReauthentication`) detected via `AuthManager.supports<T>()`, so the four-method `AuthStrategy` contract never has to grow.
  - `token_store.dart` — `TokenStore` (the only persistence boundary) + `InMemoryTokenStore`.
  - `auth_token_source.dart` — `AuthTokenSource`: read-only token source for network layers (`accessToken`, plus `validAccessToken({leeway})` which renews first when a manager backs the source).
  - `exceptions.dart` — `AuthException` (auth-specific failures).
  - `error/` — the error kernel: `app_exception.dart` (`AppException`), `result.dart` (`Result<T>` = `Ok` / `Err`), `error.dart` (barrel).
- `test/` — unit tests written with `package:test` (NOT `flutter_test`); `fake_async` is used for timer-driven refresh behaviour; `fake_strategy.dart` is the shared test double.
- `example/` — Flutter example app (Android / iOS / Web / Windows). `main.dart` (state machine UI + backend toggle + register flow), `dio_interceptor.dart` (`AuthInterceptor`, `RefreshingAuthInterceptor` and `AuthRetryInterceptor` — ready-to-copy Dio integrations), `secure_token_store.dart` (`flutter_secure_storage` reference `TokenStore`) and `json_token_store.dart` (`JsonTokenStore`, a `dart:io` file-backed reference store). Both reference stores are consumer material and are **not** wired into `main.dart`, which uses `InMemoryTokenStore`; `json_token_store_test.dart` covers the file-backed one so sample code cannot rot silently. `widget_test.dart` renders the app unauthenticated and at three viewport sizes.
- `server/` — a layered `dart:io` demo backend used by the example (`dart run bin/server.dart`, port `8080`); endpoints `/login`, `/register`, `/refresh`, `/logout`, `/me`, `/health` (plus three `/debug/*` hooks the example drives). It issues real HMAC-SHA256 JWTs (via the `crypto` package) with refresh-token rotation, family revocation and replay detection, and logs every request with status and duration. Credentials are `user` / `user`; CORS enabled. Structure: `bin/server.dart` only bootstraps, everything else lives under `lib/` (`config`, `logging`, `http`, `auth`, `handlers`). It is repo-only and **not** shipped to pub.dev (excluded via `.pubignore`).
- `zero_auth_design.md` — repo-internal design notes (excluded from the published package).
- `website/` — the **Nextra + Next.js** documentation site (Animal-Crossing theme, copied from the `zero_inspector_kit` site). Source lives under `website/pages/*.md` and is the **only** hand-edited doc source; it builds to `website/out/`, which CI publishes to the `gh-pages` branch (see "Docs site" below). There is **no** generated `docs/` directory on `main`. `website/` is excluded from the pub package via `.pubignore`. The homepage is `website/pages/index.md`; version strings use the `__ZERO_AUTH_VERSION__` placeholder, injected from `pubspec.yaml` at build time.

### Hard constraints on `lib/`
- **Pure Dart only.** No `dart:io`, no `dart:html`/`package:web`, no platform channels, no Flutter widgets, no HTTP client. It must run unchanged on Flutter, server and CLI.
- **No hidden state.** The manager holds no UI, no backend and no native code; every side effect goes through `AuthStrategy` or `TokenStore`.
- **Errors never escape raw.** Every failure surfaced publicly is an `AppException` (typically `AuthException`); raw `Exception`s must not cross the public surface.
- **Single-flight refresh.** Concurrent `refresh()` callers must keep sharing one backend call (`_refreshCompleter`); do not "simplify" it into independent calls. Sharing is **epoch-scoped**: a call started before the session was replaced must not be joined (`_refreshCompleterEpoch`).
- **Every path that installs a session bumps the epoch.** `login` / `register` / `loginWith` / `updateSession` / `logout` / `dispose` call `_invalidateInFlight()` first, so a refresh already in flight can never overwrite the session they install (or write back a token minted from a rotated refresh token). Adding a new session-writing path means bumping the epoch too.
- **A transient renewal failure never destroys a session.** Whether in `refresh()` or `restore()`, only `refreshFailurePolicy(failure) == true` may clear the store; everything else keeps the session so a later attempt can retry.
- **Rethrow after emit.** `login()` / `register()` emit `AuthError` and then rethrow; callers (and the example app) must handle or deliberately swallow that rethrow.

## Dependencies and SDK constraints
- Dart SDK `^3.4.0` (sealed classes) is the **only** SDK constraint. The package is pure Dart and does **not** declare `flutter:` in `environment` — declaring it would mis-tag the package as "Flutter" on pub.dev and force pure-Dart (CLI/server) consumers to install the Flutter SDK for no reason. A Dart package is usable from Flutter projects automatically, so no Flutter constraint is needed.
- Runtime deps: `meta` only. Resist adding dependencies; the package must stay backend- and framework-agnostic.
- Dev deps: `test`, `fake_async` (refresh timers), `flutter_lints ^6` (required by `analysis_options.yaml`).
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
  - `docs.yml` — builds the Nextra site and publishes it to the `gh-pages` branch. See "Docs site" below.
    `docs.yml` — 构建 Nextra 站点并发布到 `gh-pages` 分支，详见下方"Docs site"。
  - `link-check.yml` — lychee scan of `README.md`, `README_zh.md`, `USAGE.md`, `CHANGELOG.md`, `website/pages/**`.
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

### Docs site (GitHub Pages — `gh-pages` branch)

- Source content lives in `website/` (Nextra) and is the only hand-edited
  documentation source. **Never commit a built site to `main`.**
- CI builds and publishes: pushes to `main` touching `website/**` or
  `pubspec.yaml` trigger `docs.yml`, which runs
  `node website/scripts/sync-docs.mjs --ci` and force-orphan-publishes
  `website/out/` to the root of the `gh-pages` branch as `github-actions[bot]`.
  A separate Pages branch is required because `main` is branch-protected — the
  bot cannot push there.
- GitHub Pages must be pointed at that branch **once** (Settings → Pages →
  Source: "Deploy from a branch", branch `gh-pages`, folder `/ (root)`).
  `gh-pages` is generated and force-pushed by CI, so never commit to it by hand.
- `website/out/` is git-ignored (see `website/.gitignore`); `main` holds no
  `docs/` directory anymore.
- To preview locally: `cd website && npm ci && npm run build` (output in
  `website/out/`), or `node website/scripts/sync-docs.mjs --ci`.
- The optional git pre-commit hook (`npm --prefix website run setup-hook`) only
  refreshes `website/out/` locally for previews. It never stages anything, and
  CI — not the hook — is the source of truth for the live site.

文档站（GitHub Pages — `gh-pages` 分支）:
- 源内容位于 `website/`（Nextra），是唯一需要手工编辑的文档源。**绝不要把构建产物提交到
  `main`。**
- 由 CI 构建并发布：推送到 `main` 且改动 `website/**` 或 `pubspec.yaml` 时会触发
  `docs.yml`，它执行 `node website/scripts/sync-docs.mjs --ci`，并以
  `github-actions[bot]` 身份把 `website/out/` 以 force-orphan 方式发布到 `gh-pages`
  分支根目录。`main` 受分支保护、bot 无法推送，因此必须使用独立的 Pages 分支。
- GitHub Pages 需**一次性**指向该分支（Settings → Pages → Source: "Deploy from a
  branch"，branch `gh-pages`，folder `/ (root)`）。`gh-pages` 由 CI 生成并强制推送，
  不要手工提交。
- `website/out/` 已被 git 忽略（见 `website/.gitignore`）；`main` 不再包含 `docs/`。
- 本地预览：`cd website && npm ci && npm run build`（产物在 `website/out/`），或
  `node website/scripts/sync-docs.mjs --ci`。
- 可选的 git pre-commit hook（`npm --prefix website run setup-hook`）仅在本地刷新
  `website/out/` 用于预览，不会暂存任何文件；线上站点以 CI 为准，而非 hook。

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
- `.pubignore` keeps `server/` (demo backend), `website/` (docs source), `build/`, `.codebuddy/`, `AGENTS.md`, `CONTRIBUTING.md`, `TODO.md`, `wiki/` and `zero_auth_design.md` out of the published tarball. `example/` is intentionally published so consumers can browse a working integration. After touching `.pubignore`, re-check with `dart pub publish --dry-run` (must report **0 warnings**).

## New feature development checklist
- [ ] Confirm the change against `effective_dart` and the existing `lib/src/` structure (no `dart:io`, no Flutter imports in `lib/`).
- [ ] Expose any new public symbol through `lib/zero_auth.dart` **only**, with bilingual doc comments.
- [ ] Add or update unit tests under `test/` (`package:test`, `fake_async` for timers).
- [ ] Map every new failure mode to `AppException` / `AuthException`; never leak raw exceptions.
- [ ] Run `dart format .`, `dart analyze`, `flutter analyze`, `flutter test` locally.
- [ ] Use a typed branch (`feat/...`) and an English Conventional Commits PR title.
- [ ] Mirror user-facing changes in `README.md` **and** `README_zh.md`.
- [ ] For user-facing changes, also update `website/pages/*.md` (the site is rebuilt and published by the `docs.yml` CI workflow once the change lands on `main`; do not generate or commit `docs/`).
- [ ] For releases, follow the **Mandatory version-bump checklist** above, cut `release/vX.Y.Z` from `main`, and tag `vX.Y.Z` to publish.

## Known gaps (do not "fix" silently — raise with the maintainer)
- No branch protection ruleset is configured yet, so the CI required checks are advisory only.
- `README.md` / `README_zh.md` link to `CONTRIBUTING.md`, which now exists (added alongside the docs site).
- GitHub Pages docs site: `.github/workflows/docs.yml` builds the site and publishes it to the `gh-pages` branch. Deployment still needs a one-time manual repo setting — set **Settings → Pages → Source = "Deploy from a branch"**, branch `gh-pages`, folder `/ (root)`. Until then `pubspec.yaml`'s `documentation:` URL is not live.
