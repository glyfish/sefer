# FRED Metadata Data Store

A catalog of **FRED series metadata** — one record per series, describing what each series
measures, how often it is released, and what period it covers. It is a discovery index, not a
data store: observations are fetched separately and land in the PostgreSQL time-series cache.

**There are currently two of them, and both are live.** A PostgreSQL catalogue, collected
directly from the FRED API, is complete and is the one to build on. A ChromaDB collection,
indexed from a superseded YAML export, covers 123,119 series against Postgres's 846,628 and is
partly wrong, but is still the only store any agent actually queries. This document describes both, and what the cutover between them
requires.

See [architecture.md](architecture.md) for how this fits the wider system, and
[../planning/yada-todo.md](../planning/yada-todo.md) §5 for the cutover's remaining work.

---

## Why there are two

The Chroma store was built from YAML files exported by `clients/bin/fred.py`. That export was
found to be wrong in four ways at once, none of which produced a symptom:

- **Truncated at 1,000 rows per category.** FRED's `category/series` endpoint pages at a maximum
  of 1,000 and the export treated that ceiling as a count. 145,192 series-category memberships
  were silently absent.
- **Mis-rooted tree.** Parts of the hierarchy hung from the wrong parent.
- **`Production & Business Activity` missing entirely** — a top-level category with 99,452
  memberships beneath it.
- **881 of 1,029 categories present**, with no way to tell a category the export never reached
  from one that genuinely has no children.

The common cause is that a file hand-off carries no row count and no transaction. One page of
nine looks exactly like a complete category, so the export reported success. That is the defect
the Postgres catalogue is designed around, and it is why its central feature is a
reconciliation rather than a schema.

---

## Part 1 — The PostgreSQL catalogue (primary)

### Identity

| | |
| --- | --- |
| Engine | PostgreSQL 18 |
| Database | `yada_dev` (dev) / `yada` (prod), selected by `YADA_ENV` |
| Migrations | `0005_fred_series_catalogue` … `0009_resumable_walk` |
| Upstream source | the FRED API directly — no intermediate files |
| Collector | `apps/agentic/db/fred_discovery.py` |
| Entry point | `clients/bin/fred_metadata.py` |
| Notebook | `notebooks/data/fred_meta_data.ipynb` |
| Series | 846,628 |
| Categories | 5,201 |
| Memberships | 1,002,244 |

### Tables

| Table | Rows | Holds |
| --- | --- | --- |
| `fred_series` | 846,628 | One row per series: title, units, frequency, seasonal adjustment, observation bounds, `last_updated`, `popularity`, `notes`, plus a generated `title_tsv` for full-text search. |
| `fred_category` | 5,201 | `category_id`, `category_name`, `parent_id` as FRED supplies it, a derived `category_path`, `excluded_reason`, and `walked_at`. |
| `fred_series_category` | 1,002,244 | The membership edge. A series can sit in several categories, which is why memberships exceed series by ~18%. |
| `fred_category_scan` | 5,201 | **The reconciliation.** One row per category: `api_series_count`, `fetched_series_count`, `pages`, `page_limit`, `status`, `error`, timings. |
| `fred_frequency_class` | 8 | The per-class currency rule, rebuilt from the data. |
| `fred_subcategory` | 77 | The derived browsable tree. Not yet populated — see below. |
| `fred_series_subcategory` | 839 | Series-to-leaf assignment for the derived tree. |
| `fred_subcategory_build` | 2 | Per-category build outcome, LLM call count and cost. |

Only `fred_category.parent_id` is stored; `category_path` is derived from it by a recursive CTE
in `rebuild_paths`. Storing both independently is what let the old export's tree be mis-rooted
without contradiction.

### The reconciliation contract

Every fetch records **two** numbers: what FRED said the category contains, and what we actually
wrote.

```python
requested = api_count if page_limit is None else min(api_count, page_limit * PAGE)
status = "ok" if len(fetched) >= requested else "incomplete"
```

