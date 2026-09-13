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
- **navi owns the shared dependencies** — third-party packages that `lib/` imports
  are declared in `navi/pyproject.toml`, never repeated in a consumer's
  `requirements.in`; consumers inherit them through `-e ../navi` (plus
  `-e ../navi[mcp]` for the optional MCP client). A consumer lists only its *own*
  tooling, or a deliberate constraint on a navi-provided package with a comment
  saying why (e.g. yada's `pandas<3`). Hand-listing the stack per repo is what let
  alef, yada and meida drift onto different statsmodels and pandas versions. The
  `navi-3.14.7` env is deliberately minimal so an undeclared import fails there
  rather than in whoever installs navi next — `navi/scripts/check_imports.py`
  checks it, and nothing else should be installed into it.
- **navi's areas have owners** — `lib/data`, `lib/models`, `lib/plots` and
  `lib/trading` belong to **alef**. navi carries no tests of its own: they live
  with the owner (`alef/tests`). `yada` consumes the library and owns none of it.
- **The vendor clients live in meida, not navi** — `meida/clients/` holds the
  FRED, BLS, BIS, Socrata, Tiingo and WONDER clients and their pydantic models.
  They were in `navi/lib/clients` while navi was assumed to be the shared home
  for everything; in practice meida is the only consumer (yada and alef import
  none of it), and keeping them in a library shipped to three repos meant a
  change made for meida's interface landed in yada's and alef's dependency.
  They still import `lib.env` and `lib.logger`, which are genuinely shared.
- **Develop algorithms on simulated data first** (in `alef`); the matured model
  code then lands in `navi`, and `yada`'s pipeline applies it to *real* data.
  Developing against synthetic data guards against overfitting to the real series.
- **Regenerable catalogs are gitignored** — the metadata catalogs meida exports
  (e.g. `notebooks/*/data/`) are large, regenerable, and **not committed**; they
  are reproduced from code and persisted via system backups. This holds without
  exception: nothing under `notebooks/*/data/` is tracked.
- **A provider that revises in place gets a diff at load time, not in git** —
  NCHS reclassifies death certificates after publication, so re-running a
  pipeline changes numbers already loaded. `db_import/load_timeseries.py`
  compares each incoming series against what is stored and reports what moved,
  which is where that shows up. Committing the build artifact was tried and
  reverted (meida `a1aa12d`): git only surfaces the change if someone re-pulls
  *and* reads the diff, whereas the load reports it every time.
- **A slow or throttled download gets a notebook, not a script** — see
  [meida/architecture.md §9](meida/architecture.md). The saved cell output is
  the record that an expensive pull succeeded, and a notebook makes re-running
  one a deliberate act.
- **`_int` date mirrors** — vector stores can't range-compare date strings, so
  series records carry integer date mirrors (`YYYYMMDD`) beside the ISO dates for
  recency/coverage filters.
