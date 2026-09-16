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
  - `auth_manager.dart` — `AuthManager`: the orchestrator. Owns the state machine, `restore()` / `login()` / `register()` / `logout()` / `refresh()` / `dispose()`, plus `current`, `state` (replay-last broadcast stream), `currentSession` and `accessToken` (it *is* an `AuthTokenSource`).
  - `auth_state.dart` — sealed `AuthState`: `Unauthenticated` / `Authenticating` / `Authenticated` / `AuthError` (+ `AuthFail` payload).
  - `auth_session.dart` — `AuthSession` (access/refresh token, expiry, user id, display name, raw claims) and `SessionHandle`.
  - `auth_strategy.dart` — `AuthStrategy` (the backend boundary), `Credentials`, `RegistrationInput`, `RefreshToken`.
  - `token_store.dart` — `TokenStore` (the only persistence boundary) + `InMemoryTokenStore`.
  - `auth_token_source.dart` — `AuthTokenSource`: read-only token source for network layers.
  - `exceptions.dart` — `AuthException` (auth-specific failures).
  - `error/` — the error kernel: `app_exception.dart` (`AppException`), `result.dart` (`Result<T>` = `Ok` / `Err`), `error.dart` (barrel).
- `test/` — unit tests written with `package:test` (NOT `flutter_test`); `fake_async` is used for timer-driven refresh behaviour; `fake_strategy.dart` is the shared test double.
- `example/` — Flutter example app (Android / iOS / Web / Windows). `main.dart` (state machine UI + backend toggle), `dio_interceptor.dart` (`AuthInterceptor`, a ready-to-copy Dio integration), `secure_token_store.dart` (`flutter_secure_storage` reference `TokenStore`; not wired into `main.dart`, it is reference material for consumers).
- `server/` — a zero-dependency `dart:io` demo backend used by the example (`dart run bin/server.dart`, port `8080`); endpoints `/login`, `/refresh`, `/logout`, `/me`; any username, password must be `b`; CORS enabled.
- `zero_auth_design.md` — repo-internal design notes (excluded from the published package).

### Hard constraints on `lib/`
- **Pure Dart only.** No `dart:io`, no `dart:html`/`package:web`, no platform channels, no Flutter widgets, no HTTP client. It must run unchanged on Flutter, server and CLI.
- **No hidden state.** The manager holds no UI, no backend and no native code; every side effect goes through `AuthStrategy` or `TokenStore`.
- **Errors never escape raw.** Every failure surfaced publicly is an `AppException` (typically `AuthException`); raw `Exception`s must not cross the public surface.
- **Single-flight refresh.** Concurrent `refresh()` callers must keep sharing one backend call (`_refreshCompleter`); do not "simplify" it into independent calls.
- **Rethrow after emit.** `login()` / `register()` emit `AuthError` and then rethrow; callers (and the example app) must handle or deliberately swallow that rethrow.

## Dependencies and SDK constraints
- Dart SDK `^3.4.0` (sealed classes); Flutter `>=3.0.0` is a **constraint only** — the runtime does not depend on Flutter.
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
- Branch from `main` with a typed prefix: `feat/`, `fix/`, `docs/`, `ci/`, `chore/`, etc.
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
- **Not configured yet** — this repo has no `.github/workflows/`. When adding CI, mirror the sibling project `zero_inspector_kit`: `ci.yml` (`flutter analyze` + `flutter test` + pana score check), `pr-title-check.yml` (`amannn/action-semantic-pull-request@v6`, allowed types `feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert`), `dart-format-fix.yml`, `link-check.yml` (README/CHANGELOG link scan), and `pub-publish.yml` (triggered by the `vX.Y.Z` **tag**, publishing via `k-paxian/dart-package-publisher@v1.6` with the `PUB_CREDENTIALS_JSON` secret; do NOT pass OIDC fields).
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
- Any username works; the password must be `b`. A wrong password shows the `AuthError` path; `Call /me` proves the bearer header reaches the backend.
- On an Android emulator use `http://10.0.2.2:8080` (`_baseUrl` in `example/lib/main.dart`).

### Release and publish
1. Bump `version` in `pubspec.yaml` (semver; major bump for breaking public API).
   **Mandatory version-bump checklist — every item MUST be updated to the new `X.Y.Z` (old string fully removed):**
   - [ ] `pubspec.yaml` → `version: X.Y.Z`
   - [ ] `README.md`: the `^X.Y.Z` dependency constraint, the `` `X.Y.Z` `` placeholder in the GitHub install snippet, the `ref: vX.Y.Z` git ref, and the "🔔 Upgrade recommended" callout (summarize **only** what the current release changed; never reference previous versions).
   - [ ] `README_zh.md`: the same four spots (`^X.Y.Z`, `` `X.Y.Z` ``, `ref: vX.Y.Z`, "🔔 推荐升级：" callout).
   - [ ] `CHANGELOG.md`: add a new `## X.Y.Z` section at the top, bilingual (EN bullet + indented ZH bullet) — see the existing `0.1.0` section for the house style.
   - Grep sanity check: `grep -rn "old_version" README.md README_zh.md CHANGELOG.md` must return nothing but legitimate history.
2. **Changelog scope rule / 变更日志范围规则:** only changes to `lib/` (the published runtime behaviour) earn a CHANGELOG entry. Pure documentation updates (`README*.md`) and `example/` / `server/` changes must NOT get a CHANGELOG entry — they do not change the released package's behaviour. The single exception is a pure version-bump commit.
3. Verify locally (see "Local verification" above), including `dart pub publish --dry-run` reporting **0 warnings**.
4. Commit on a branch, open a PR, merge to `main`.
5. Tag to publish: `git tag vX.Y.Z <commit> && git push origin vX.Y.Z`. Never create a **branch** named `vX.Y.Z` — it collides with the tag refspec.
- `.pubignore` already keeps `docs/`, `build/`, `.codebuddy/`, `AGENTS.md`, `CONTRIBUTING.md`, `TODO.md`, `wiki/` and `zero_auth_design.md` out of the published tarball. If the demo backend should not ship to pub.dev either, add `server/` there before the first publish.

## New feature development checklist
- [ ] Confirm the change against `effective_dart` and the existing `lib/src/` structure (no `dart:io`, no Flutter imports in `lib/`).
- [ ] Expose any new public symbol through `lib/zero_auth.dart` **only**, with bilingual doc comments.
- [ ] Add or update unit tests under `test/` (`package:test`, `fake_async` for timers).
- [ ] Map every new failure mode to `AppException` / `AuthException`; never leak raw exceptions.
- [ ] Run `dart format .`, `dart analyze`, `flutter analyze`, `flutter test` locally.
- [ ] Use a typed branch (`feat/...`) and an English Conventional Commits PR title.
- [ ] Mirror user-facing changes in `README.md` **and** `README_zh.md`.
- [ ] For releases, follow the **Mandatory version-bump checklist** above and tag `vX.Y.Z`.

## Known gaps (do not "fix" silently — raise with the maintainer)
- No `.github/workflows/` yet; no automated CI, PR-title check or pub publish.
- `README.md` / `README_zh.md` link to `CONTRIBUTING.md`, which does not exist yet.
- No GitHub Pages docs site yet, although `pubspec.yaml` declares `documentation: https://zero-foundation.github.io/zero_auth/`.
