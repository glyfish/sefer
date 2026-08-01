# Conventions

Shared conventions across the gly.fish repos. See [overview.md](overview.md) for
who owns what.

## Documentation

- **Markdown links, never bare URLs** — `[text](url)`, not a raw `https://…`
  (bare URLs trip markdownlint MD034 and aren't clickable everywhere).
- **Headings blank-surrounded** — a blank line above and below every heading
  (MD022).
- **Fenced code blocks name their language** — ` ```python `, ` ```text `, etc.
- **Docs live in `sefer`** — cross-cutting docs at the top level / `planning/`;
  project-owned docs under `sefer/<repo>/`. A repo keeps only genuinely internal
  notes.
- **Cross-cutting plans carry a `Spans:` header + work-breakdown table** mapping
  tasks to repos, so a multi-repo effort is legible from any single repo.

## Code & workflow

- **navi is the shared library** — its package is named `lib`, installed editable
  (`-e ../navi`). `import lib …` resolves to `navi/lib`; keep the parent dir free
  of any stray `lib/`, which would shadow it.
- **Develop algorithms on simulated data first** (in `alef`); the matured model
  code then lands in `navi`, and `yada`'s pipeline applies it to *real* data.
  Developing against synthetic data guards against overfitting to the real series.
- **Regenerable catalogs are gitignored** — the metadata catalogs meida exports
  (e.g. `notebooks/*/data/`) are large, regenerable, and **not committed**; they
  are reproduced from code and persisted via system backups.
- **`_int` date mirrors** — vector stores can't range-compare date strings, so
  series records carry integer date mirrors (`YYYYMMDD`) beside the ISO dates for
  recency/coverage filters.