`status = 'ok'` is only reachable when those agree. The consequence is that incompleteness
cannot be silent — it is a row you can query:

```sql
SELECT count(*) FROM fred_category_scan WHERE status <> 'ok';
```

A deliberate limit is recorded separately from a fault. `page_limit` stores the cap that was
applied, so `api_series_count > fetched_series_count` means a **choice** when `page_limit` is
set and a **fault** when it is not. The whole-catalogue check is that the gap between the two
sums equals the deliberate deferral exactly:

| | |
| --- | --- |
| `sum(api_series_count)` | 1,052,462 |
| `sum(fetched_series_count)` | 1,000,709 |
| difference | 51,753 |
| `deferred_by_cap` | 51,753 — identical, so nothing is unaccounted for |

### The walk, and why it is resumable

A category is **found** when its parent names it as a child, and **visited** when we ask it for
its own children. Those are different events, and recording only the first is what made the
original export's gaps indistinguishable from genuine leaves.

`walked_at` records the second. A resuming walk skips categories that have it set and queues
their children from the database, so a run that dies continues past the previous frontier
rather than restarting at it. In the full regional collection that skipped 1,058 categories
without a request.

**The semantics are a caller's choice, not a default.** Skipping a visited category means not
noticing children FRED has *added*. That is right for resuming an interrupted run and wrong for
a refresh, so `walk_categories` takes `revisit` as an argument — exposed as `--revisit`.
Defaulting to skip would make every later run a silent no-op; defaulting to revisit would make
resume pointless.

### Collecting it

```bash
python clients/bin/fred_metadata.py status     # what is held, what is outstanding
python clients/bin/fred_metadata.py walk       # the category tree, resuming
python clients/bin/fred_metadata.py fetch      # series for every category not yet `ok`
python clients/bin/fred_metadata.py all        # both — a full collection run
python clients/bin/fred_metadata.py all --dry-run   # prove a second run is a no-op
python clients/bin/fred_metadata.py fetch --limit 5 # bound a run while testing
```

The client paces itself at `MIN_INTERVAL = 0.6s`, under FRED's documented 120 requests/minute.
That number is empirical, not cautious: a children sweep at ~480/min returned 429s until
retries were exhausted. `PAGE = 1000` is FRED's maximum for `category/series`; `MAX_DEPTH = 12`
is a cycle guard, not a FRED limit.

**Every subcommand is idempotent**, which is what makes the notebook safe to re-run:

- `walk` skips categories whose `walked_at` is set.
- `fetch` skips categories whose scan is already `ok`.
- series are upserted; memberships are inserted on-conflict-do-nothing.
- `rebuild_paths` and `mark_exclusions` update only rows whose value actually differs.

`mark_exclusions` reconciles in **both** directions. Emptying the exclusion table has to
*clear* the stored marks, or a branch that is wanted again stays invisible to
`pending_categories` and the fetch skips it silently — the same class of defect as the
truncated export.

### What a full run costs

Measured on 2026-11-07, collecting the regional subtree that had been deferred:

| | |
| --- | --- |
| Walk | 5,202 categories visited, 4,180 written, 1,058 skipped, 4,145 requests |
| Fetch | 4,142 categories, 4,197 requests, 44.7 minutes |
| Rate | 94 requests/minute sustained |
| Failures | 0 incomplete, 0 failed, 0 unreachable |

### Coverage

The denominator is measured independently of the category walk. Each series belongs to one
release, so enumerating every release's series list gives a total the walk cannot influence.
Measured 2026-11-07 over all 337 releases, 1,132 requests:

| | |
| --- | --- |
| FRED total (union over 337 releases) | **853,320** |
| sum of per-release counts | 853,320 — identical, and **0 series appear in 2+ releases** |
| held, and listed by a release | 845,628 — **99.1%** |
| held, but listed by no release | **1,000** (see below) |
| held, total | 846,628 |
| missing | 7,692, of which 7,690 are under the capped country categories |
| with `notes` | 774,931 (91.5%) |
| `currently_relevant` | 585,251 (69.1%) |

