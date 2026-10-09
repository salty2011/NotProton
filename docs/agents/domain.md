# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root, or
- **`CONTEXT-MAP.md`** at the repo root if it exists: it points at one `CONTEXT.md` per context. Read each one relevant to the topic.
- **`docs/adr/`**: read ADRs that touch the area you're about to work in. In multi-context repos, also check `src/<context>/docs/adr/` for context-scoped decisions.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## Layout and language

This repository uses one root `CONTEXT.md` glossary and `docs/adr/` for durable decisions. Create them only when a term or meaningful trade-off has been resolved. Use canonical glossary terms in specs, tickets and implementation. Graft provides implementation context; the glossary holds domain meanings, not source structure.

## ADR conflicts

Read decisions relevant to the change. Surface any contradiction explicitly rather than silently overriding an accepted decision.
