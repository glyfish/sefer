# PostgreSQL Data Store

The relational store. Holds **observation data** (cached time series) and **user artifacts**
(saved reports). Everything here is authored or fetched by YADA itself — unlike the ChromaDB
stores, which are catalogs of external reference material.

See [architecture.md](architecture.md) for how this fits the wider system.

---

## Identity

| | |
| --- | --- |
| Engine | PostgreSQL |
| Connection | `YADA_DB_URL` (default `postgresql://yada@localhost/yada`) |
| Access layer | SQLAlchemy **Core** — tables are *reflected* at startup, not declared as ORM models |
| Schema management | Alembic (`alembic/versions/`) |
| Code | `apps/agentic/db/series_cache.py`, `apps/agentic/db/report_cache.py` |
| Tables | `time_series_cache`, `time_series_reports` |

Both caches are singletons initialized once at app startup (`SeriesCache.initialize()` /
`ReportCache.initialize()`), which reflects the table and verifies connectivity. Sync methods do
the SQL; async wrappers (`asyncio.to_thread`) are what agents and endpoints call.

---

## `time_series_cache`

One row per cached series. The observation payload lives in JSONB rather than a narrow
(date, value) table — series are read whole, never joined against.

| Column | Type | Notes |
| --- | --- | --- |
| `cache_id` | uuid PK | `gen_random_uuid()`. **Stable across re-fetches** — reports reference it. |
| `source` | text | Data provider namespace: `fred`, `tiingo`, `alpaca`. |
| `native_id` | text | Provider's identifier (`UNRATE`, `IHY`). Not unique on its own. |
| `title` | text | Human-readable series name. |
| `frequency` | text | Release frequency, long form (`Monthly`, `Quarterly`). |
| `metadata` | jsonb | Source-keyed catalog metadata + units + observation counts. See below. |
| `observations` | jsonb | Full observation payload as fetched. |
| `created_at` / `updated_at` | timestamptz | `now()` defaults. |
| `expires_at` | timestamptz | Freshness horizon; drives re-fetch. |
| `observation_start` / `observation_end` | date | Bounds of the stored data. |
| `ttl_days` | integer | Per-series TTL used to compute `expires_at`. |

**Indexes**

| Index | Purpose |
| --- | --- |
| `time_series_cache_pkey` | `cache_id` |
| `uq_tsc_source_native_frequency` | **Unique** `(source, native_id, frequency)` — the upsert conflict target |
| `idx_tsc_source`, `idx_tsc_native_id`, `idx_tsc_frequency` | Lookup |
| `idx_tsc_expires_at` | Expiry scans |
| `idx_tsc_metadata_gin` | GIN over `metadata` for JSONB filtering |

### The `metadata` column

```jsonc
{
  "units": "USD",
  "observation_count": 3824,
  "tiingo": {                                // source-keyed catalog block
    "family": ["VanEck Asset Management"],
    "category_group": ["Fixed Income"],
    "category": ["Corporate Bonds"],
    "exchange": ["PCX"],
    "observation_start_int": [20110426],     // YYYYMMDD ints, range-queryable
    "observation_end_int": [20260710]
  }
}
```

Catalog values are **always lists**, even for one series, so a report's metadata merges
uniformly. The catalog block is lifted at fetch time from the matching ChromaDB store
(`apps/agentic/core/agents/series_metadata.py`), which is what lets the document-search filter
extractors be reused verbatim against this table. See
[architecture.md §7](architecture.md#7-filtering-architecture).

### TTL semantics

`ttl_days` is derived from the series' release frequency — re-fetching a monthly series daily is
wasted work. Source defaults: `fred` 30 days, `tiingo`/`alpaca` 1 day, with frequency-specific
overrides.

Reads accept `include_expired`:

- **Fetch paths** honor expiry and re-fetch (`fetch_series_into_cache`), preserving `cache_id`
  via an upsert that deliberately does *not* touch it.
- **Report paths** pass `include_expired=True`, so a saved report **always plots** even if its
  series aged out.

---

## `time_series_reports`

A named grouping of cached series, plus the window to plot them over.

| Column | Type | Notes |
| --- | --- | --- |
| `report_id` | uuid PK | `gen_random_uuid()`. |
| `report_title` | text | Display name; target of the picker's text search. |
| `report_description` | text | Free text, default `''`. Also text-searched. |
| `time_series_info` | jsonb | Array of per-series records — see below. |
| `metadata` | jsonb | **Merged** metadata of all member series. |
| `time_range_from` | date | Report window start. |
| `time_range_to` | date, nullable | `NULL` means "track the latest data". |
| `created_at` / `updated_at` | timestamptz | `now()` defaults. |

**Indexes**: `time_series_reports_pkey`, `idx_tsr_report_title`, `idx_tsr_metadata_gin`,
`idx_tsr_time_series_info_gin`.

### `time_series_info` records

Each entry snapshots what the report needs to render without re-reading the cache row:

```jsonc
{
  "cache_id": "a05a0775-…",
  "title": "VANECK INTERNATIONAL HIGH YIELD BOND ETF",
  "source": "tiingo",
  "native_id": "IHY",
  "frequency": "Daily",
  "observation_start": "2012-04-03",
  "observation_end": "2026-07-10",
  "metadata": { … }                 // the series' own metadata, source-keyed
}
```

### `metadata` — the merge

`report_metadata_from_series()` lifts each member's source-keyed block and unions the value lists
(`merge_source_metadata`). A three-ETF report ends up with:

```jsonc
{"tiingo": {"family": ["VanEck Asset Management"],
            "category": ["Corporate Bonds", "High Yield Bonds", "Government Bonds"], …}}
```

Because the lists are unions, a report matches a filter when **any** member series does —
containment semantics for free. A mixed report carries one block per source (`tiingo` *and*
`fred`), so it is reachable from either store's vocabulary.

---

## Access patterns

| Caller | Operation |
| --- | --- |
| `fetch_series_into_cache()` | Upsert on `(source, native_id, frequency)`; re-fetch only past `expires_at`. |
| `DataInfoAgent.list_time_series*` | Inventory listings, optionally filtered by extracted metadata filters. |
| `TimeSeriesReportAgent` | Report CRUD; computes merged `metadata` on create/update. |
| `render_report_plot()` | Reads member series with `include_expired=True`; refreshes best-effort first. |
| `GET /api/reports?filter=` | Metadata-filtered report listing for the plot picker. |

Filtering never uses ad-hoc SQL: a Chroma-style `where` dict is translated by
`apps/agentic/db/metadata_filter.py::metadata_where()` into JSONB containment (`?`, `?|`) and
`jsonb_path_exists` range predicates.

---

## Migrations

| Revision | Change |
| --- | --- |
| `0001_create_time_series_cache` | `time_series_cache` + indexes |
| `0002_create_time_series_report` | `time_series_reports` (`metadata` JSONB + GIN; replaced an earlier `tags` array) |
| `0003_add_ttl_days` | `ttl_days` on the cache |

Apply with `alembic upgrade head`.

---

## Operational notes

- **`cache_id` must survive re-fetch.** Reports store it; regenerating it orphans them.
- **Key by `source:native_id`.** `native_id` collides across providers.
- **The cache is disposable, reports are not** — cached observations can always be re-fetched
  from the provider; reports are user-authored.
- Pre-release, the schema is recreated rather than migrated incrementally; once releases begin,
  every change needs a revision.
