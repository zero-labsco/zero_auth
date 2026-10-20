# Contributing to Zero Auth

Thanks for your interest in improving `zero_auth`! This guide keeps the package
consistent with the rest of the `zero_*` series. For deeper context, read
[`AGENTS.md`](AGENTS.md) (the single source of truth for conventions).

## Scope

`zero_auth` is a **pure-Dart, headless auth state machine & session lifecycle**
library. It ships **no** native code, backend SDK, HTTP client, UI, or
state-management framework. Consumers bring their own backend (`AuthStrategy`)
and persistence (`TokenStore`).

Hard rules for `lib/`:

- **Pure Dart only.** No `dart:io`, no `dart:html`/`package:web`, no platform
  channels, no Flutter widgets, no HTTP client. It must run unchanged on
  Flutter, server and CLI.
- **No hidden state.** Every side effect goes through `AuthStrategy` or
  `TokenStore`.
- **Errors never escape raw.** Every failure surfaced publicly is an
  `AppException` (typically `AuthException`); raw `Exception`s must not cross
  the public surface.
- **Single-flight refresh.** Keep the shared `_refreshCompleter`; do not
  "simplify" concurrent `refresh()` into independent calls.

## Local setup

```powershell
cd d:\FlutterProgram\zero_auth
dart pub get
dart analyze          # must report no issues
dart test             # runs the unit tests (package:test, fake_async)
```

For the example app and demo backend:

```powershell
cd example && flutter analyze && flutter test
cd ..\server && dart analyze
```

## Docs site / 文档站

The docs site is built by **CI**, not committed to `main`. Pushes to `main`
touching `website/**` or `pubspec.yaml` trigger `docs.yml`, which builds
`website/out/` and publishes it to the `gh-pages` branch. GitHub Pages serves
that branch (one-time repo setting: Settings → Pages → Source "Deploy from a
branch", branch `gh-pages`, folder `/ (root)`).

文档站由 **CI** 构建，不会提交到 `main`。推送到 `main` 且改动 `website/**` 或
`pubspec.yaml` 时会触发 `docs.yml`：它构建 `website/out/` 并发布到 `gh-pages` 分支。
GitHub Pages 提供该分支（一次性仓库设置：Settings → Pages → Source "Deploy from a
branch"，branch `gh-pages`，folder `/ (root)`）。

Only `website/pages/*.md` is hand-edited — never build or commit a `docs/`
directory.

只有 `website/pages/*.md` 需要手工编辑——不要构建或提交 `docs/` 目录。

```powershell
# Optional: local preview (writes website/out/, which is git-ignored).
# 可选：本地预览（生成 website/out/，已被 git 忽略）。
cd website && npm ci && npm run build

# Same build, with the pubspec version injected into the pages.
# 同样的构建，并把 pubspec 版本注入页面。
node website/scripts/sync-docs.mjs --ci
```

## Branching & pull requests

- Branch from `main` with a typed prefix: `feat/`, `fix/`, `docs/`, `ci/`,
  `chore/`, `release/`, etc. (`release/vX.Y.Z` is the branch for a shipped
  version — see "Releasing".)
- **Never push directly to `main`.**
- PR titles are **English-only** and MUST follow
  [Conventional Commits](https://www.conventionalcommits.org/):
  `feat:`, `fix:`, `docs:`, `style:`, `refactor:`, `perf:`, `test:`,
  `build:`, `ci:`, `chore:`, `revert:`.
- Follow the bilingual PR body template in `AGENTS.md` and sign off with
  **Zero Buddy**.

## Code conventions

- Follow `effective_dart`; enforced by `dart analyze` / `flutter analyze`.
- **Doc comments in `lib/` are bilingual, EN-primary / ZH-secondary** (English
  paragraph first, then the Chinese one).
- `example/` and `server/` are **English-only**.
- `README.md` (EN) and `README_zh.md` (ZH) are parallel documents; any content
  change to one must be mirrored in the other.
- Do not break the public API without a major version bump; add new public
  symbols to `lib/zero_auth.dart` only.

## Tests

- Use `package:test` (NOT `flutter_test`); use `fake_async` for timer-driven
  refresh behaviour.
- Shared test doubles live in `test/fake_strategy.dart`.
- Every new public behaviour needs a unit test.

## Releasing

Bumping the version is the maintainer's call (see `AGENTS.md` for the mandatory
version-bump checklist). In short: update `version` in `pubspec.yaml`, the four
spots in both `README.md` and `README_zh.md`, and add a bilingual `## X.Y.Z`
section at the top of `CHANGELOG.md` (only `lib/` behaviour changes earn a
changelog entry).

Release flow:

1. Merge the version bump to `main`.
2. Cut the release branch: `git checkout -b release/vX.Y.Z main`.
3. Tag and publish: `git tag vX.Y.Z && git push origin release/vX.Y.Z && git push origin vX.Y.Z`.
   The `vX.Y.Z` **tag** triggers the publish workflow and publishes to pub.dev —
   this is irreversible, so only tag when you intend to ship.

> Note: the branch is `release/vX.Y.Z`, **not** `vX.Y.Z` — a branch named
> `vX.Y.Z` collides with the tag refspec.
