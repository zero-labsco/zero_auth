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

The Pages site is served from the **pre-built** `docs/` folder; it is regenerated
from `website/out/` by a git pre-commit hook. The hook must be installed once per
clone, otherwise edits under `website/` never reach GitHub Pages.

文档站由**预先构建**的 `docs/` 目录提供，它由 git pre-commit hook 从 `website/out/`
重新生成。每个克隆必须安装一次该 hook，否则你在 `website/` 下的改动永远不会上线。

```powershell
npm --prefix website run setup-hook
```

If you changed `website/**` but `git status` shows no `docs/` changes, the hook is
missing — reinstall it and run `node website/scripts/sync-docs.mjs --force` once.

若你改了 `website/**` 而 `git status` 中没有 `docs/` 变化，说明 hook 未安装——重装它，
再手动执行一次 `node website/scripts/sync-docs.mjs --force`。

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
