# meida Time-Series Source Database

> **Status: built** (2026-09-07). Migrations `0d2b2b6d7904` and `8f31c0a4e7d2`
> are applied, the client is `mcp_server/timeseries_source.py`, and three MCP
> tools serve it. 180 series are loaded — 171 NVSR, 9 WONDER.

meida's own PostgreSQL database. It holds observations for sources that **cannot
be fetched per request**, and exposes them over MCP so consumers reach them
through exactly the same path as an API-backed source.

Companion to [architecture.md](architecture.md), the
[WONDER/NVSR reference](api/wonder-nvsr.md), and
[series-catalog.md](series-catalog.md) — the discovery half, which lives in the
same database. The consuming side is
[yada's time-series tables](../yada/postgres-time-series-tables.md).

## Why meida has a database

Every other source is fetched live: a tool call reaches the vendor client, which
calls the provider. Two CDC sources make that impossible.

| Source | Why it cannot be fetched per request |
| --- | --- |
| **CDC WONDER** | Throttled to ~1 query per 2 minutes behind an Akamai bot filter. A single despair-series pull is ~32 minutes. |
| **CDC NVSR** | Annual life tables as Excel on an FTP tree, with no programmatic year → volume-directory mapping. Downloaded by hand. |

Their observations are already on disk after a pull. Something has to stand in
for the provider API, and that is this database — **not a cache, but the source
of truth** for these series.

**meida owns it end to end**: the database, the `meida` role, the Alembic
migrations, the client that reads it, and the MCP tools that expose it. Nothing
here belongs to a consumer — yada connects to its own database and never to this
one.

## `time_series_source`

Columns mirror yada's `time_series_cache` deliberately, so anyone who knows one
knows the other.

| Column | Type | Notes |
| --- | --- | --- |
| `source_id` | uuid PK | `gen_random_uuid()`. |
| `source` | text | `cdc_wonder`, `cdc_nvsr`. |
| `native_id` | text | Series identifier, e.g. `cdc/alcohol_induced/wonder/national/age_adjusted`. |
| `title` | text | Human-readable series name. |
| `frequency` | text | Long form (`Annual` for every row today). |
| `units` | text, null | e.g. `deaths per 100,000` (WONDER), `years` (NVSR). |
| `metadata` | jsonb | Source-keyed catalog block + `units` + `observation_count`. |
| `observations` | jsonb | Full payload — see the contract below. |
| `created_at` / `updated_at` | timestamptz | `now()` defaults. |
| `expires_at` | timestamptz | **When the series is due for an update**, not a freshness horizon. |
| `ttl_days` | integer, null | 365 for both current sources; `load_timeseries` falls back to 365 when it is absent. |
| `observation_start` / `observation_end` | date, null | Bounds of the stored data. |

**Unique `(source, native_id, frequency)`** — the upsert conflict target, same
as the cache. Indexes on `source`, `native_id` and `expires_at`, plus a **GIN
index on `metadata`** (`idx_tss_metadata_gin`). The GIN index is there for
containment queries against the source-keyed catalog block; no query path uses
it yet, since the routine filtering job belongs to the document store.

The `metadata` block is keyed by source — a `cdc_wonder` or `cdc_nvsr` object —
beside a flat `units` and `observation_count`. The two do not carry the same
keys, because they are not the same kind of series: both hold `concept`,
`measure`, `geography`, `definition` and the
[`_int` date mirrors](../conventions.md), but `cdc_wonder` adds `databases`
(the D76/D158 vintages its series was stitched from) while `cdc_nvsr` adds the
demographic facets `sex`, `race` and, for the state tables, `state`.

### `ttl_days` means "due for an update"

This is the one semantic that differs from yada's cache. There, expiry forces a
re-fetch for freshness. Here there is no live API to re-fetch from — `expires_at`
tells a future refresh workflow when to go **re-run the WONDER pull** or **check
for a new NVSR volume**. Both sources publish annually, so `ttl_days` is 365.

**Expiry never withholds a row.** `TimeSeriesSourceClient` computes a `stale`
flag from `expires_at` and returns the data anyway: annual data three weeks late
is fine where a missing series is not, and the only cure for staleness is a
deliberate, throttled re-pull. `timeseries_source_stale` is the query that
replaces a polling process — ask what needs updating when you want to know.

Keeping this separate from the cache is precisely why the table exists: parking
these series in `time_series_cache` would have needed a ~100-year TTL purely to
stop the cache expiring rows it could never re-fetch.

### `observations` contract

Matches the cache's, so the hop from here into `time_series_cache` is a straight
copy. Rows are stored as a **bare JSON array**, ascending by date:

```jsonc
[
  {"date": "1999-01-01", "value": "7.1",       // value is a STRING
   "deaths": 19469, "population": 279040168, "crude_rate": "7.0"}
]
```

The client's `_payload` also unwraps `{"observations": [...]}`, the shape yada's
cache uses, so a row copied verbatim from either side round-trips.

Annual data snaps to `YYYY-01-01`, matching the BIS/BLS month-start convention.
Extra keys ride along untouched — `Observation` sets `extra="allow"`, so WONDER's
`deaths`, `population` and `crude_rate` survive beside the age-adjusted `value`,
and readers that only know `date`/`value` ignore them. NVSR rows carry `date`
and `value` alone.

### What does not go here

**CDC Socrata.** It has a working API, so its 2,346 series are catalog-only and
are fetched live through the `cdc_series_data` MCP tool. Only sources without a
usable API are stored. Those Socrata series *are* discoverable, though — they sit
in [`series_catalog`](series-catalog.md) alongside the 180 stored ones, which is
what lets a single listing span both routes.

## Migrations

meida owns its own Alembic chain — `alembic/` + `alembic.ini` at the repo root,
following yada's layout. Two revisions so far:

| Revision | Creates |
| --- | --- |
| `0d2b2b6d7904` | `time_series_source` |
| `8f31c0a4e7d2` | [`series_catalog`](series-catalog.md) |

`alembic/env.py` takes its URL from `get_meida_db_url()` rather than
`alembic.ini`, so the migrations and the client cannot disagree about which
database they mean.

This chain is new: meida had no database before, and `SQLAlchemy` / `alembic`
were removed from `requirements.in` during the Python 3.14 upgrade because
nothing imported them. Both come back, with **`psycopg[binary]` (v3)** rather
than yada's `psycopg2` — v3 ships macOS wheels, where `psycopg2` needs
`pg_config` to build. The databases are separate, so the drivers need not agree.

## The client

`TimeSeriesSourceClient` lives in **meida**, at
`mcp_server/timeseries_source.py`. It is deliberately not in navi: navi's
clients speak to *external providers* over HTTP, while this database is meida's
own — the schema, the migrations and the SQL belong together, and navi stays
free of a database dependency.

It follows the [§5 client pattern](architecture.md#5-the-client-pattern) with one
substitution: where the HTTP clients take `client=` (an `httpx.AsyncClient`),
this takes **`engine=`** (a SQLAlchemy engine). That parameter serves the same
purpose — it is what keeps the test suite hermetic.

```python
class TimeSeriesSourceClient:
    def __init__(self, *, db_url=None, engine=None, timeout=30.0):
        self.db_url = db_url or get_meida_db_url()
        self._engine = engine or sa.create_engine(
            self.db_url, connect_args={"connect_timeout": int(timeout)})
        self._owns_engine = engine is None      # don't dispose a caller's engine

    async def __aenter__ / __aexit__ / aclose
    async def get_series(source, native_id, frequency=None) -> TimeSeriesRecord
    async def list_series(source=None) -> list[TimeSeriesRef]
    async def list_stale(source=None) -> list[TimeSeriesRef]
```

Two details that are not obvious from the signature:

- **The table is reflected, once, lazily** — not declared. A declared model would
  be a second copy of a schema the migrations own, free to drift from it.
  Reflecting also means constructing a client touches no database.
- **Every query runs in `asyncio.to_thread`.** SQLAlchemy's calls are blocking
  and the tool handlers are async, so the SQL is pushed off the event loop.

`list_series` deliberately excludes the `observations` column — it dominates row
size and a listing never needs it. `get_series` raises when a `native_id` matches
more than one row, naming the frequencies found, rather than picking one.

Errors translate at the boundary to a `TimeSeriesSourceError`, so callers never
see raw SQLAlchemy exceptions — the same rule the HTTP clients follow.

The response models are in `mcp_server/timeseries_source_models.py`: `Observation`,
`TimeSeriesRef` (identity and coverage), `TimeSeriesRecord` (`TimeSeriesRef` plus
`metadata` and `observations`), and `TimeSeriesRefList`. The last exists purely
because FastMCP derives a tool's output schema from its return annotation, and a
**bare list yields no `structuredContent` at all** — so listings are wrapped as
`{"series": [...]}`.

**Testing** (`tests/test_timeseries_source_client.py`, 13 tests): pass a **SQLite
in-memory engine** with the equivalent table — the direct analog of httpx's
`MockTransport`. Real SQL runs, no Postgres required, suite stays hermetic. This
works only while the client's queries stay simple lookups; JSONB containment
(`@>`) would not run on SQLite, which is another reason filtering belongs in the
document store rather than here.

## The MCP tools

| Tool | Returns | Notes |
| --- | --- | --- |
| `timeseries_source_list` | `TimeSeriesRefList` | Identity and coverage, no observations. Optional `source` filter. |
| `timeseries_source_data` | `TimeSeriesRecord` | One series in full. `frequency` only needed to disambiguate. |
| `timeseries_source_stale` | `TimeSeriesRefList` | Series past `expires_at` — due for a refresh, still served. |

They share a `_call_timeseries_source` helper, which owns client lifecycle and
wraps a returned list in `TimeSeriesRefList`.

## `WonderSourceClient`

`mcp_server/wonder_source.py` is a thin, WONDER-shaped face over the same table.
Where `TimeSeriesSourceClient` takes a `source` and a `native_id`, this takes a
**concept** — `alcohol_induced`, `suicide`, `firearm` — and builds the identifier
itself, since every stored WONDER series is national and age-adjusted and the
concept is the only part that varies:

```python
SOURCE = "cdc_wonder"
NATIVE_ID = "cdc/{concept}/wonder/national/age_adjusted"
```

`list_concepts()` is the discovery step: what can be served without touching the
network. `get_series(concept)` returns one in full.

### Why `stored_only` defaults to `True`

Because the alternative costs a rate-limited request that nobody chose to spend.
A live WONDER query is throttled to one per 120 seconds behind a bot filter, so
a fallback-by-default turns a typo into a two-minute stall that *looks like it
worked*. With `stored_only=True` a miss raises `WonderNotStoredError` immediately,
carrying the fix — the concepts that **are** loaded, or a pointer to
`load_timeseries` when the table is empty. A miss should be a loud failure you
repair by loading the data, not a slow success.

The flag makes the safe path the default rather than a convention someone has to
remember. Turning it off does not currently buy a live fetch either:
`stored_only=False` raises `NotImplementedError`, because fetching a concept
means choosing its ICD-10 code set and stitching the D76 and D158 vintages —
which `notebooks/cdc/utils/wonder_series.py` does as a deliberate offline step.

Not exposed as an MCP tool; the server serves WONDER through the generic
`timeseries_source_*` tools. `WonderSourceClient` is what
`notebooks/cdc/client.ipynb` uses to drive the same arc without the server.
Tested in `tests/test_wonder_source.py` (7 tests), against the same injected
SQLite engine.

## How consumers reach it

The point of the design — the chain is identical to an API-backed source, so
yada needs no special case:

```text
meida TimeSeriesSourceClient  →  meida MCP tool  →  yada CachingDataTool  →  time_series_cache
      (reads meida's DB)                               (_fetch_raw)
```

Compare FRED, where the first box is `FredClient` and it reads an HTTP API
instead. Everything downstream — `SeriesRef`, `cache_id`, report rendering — is
unchanged.

## The CDC pipeline, in order

Nothing else records the sequence, and several steps are `python -m` only. Run
from `notebooks/cdc/` unless noted.

| # | Step | Command | Notes |
| --- | --- | --- | --- |
| 1 | fetch the raw files | `downloads.ipynb` | no-op if the tree is complete; `refresh=True` to re-pull |
| 2 | build the `.jsonl` | `python -m utils.build_timeseries` | offline; runs the parse guards |
| 3 | load observations | `load_timeseries.load_all(Path("notebooks/cdc/data/timeseries"))` | reports what moved |
| 4 | export the Socrata catalog | `catalog.ipynb` | ~17 live Socrata queries |
| 5 | export the stored catalog | `python -m utils.catalog_timeseries` | merges WONDER + NVSR into `dataset.yaml` |
| 6 | apply descriptions | `descriptions.apply_to_catalog(data_dir, "cdc")` | **must precede step 8** |
| 7 | normalize | `python -m utils.normalize_catalog` | adds the `_int` date mirrors |
| 8 | load the catalog | `load_catalog.load(data_dir, "cdc")` | upserts and **prunes** |

Two orderings are load-bearing rather than stylistic.

**Step 5 after step 4.** `export_cdc_catalog` writes `dataset.yaml` with only
the Socrata groups it produced — no merge — so running step 4 alone leaves the
index claiming 2,346 series over 6 groups and silently dropping the WONDER and
NVSR registrations. Step 5 puts them back, giving 2,526 over 8.

**Step 6 before step 8.** The export writes group files with no `description`,
and the loader takes the YAML as authoritative. Skipping the description merge
blanks the column for all 2,526 rows, and nothing complains.

`descriptions.generate` is the expensive one — roughly 37 `claude-opus-5` calls
at `max_tokens=16000`, i.e. real money. `apply_to_catalog` only merges the
existing sidecar and is free; that is the one step 6 needs.

## Loading

`db_import/load_timeseries.py` upserts normalized `.jsonl` from
`notebooks/cdc/data/timeseries/` on the `(source, native_id, frequency)`
conflict target. Those files come from `python -m utils.build_timeseries`, run
from `notebooks/cdc/` — it calls `nvsr_series.build_all` and
`wonder_series.build_all` and writes both files. Neither builder touches the
network; both verify before emitting, so a bad parse or a missing WONDER
download summary stops the build rather than producing quietly wrong series.
`source_id` and `created_at` are deliberately left untouched: a refresh updates a
series, it does not replace its identity. `expires_at` is computed here, from
`ttl_days`.

Unlike the [catalog loader](series-catalog.md), this one does **not** prune. A
`.jsonl` file is one pull, not a complete statement of what should exist, so a
series missing from it means "not re-pulled", not "gone".

## Configuration

`MEIDA_DB_URL`, read by `get_meida_db_url()` in `meida/environment.py`, defaulting
to `postgresql+psycopg://meida@localhost/meida`. Named for its **owner** rather
than any consumer, so nothing in navi needs to know which project is asking —
the same rule `get_cdc_base_url()` and friends follow.