The union and the sum agreeing exactly is worth stating, because it is the one thing that makes
the arithmetic above trustworthy: it confirms one-release-per-series as a measured property
rather than a documented claim, so the denominator has no double counting to correct for.

**Almost all of the shortfall is one deliberate decision.** `International Data > Countries` and
its 245 children are capped at one page each, because country data is better sourced from BIS,
whose SDMX dimensions are native facets rather than strings to be parsed out of a title. 38
capped categories carry the shortfall; the 7,690 series behind them were enumerated by id, not
inferred by subtraction. The cap is recorded per category, so lifting it is a configuration
change, not a re-derivation.

**The 1,000 held series that no release lists are diagnosed**, and the roundness of the number
was the clue. All 1,000 sit in a single category — **34111, `Money, Banking, & Finance > Banking
> Senior Credit Officer Opinion Survey`**, which holds 2,398 memberships against FRED's reported
1,398. Every one is from the retired `ALLQ*` series family: FRED returns `400 Bad Request` for
each, 0 of the 1,000 carry `notes` while all 1,398 current rows do, and the current ids carry
entirely different prefixes (`CTQ3`, `CTQ1`, `SFQ7`, `OTCD`). FRED replaced the family and the
old YAML loader's rows were never removed, because **nothing in the fetch path deletes** — which
is deliberate. 1,000 exactly, because that was the old export's page size.

**What this exposes is a blind spot in the reconciliation, not a failure of it.**
`fred_category_scan` compares `api_series_count` against `fetched_series_count` — what FRED
reported against what *that run wrote*. That proves a fetch was complete and says nothing about
rows already present, so a category can read `status='ok'` while holding series FRED has
retired. The other half of the check is `held > api_series_count`, now implemented as
`surplus_categories` and reported by `fred_metadata.py status`:

```json
"surplus_categories": 1,
"surplus_memberships": 1000
```

It is reporting only. Pruning needs a complete scan to be safe — a surplus is evidence FRED
dropped something, but a failed or capped fetch would look identical against partial data — so
it stays a separate pass. Tracked in [../planning/yada-todo.md](../planning/yada-todo.md) §5.

### Shape of the tree

| Top-level category | Categories | Memberships |
| --- | --- | --- |
| U.S. Regional Data | 4,173 | 529,976 |
| International Data | 466 | 191,959 |
| Production & Business Activity | 33 | 99,452 |
| National Accounts | 96 | 68,199 |
| Population, Employment, & Labor Markets | 82 | 54,321 |
| Money, Banking, & Finance | 180 | 24,272 |
| Prices | 105 | 17,375 |
| Academic Data | 66 | 16,690 |

Regional data is 80% of the categories and 53% of the memberships. That lopsidedness is the
reason the derived subcategory scheme is still open: county-level titles differ from each other
by place name, not by what they measure, so clustering them on title text would group Alabama's
counties together rather than grouping unemployment measures together. Regional data is
**facet-shaped** (measure × place × time), and a facet scheme is not the same design as the
semantic one.

### Derived columns

Two columns are computed from the data rather than taken from the API, both refreshed once at
the end of a run by `refresh_derived`:

**`frequency_class`** collapses FRED's raw frequency spellings onto eight classes. The raw field
distinguishes `Monthly` from `Monthly, End of Period`, which matters for display and not for
recency arithmetic.

**`currently_relevant`** answers "is this series still being updated?" without a per-series
rule. For each class, the 95th percentile of `observation_end` is taken as what "current" means
for that release cadence, and a series is current if it ends within two periods of that cutoff:

| class | period | p95 `observation_end` | cutoff | series |
| --- | --- | --- | --- | --- |
| annual | 365d | 2025-01-01 | 2023-01-02 | 498,774 |
| monthly | 30d | 2026-10-01 | 2026-08-02 | 220,789 |
| quarterly | 91d | 2026-07-01 | 2025-12-31 | 108,960 |
| daily | 1d | 2026-10-29 | 2026-10-27 | 11,478 |
| weekly | 7d | 2026-11-04 | 2026-10-21 | 3,631 |
| semiannual | 182d | 2026-01-01 | 2025-01-02 | 2,113 |
| other | 365d | 2026-09-16 | 2024-09-16 | 867 |
| biweekly | 14d | 2026-10-29 | 2026-10-01 | 16 |

