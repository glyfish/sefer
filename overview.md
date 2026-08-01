# gly.fish — System Overview

The gly.fish project is four repos under `~/Develop/gly.fish/`, plus this shared
docs repo (`sefer`). This file is the orientation map — the deeper docs live
alongside it (see [README](README.md)).

## The repos

| Repo | Role |
| --- | --- |
| **navi** | Shared library (the importable package is named `lib`; consumers install it via `-e ../navi`). Owns the data **clients** and the **model code** — reusable algorithm implementations (indicators, strategies, estimators, stats) plus plot/db utils. |
| **meida** | Data-access **API** — an MCP server exposing navi's clients as tools and building the metadata catalogs (FRED, Tiingo, BLS, BIS). |
| **alef** | Model **development & testing** — where algorithms are prototyped and validated, **on simulated data first**, against navi's model primitives. |
| **yada** | The **analysis pipeline** — applies the models to *real* data, plus the data stores (Postgres, vector), plotting, reporting, and the agentic frontend. |

(`website`, the public site, is a separate legacy repo — not covered here yet.)

## How work flows

```text
        raw data  (meida / navi clients)
                        │
    simulated data ─▶  alef   develop & test the algorithm
                        │  matures into
                        ▼
                      navi    the model code — reusable
                        │  applied to real data by
                        ▼
                      yada    analysis pipeline → results, plots, reports
```

**alef is the lab, navi is where the code lives, yada is where it runs.** Data
collection is meida/navi.

## Where things are documented

- **Cross-cutting plans** — `planning/`: designs that span repos (structural
  demographic theory, pairs/triples screening, the data-sources backlog). Each
  carries a `Spans:` header + a per-repo work breakdown.
- **Per-repo docs** — `meida/`, `yada/`, `alef/`, `navi/`: each repo's own
  architecture and reference material (e.g. `meida/api/` = data-source references).
- **Conventions** — [conventions.md](conventions.md).
