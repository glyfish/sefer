# sefer

Shared documentation for the **gly.fish** project — the single source of truth
across `meida`, `yada`, `alef`, and `navi`. Start with
[overview.md](overview.md).

## Contents

- **[overview.md](overview.md)** — system map: the four repos, their roles, and
  how work flows between them. This is what each repo's `CLAUDE.md` imports.
- **[conventions.md](conventions.md)** — shared doc, code, and workflow conventions.
- **planning/** — cross-cutting designs that span repos (structural demographic
  theory, pairs/triples screening, the data-sources backlog).
- **meida/ · yada/ · alef/ · navi/** — each repo's own docs (architecture and
  reference material).

## Layout

```text
sefer/
├── overview.md          system map (imported into every repo's CLAUDE.md)
├── conventions.md       shared conventions
├── setup.sh             wires the parent CLAUDE.md import stub (run once per machine)
├── planning/            cross-cutting designs (Spans: multiple repos)
├── meida/               architecture, api/ (data-source references)
├── yada/                architecture, data-store-*
├── alef/                architecture
└── navi/                (docs as they arrive)
```

## How it's consumed

- **Claude Code (VSCode)** — the parent `~/Develop/gly.fish/CLAUDE.md` is one line,
  `@sefer/overview.md`, which every sibling repo inherits (Claude Code reads
  `CLAUDE.md` up the directory tree). Only `overview.md` (+ `conventions.md`)
  auto-load; the rest is read on demand. Run `./setup.sh` once per machine to
  write that stub.
- **Claude Desktop** — point its Filesystem connector (or a Project) at this repo;
  it reads the same markdown (Desktop ignores `CLAUDE.md` and `@` imports).

> `planning/` and the per-repo folders are populated by migrating each repo's
> `documents/` into here — that migration is the next step.