The percentile is deliberately not a maximum: one series revised unusually late would otherwise
redefine "current" for its whole class. The cutoffs are only correct when every series in a
class is present, which is why they are computed once at the end of a run and not per category.

### The derived subcategory tree

FRED's own taxonomy bottoms out well above browsable size. **206 categories hold 500 or more
series attached directly to them, and 142 of those have no children at all** — terminal nodes
an order of magnitude or two past what a person can scan.

The remaining 64 do have children, and they are the more interesting case: the children exist
but hold almost nothing. `Production & Business Activity > Housing` holds **53,187 series
directly** and its 7 children hold **254 between them — 0.5%**. `National Accounts > Flow of
Funds` holds 46,124 with 2,359 (5.1%) in its 17 children. So descending does not reduce what
sits at the node you are looking at; the subcategories are a thin veneer over an undivided
pile.

Either way the tree stops subdividing long before browsable size, and it needs a level FRED
does not supply. (Measured on the full catalogue; non-regional alone gives 151 such categories,
138 of them terminal.)

`fred_subcategory` holds that derived level — semantic clustering of series titles, with each
node named by an LLM that is required to emit `concepts` containing terms *absent* from the
titles it was given. That requirement is the mechanism: it builds a vocabulary bridge, so a
full-text search for "industrial infrastructure construction" can reach a series titled "Total
Coke Ovens Under Construction for United States", which neither full-text search nor vector
similarity over raw titles finds.

The table is built and tested (77 nodes from two trial categories) but **not populated**. The
full run is ~952 categories, ~27,000 nodes, roughly $4.20 and two hours. It is deliberately
deferred, and the regional facet question above should be settled first.

The procedure, both prompts verbatim, and the rule-by-rule rationale are written up in
[../planning/yada-fred-subcategory-procedure.md](../planning/yada-fred-subcategory-procedure.md)
— it is specified for **meida** to own, since meida is where vendor catalogues belong.

### Why a script here, and not only a notebook

Conventions say a slow or throttled download gets a notebook, not a script, because the saved
cell output is the record that an expensive pull succeeded. The FRED collection has both, and
the reason is that the record lives in `fred_category_scan` rather than in cell output: the run
is resumable, and every category's completeness is a queryable row. A notebook cannot resume,
and a two-hour pull that dies at 90 minutes needs to.

`notebooks/data/fred_meta_data.ipynb` therefore illustrates the API and proves the idempotency
properties against the live catalogue; `clients/bin/fred_metadata.py` is what actually collects.

---

## Part 2 — The ChromaDB catalog (still serving)

This is the store every FRED query currently goes through. It covers **123,119 distinct series
against the Postgres catalogue's 846,628 — a factor of 6.9** — carries the export defects
described above, and is still wired to the agents and to the cache.

### Identity

| | |
| --- | --- |
| Engine | ChromaDB (persistent) |
| Path | `.db/fred` (2.4 GB) |
| Collection | `fred` |
| Documents | 145,679 rows — but **125,869 distinct `(series_id, category_id)` pairs and only 123,119 distinct series.** The grain is one per series-category pair, not one per series, and ~19,810 rows are outright duplicates from repeated loads. See [bugs.md](bugs.md). |
| Embeddings | `OpenAIEmbeddings` (`embedding_ctx_length=2000`, `chunk_size=100`) |
| Loader | `apps/agentic/core/document_loaders/fred_document_loader.py` → `FREDChromaDocumentLoader` |
| Upstream source | YAML exports under `clients/fred/`, produced by `clients/bin/fred.py` |

### What a document looks like

Markdown, titled with the series name and units so semantic search has something meaningful to
match:

```markdown
# Australian Bank Transactions: RBA Spot and Forward Transactions: Net with Dealers (AUD Millions)

## Series Information
- **Series ID:** ...
- **Frequency:** ...
- ...
```

### Metadata schema

| Field | Example | Notes |
| --- | --- | --- |
| `series_id` | `UNRATE`, `GGGDTPUSA188N` | FRED identifier. **Filterable**, exact match. |
| `series_title` | `Total Federal Receipts` | Human-readable title. |
| `units` | `Mil. of $`, `% of GDP` | Display units — reused for plot axes and legends. |
| `frequency` | `Monthly`, `Quarterly` | Release frequency, long form. **Filterable**. |
| `seasonal_adjustment` | `Not Seasonally Adjusted` | **Filterable**. |
| `category_id` / `category_name` | `Government Debt` | FRED category. `category_name` is **filterable**. |
| `category_path` | `Indicators > National Accounts > Government Debt` | Full classification path. |
| `leaf_name` | | Terminal category node. |
| `popularity` | `5` | FRED popularity score (0–87). **Filterable** by range. |
| `observation_start` / `observation_end` | `2006-12-29` | Coverage bounds (ISO strings). |
| `observation_start_int` / `observation_end_int` | `19831212` | **Numeric YYYYMMDD mirrors.** |
| `last_updated` / `last_updated_int` | `2008-03-03T…` / `20080303` | Last release, string + numeric mirror. |
| `filename` | | Source YAML the document came from. |

### Why the `*_int` mirrors exist

