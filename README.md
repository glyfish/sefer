# sefer

Shared documentation for the **gly.fish** project — the single source of truth
across `meida`, `yada`, `alef`, and `navi`. Start with
[overview.md](overview.md).

## Contents

- **[overview.md](overview.md)** — system map: the four repos, their roles, and
  how work flows between them. This is what each repo's `CLAUDE.md` imports.
- **[conventions.md](conventions.md)** — shared doc, code, and workflow conventions.
- **[known-issues.md](known-issues.md)** — running log of deferred problems / rough edges.
- **planning/** — cross-cutting designs that span repos:
  [structural demographic theory](planning/structural-demographic-theory.md),
  [pairs/triples screening](planning/llm-pairs-triples-screening.md), and the
  [data-sources backlog](planning/data-sources-backlog.md).
- **meida/ · yada/ · alef/ · navi/** — each repo's own docs (architecture and
  reference material).

## Layout

```text
sefer/
├── overview.md          system map (imported into every repo's CLAUDE.md)
├── conventions.md       shared conventions
├── known-issues.md      running log of deferred problems
├── planning/            cross-cutting designs (Spans: multiple repos)
├── meida/               architecture, api/ (data-source references)
├── yada/                architecture, data-store-*
├── alef/                architecture
└── navi/                (docs as they arrive)
```

## How it's consumed

- **Claude Code (VSCode)** — each repo commits a `CLAUDE.md` that imports
  `@../sefer/overview.md` (+ `@../sefer/conventions.md`) plus its own specifics.
  Because it's committed, `git clone` brings the wiring along — nothing to run per
  machine. Only `overview.md`/`conventions.md` auto-load; the rest is read on
  demand. (If a repo is cloned without `sefer` alongside, the import just no-ops.)
- **Claude Desktop** — point its Filesystem connector (or a Project) at this repo;
  it reads the same markdown (Desktop ignores `CLAUDE.md` and `@` imports).
