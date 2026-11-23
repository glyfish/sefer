# BLS catalogue over MCP

How meida should serve the BLS series catalogue to yada, replacing the metadata
file dumps on the meida side and the document-store file upload on the yada
side.

**Spans:** meida (expose) and yada (consume). meida's half is the smaller one
and is specified here; yada builds its own searchable store on top, the way it
already does for FRED.

**Status: deferred, by decision 2026-11-22.** Three things come first — finish
**FRED over yada's MCP** so that design is fully worked through; then work
through the **other data stores** to get the full picture; then return here.
yada's design changed significantly over the preceding months: it is now
**MCP-based and built for a client supporting MCP/UI**, and **document search in
that new design must be finished before any backfill work**. Returning sooner
would mean designing BLS against a target still in motion.

Everything below was verified live on **2026-11-22** except where marked.

| Phase | Owner | Work |
| --- | --- | --- |
| 1 | meida | Load the BLS catalogue into Postgres (`bls_survey`, `bls_series`) |
| 2 | meida | Expose `bls_catalog_surveys` + `bls_catalog_series` over MCP |
| 3 | yada | Walk those tools; build the merged category/timeseries store |
| 4 | yada | Document search over the result, in the new MCP/UI design |

---

## The thing that is easy to misremember

**The BLS file download does not end up on MCP.** There are two disjoint paths
against two different hosts, and they touch at exactly one point.

```text
api.bls.gov/publicAPI/v2          download.bls.gov/pub/time.series/
   (BLS_API_KEY)                    (no key; Akamai TLS filter)
        |                                     |
   clients/bls.py                     fetch_bls_source_files()
        |                              curl_cffi impersonate="chrome"
        |                                     | -> /tmp/bls_source (transient)
   5 MCP tools                        overview.txt + {s}.series + lookups
   bls_series_data                            |
   bls_series_latest                  write_survey_yaml / write_all_series_yaml
   bls_popular_series --+                     |
   bls_all_surveys      |             notebooks/bls/data/ (148 MB, 24 files)
   bls_survey_info      |             23x bls_series_{CODE}.yaml + survey.yaml
        |               |                     |
   OBSERVATIONS         +-- is_popular -->  CATALOGUE
   (live, on MCP)         the only crossover  (files, NOT on MCP)
```

The observation path is complete and needs no work. The catalogue path produces
148 MB of YAML that **nothing currently reads** — yada has no `bls` collection
(its Chroma holds `etf`, `fred`, `github`, `research_library`) and no BLS
document loader. The consumer was specified in
[meida/api/bls.md](../meida/api/bls.md) under "Building a document per series
(for yada)" and never built.

The single crossover is `fetch_popular_ids()`, which calls `BlsClient` **directly,
not through MCP**, to fill the `is_popular` flag — deliberately, so the export
stays in its otherwise offline generation flow.

## Why BLS cannot follow FRED

yada collects FRED by walking the vendor API directly —
`apps/agentic/db/fred_discovery.py` line 60 is
`BASE_URL = "https://api.stlouisfed.org/fred"`, bypassing meida entirely.

**That route does not exist for BLS.** `bls_popular_series` returns ~25 series
per survey and the API offers no enumeration, no coverage dates and no index
bases. The flat files are the *only* source of the 288,085-series inventory, so
there is no "go direct" option for BLS, ever.

This is the argument for doing the work in meida at all: the proposed tools are
a **capability the vendor API lacks**, not a relocation of a file. yada asks
"what series are in CE, with coverage and frequency?" and meida answers a
question `api.bls.gov` cannot answer.

## Why not `series_catalog`

`load_catalog.load(directory, source)` is fully source-generic — it globs
`{source}_series_*.yaml`, upserts on `(source, series_id)`, prunes within source
scope, and guards against erasing stored descriptions. meida's files are
*already* named `bls_series_AP.yaml`, so they match the glob today. It is
tempting, and it is still wrong:

1. **No survey parent.** `series_catalog` is flat. `survey.yaml` — 23 records
   with ten fields each — has nowhere to land, and the survey layer is exactly
   what yada needs to merge against.
2. **Every row would be routeless.** BLS entries carry no `retrieval` block and
   no `dataset_id`, so `_retrieval()` falls through to
   `{"tool": None, "note": "multi-query union; no single-call route"}` — a bug
   guard that is asserted against in tests. All 13,967 rows in the live table
   are routed; none has ever hit it.
3. **Three fields vanish silently.** `survey`, `seasonal_adjustment` and
   `is_popular` have no column and would be dropped by `_row()` — the same shape
   as the FBI blocker in
   [series-catalog-quality-fields.md](../meida/series-catalog-quality-fields.md).
4. **Scale.** 288,085 rows into a 13,967-row table makes it 95% BLS, while
   inheriting its known weakness that `series_catalog_search` filters are exact,
   not fuzzy.