ChromaDB cannot range-compare strings — a `$gte` against `"2025-01-01"` raises at query time. So
every date is stored **twice**: the ISO string for display, and a `YYYYMMDD` integer for
comparison. All recency filtering ("series updated within the last year", "data ending after
2020") targets the `_int` fields.

The same convention carries into the PostgreSQL cache, whose `observation_*_int` values are
filtered with `jsonb_path_exists`. The Postgres catalogue needs none of this — it stores real
`date` columns and compares them directly.

### Loading and refresh

Two stages:

1. **Export** — `clients/bin/fred.py` walks the FRED category tree and writes YAML under
   `clients/fred/`:
   - `clients/fred/categories/` — category trees (e.g. `fred_academic_data_33060.yaml`)
   - `clients/fred/series/` — per-category series metadata

2. **Index** — `FREDChromaDocumentLoader.load_all_documents()` reads those exports (default base
   path `clients/fred/categories`) and writes documents into the collection.

`notebooks/documents/fred_chroma_query.ipynb` is the interactive query/inspection notebook.

Because indexing embeds ~146k documents, a full rebuild is expensive — treat it as an occasional
batch operation, not something to run casually. Note that ~19,810 of those documents are
duplicates: `load_all_documents()` has no stable document key, so each run re-adds rather than
upserting ([bugs.md](bugs.md)). **Do not rebuild it to fix either problem;** that work is what
the Postgres catalogue replaces.

### How it is queried

**Agent** — `FredDataInfoAgent` (`apps/agentic/agents/document/fred_data_info_agent.py`), a
`ChromaRAGAgent`, reached via the DocumentAgent delegate
`delegate_to_fred_data_info_search_agent`.

**Filters** — `extract_fred_filters()` parses the request into `FredFilters` and
`fred_filters_to_where()` converts it:

| Filter field | Produces |
| --- | --- |
| `category_name`, `series_id`, `frequency`, `seasonal_adjustment` | Equality |
| `popularity_op` + `popularity_value` | `{"popularity": {"$gte": 50}}` |
| `observation_end` (+ `observation_end_op`) | `{"observation_end_int": {"$gte": 20250101}}` |
| `last_updated` (+ `last_updated_op`) | `{"last_updated_int": {"$gte": …}}` |

Relative dates ("within a year of today") are resolved to absolute ISO dates by the extractor,
then converted to `YYYYMMDD` ints. A missing comparison operator on a recency phrase defaults to
`$gte`, since recency phrasing is overwhelmingly "on or after".

A request naming no filterable attribute yields `None` — a plain semantic search. That is correct
behavior, not a failure: bare "GDP" should return GDP series across all countries.

### Relationship to the time-series cache

This store is the catalog for the `fred` cache source (`apps/agentic/core/agents/series_metadata.py`):

```python
"fred": {"loader": FREDChromaDocumentLoader,
         "key": "series_id",
         "fields": ("category_name", "category_path", "seasonal_adjustment", "frequency")}
```

On fetch, `catalog_metadata("fred", series_id)` copies those four fields into the cache row's
`metadata` under the `fred` key, so cached series and saved reports are filterable with the same
`extract_fred_filters()` used here.

Note the store also supplies `frequency` in **long form** (`Monthly`), which is what the cache's
metadata and its filters use — and what drives the per-series TTL.

**This is the dependency that makes the cutover more than an agent swap.** The Chroma store
feeds the *cache*, not just the agent: a series fetched today has its category and frequency
copied out of Chroma into a cache row that outlives the fetch. Retiring Chroma without
redirecting `catalog_metadata` would leave new cache rows with empty `fred` metadata, and the
report picker's filters would quietly stop matching them.

---

## Cutover

Three consumers read the Chroma store, and they do not all need the same thing:

| Consumer | Needs | Replacement |
| --- | --- | --- |
| `FredDataInfoAgent` | semantic search over titles | Postgres FTS over `title_tsv`, plus the derived `fred_subcategory.concepts` for the vocabulary bridge |
| `series_metadata.catalog_metadata("fred", …)` | four fields by `series_id` | a direct `fred_series` lookup joined to `fred_category` — exact, and 6.9× more series will resolve |
| `notebooks/documents/fred_chroma_query.ipynb` | inspection | `notebooks/data/fred_meta_data.ipynb` |

Order matters: `catalog_metadata` is the cheap one and can move first, since it is a keyed
lookup with no ranking behaviour to preserve. `FredDataInfoAgent` should move only once the
subcategory tree is populated, because `concepts` is what makes conceptual search work over
full-text search — without it, FTS alone fails queries the Chroma store currently answers.

Nothing in the application reads the Postgres catalogue yet. Its only consumers are
`clients/bin/fred_metadata.py` and the unit tests, so the catalogue is complete but unwired, and
retiring Chroma before wiring it would take FRED search offline.

`apps/agentic/db/fred_catalogue.py` is in a mixed state worth knowing about: its helpers
(`frequency_class`, `currency_cutoffs`, the date/int coercions) are imported by
`fred_discovery` and are live, while its YAML readers (`source_files`, `iter_source`,
`read_source`, `build`) are the superseded file-based loader and now have no callers.

---

## Operational notes

- **A wrong answer that looks right is worse than a visible failure.** This is the whole design
  premise of the Postgres catalogue. Prefer a schema where incompleteness is a queryable row
  over a process that reports success.
- **Vocabulary is closed and verbose (Chroma).** `FredFilters` enumerates valid `category_name`
  and `frequency` strings in its field descriptions so the model maps onto exactly what is
  stored; a near-miss silently matches nothing.
- **Never range-filter a date string in Chroma** — use the `_int` mirror. Postgres stores real
  dates and needs no mirror.
- **The Chroma catalog's `observation_end` reflects when the export ran**, so it lags reality.
  Recency filtering over *cached* series therefore uses the cache's own `observation_end_int`,
  recorded at fetch time, rather than this store's value. The Postgres catalogue's
  `currently_relevant` is recomputed from the data on every run instead.
- **The FRED API key fails loudly.** `FredApi()` raises on a missing `FRED_API_KEY`, and a 400
  naming the key raises `FredApiError` rather than being retried as a rate limit. yada's stored
  key was unregistered for an unknown length of time and nothing noticed, because nothing in
  yada called the API.
- **Country data is capped on purpose**, not by oversight — `page_limit_for` caps
  `International Data > Countries` and its children at one page. BIS is the better source.
