# Repository Guidelines

## Project Structure & Module Organization

- `app/Sources/NotProtonApp/`: SwiftUI application; installation and runtime logic in `Model/`, UI in `Views/`, resources in `Resources/`.
- `dylib/`: C Steam hooks, compatibility features, signature resolution, and the embedded `feats/compat_run.sh` launcher.
- `lsteamclient/`, `steam-shim/`, `bridge/`, and `ntdll-patch/`: Steam bridging and Wine loader integration.
- `runtime/`: experimental free Wine build recipe and pinned inputs; `runtime-tests/`: Windows acceptance probes.
- Tests live in `app/Tests/NotProtonAppTests/`, `dylib/tests/`, and `overlay-shim/tests/`. Generated artifacts go to `out/`; game evidence belongs in `docs/research/game-compatibility-matrix.md`.

## Build, Test, and Development Commands

Use macOS 26+, Swift 6.2+, and the Xcode 27 toolchain for the full app build. Follow `.github/workflows/app.yml` for pinned Dobby setup and cross-compiler prerequisites.

- `make dobby bridge app`: build dependencies, Steam bridges, and the signed `out/NotProton.app` bundle.
- `open out/NotProton.app`: run the local build; installing into Steam is a separate action.
- `make app-tests`: run Swift tests serially.
- `make runcheck scriptcheck`: ShellCheck and shell syntax validation; CI pins ShellCheck 0.11.0.
- `make webpatch-fixtures panel-behavior launch-shell`: check Steam UI patches and launch handling.
- `make callscheck compatcheck compatsvc-check`: run targeted native checks.

For engine changes, read `runtime/README.md` and `runtime-tests/README.md` before building or probing Wine.

## Coding Style & Naming Conventions

Match surrounding code: four-space Swift/C indentation, two-space shell indentation, and tabs in Make recipes. Swift uses `UpperCamelCase` types and `lowerCamelCase` members; C uses `snake_case` functions. Keep SwiftUI presentation separate from model logic. Edit launcher source rather than generated headers. Preserve verified binary hashes and engine/bridge ABI pairing. No repository-wide formatter is configured.

## Testing Guidelines

Swift tests use Swift Testing (`@Suite`, descriptive `@Test`, `#expect`) in `*Tests.swift` files. Native checks use C fixtures, shell/Python scripts, and Node panel tests. Cover changed behavior and failure paths; no percentage coverage threshold is configured. Report skipped checks explicitly. Test experimental engines with disposable or backed-up prefixes, and distinguish launch, login, gameplay, media, and session stability.

## Commit & Pull Request Guidelines

Use concise imperative subjects, such as `Add…`, `Fix…`, or `Preserve…`; history does not require Conventional Commit prefixes. Work on `codex/` branches and push to the fork's `origin`; reserve upstream changes for a reviewed PR. Describe the problem, resulting behavior, linked issues, validation, and remaining limits. Include screenshots for UI changes. Keep private game logs, generated builds, and unrelated local preferences out of commits; retain source attribution and licenses.

<!-- graft:start -->
## Graft — repo context graph

This repo is indexed in `graft/`: small linked markdown nodes that explain each
system and carry exact file:line spans, kept in sync with the code through git.

For ANY task here — understanding how something works, finding where code lives,
or scoping a change — get context from the graph before grepping or opening
source files. Re-ask freely (it's cheap) and reuse literal identifiers you
already have (symbol, error string, file name) as the query. New to this repo?
Run `graft map` first — a token-budgeted orientation (dir clusters, hubs,
hotspots), no LLM, no key.

- Run `graft ask "<your question>" --source` → ranked nodes with the relevant
  code spans inlined (each hit's ≤8-line crux by default; `--full` for whole
  definitions when the crux isn't enough). Match the tool to the task shape:
  for understanding or editing, the top node IS the answer — cite its
  `covers:` file:line spans and edit straight from `--source`. For
  exhaustive tasks ("every occurrence / every caller of this pattern"), ranked
  results are top-N, not complete — run `graft grep "<literal>"` instead
  (exhaustive over indexed files, grouped by enclosing symbol), falling back
  to raw `grep -rn` only for unindexed files.
- `graft skeleton <file>` → every definition's signature + span, ~10× cheaper
  than reading the file; use it to skim an API surface.
- `graft callers <symbol>` gives precomputed, exact edges — who calls this.
  Add `--direction out` for what it calls, or `--depth N` to walk
  transitively for the full blast radius. For structural questions, skip
  ranking and use this directly.
- Or browse: `graft/INDEX.md` lists every node; follow the links.
- Monorepos and folders of multiple repos rank fairly across sub-projects —
  hits carry `[scope/]` labels naming which one they're from. Narrow with
  `graft ask "<task>" --in <scope>/` once you know where you're working.

If a returned span is truncated ("+N more lines"), open the file at that exact
range before finalizing. Only open source files when a node genuinely lacks a
needed detail, and then at the exact file:line the node points to — never
re-read whole files.

After big code changes, refresh the graph with `graft build` (deterministic,
no API key, $0).
<!-- graft:end -->

## Agent skills

### Issue tracker
Specs and tickets use local Markdown under `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Triage labels
Use the five default triage roles. See `docs/agents/triage-labels.md`.

### Domain docs
Use a single root glossary and relevant ADRs when present. See `docs/agents/domain.md`.