Separate tables keep the blast radius on clio, cdc, voteview and clio_historical
at zero, and admit openly that meida now has two catalogue shapes.

### What the live table actually holds (2026-11-22)

| source | `series_catalog` | routed via |
| --- | --- | --- |
| clio | 11,042 | `timeseries_source_data` |
| cdc | 2,526 | `cdc_series_data` **and** `timeseries_source_data` |
| clio_historical | 391 | `timeseries_source_data` |
| voteview | 8 | `timeseries_source_data` |

`time_series_source` holds 11,621 stored series (clio 11,042, clio_historical
391, cdc_nvsr 171, cdc_wonder 9, voteview 8).

CDC is the precedent worth noting: ~2,346 of its rows are Socrata entries whose
observations are fetched **live**, catalogued in Postgres anyway. That already
contradicts the rule stated in [meida/api/fbi.md](../meida/api/fbi.md) — "a live
API source keeps its catalog as files" — which should be retired when this work
lands.

## The design

### `bls_catalog_surveys`

23 rows, the full `survey.yaml` field set. Beyond what `bls_survey_info` gives
from the API:

- `series_count` / `active_count` — yada's reconciliation targets, mirroring the
  `api_series_count` vs `fetched_series_count` check in `fred_category_scan`
- `source_mtime` / `source_bytes` — BLS's own stamps, so a resync can skip
  surveys that have not changed

### `bls_catalog_series(survey, offset, limit)`

Paged enumeration with full per-series metadata: `series_id`, `title`, `units`,
`frequency`, `seasonal_adjustment`, `observation_start`, `observation_end`,
`is_active`, `is_popular`, `facets`.

**Paging is not optional.** Measured ~390–530 bytes per series (JT: 802,594
bytes / 2,060 series; LN: 36,238,498 / 68,630), so a whole-survey response for
LN would be ~17 MB. Suggested default limit 500, cap 2,000 — about 576 requests
for a full walk. FRED's walk was 10,809 requests over 74 minutes, so this is
negligible by comparison.

### Survey sizes (from `survey.yaml`, generated 2026-07-26)

23 surveys, **288,085 series**, 265,407 active. Heavily skewed:

| | | | |
| --- | --- | --- | --- |
| LN 68,630 | BD 34,464 | LA 33,985 | SM 22,927 |
| CE 22,049 | IP 21,134 | OE 16,560 | LE 11,053 |
| CU 8,104 | CM 7,998 | CW 7,868 | ND 6,509 |
| WP 5,310 | MP 4,683 | PC 4,509 | FM 3,144 |
| CI 2,470 | JT 2,060 | EI 1,593 | AP 1,483 |
| LU 1,241 | PR 282 | SU 29 | |

Scope note: `CORE_SURVEYS` deliberately excludes the giant cross-products (NW,
WM, CX, EP). OE has its own path — `export_oe_national()` filters a ~6M-series
occupation x geography x industry cross-product down to ~16.5k national,
all-industries series.

### What meida does not do

No hierarchy derivation, no topic tree, no embeddings, no document building.
That is yada's side, exactly as it is for FRED — where yada owns
`fred_category` (with `parent_id` and `category_path`), the
`fred_series_category` join (1,052,462 rows), `fred_subcategory` (the derived
tree, with `centroid` embeddings and `concepts`) and `fred_category_scan` (the
resumable walk ledger).

## Open questions

- **`is_popular` needs a live API call.** `fetch_popular_ids()` is the only part
  of generation that is not offline. Keep it, or drop the field?
- **The `*_int` date mirrors can go.** They exist because a document store
  cannot range-compare date strings; Postgres `Date` columns do it natively.
  Confirm nothing downstream depends on them first.
- **`survey.yaml` has no equivalent on the MCP side today.** `bls_survey_info`
  carries three fields where the catalogue needs ten, including the
  change-detection stamps. Any design that drops them loses the ability to skip
  unchanged surveys.
- **Metadata coverage is partial.** [yada-todo.md](yada-todo.md) records that
  BLS's `Catalog` block gives `survey_name`, `seasonality` and
  `measure_data_type`, and the rest is positionally encoded in the series id,
  needing a per-survey decoder that does not exist.

## Check this first on return

`survey.yaml` is stamped `generated: 2026-07-26` — stale by four months as of
this writing. Regenerate before loading: it exercises the
`source_mtime`/`source_bytes` manifest and reports which of the 23 surveys
actually moved. Note `ND` shows 6,509 series with only 199 active; that is a
discontinued-series survey, but worth confirming rather than assuming.

Be gentle — `download.bls.gov` trips a multi-day block on aggressive access, and
`_bls_get` treats a lingering 403 as throttling rather than denial.
