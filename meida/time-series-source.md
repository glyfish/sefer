# meida Time-Series Source Database

> **Status: designed, not built** (2026-09-06). The database and `meida` role are
> being created; no migration, client, or tool exists yet.

meida's own PostgreSQL database. It holds observations for sources that **cannot
be fetched per request**, and exposes them over MCP so consumers reach them
through exactly the same path as an API-backed source.

Companion to [architecture.md](architecture.md) and the
[WONDER/NVSR reference](api/wonder-nvsr.md). The consuming side is
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
migrations, the navi client that reads it, and the MCP tools that expose it.
Nothing here belongs to a consumer — yada connects to its own database and never
to this one.

## `time_series_source`

Columns mirror yada's `time_series_cache` deliberately, so anyone who knows one
knows the other.

| Column | Type | Notes |
| --- | --- | --- |
| `source_id` | uuid PK | `gen_random_uuid()`. |
| `source` | text | `cdc_wonder`, `cdc_nvsr`. |
| `native_id` | text | Series identifier, e.g. `cdc/alcohol_induced/wonder/national/age_adjusted`. |
| `title` | text | Human-readable series name. |
| `frequency` | text | Long form (`Annual`). |
| `units` | text | e.g. `deaths per 100,000`, `years`. |
| `metadata` | jsonb | Source-keyed catalog block + units + observation count. |
| `observations` | jsonb | Full payload — see the contract below. |
| `observation_start` / `observation_end` | date | Bounds of the stored data. |
| `created_at` / `updated_at` | timestamptz | `now()` defaults. |
| `expires_at` | timestamptz | **When the series is due for an update**, not a freshness horizon. |
| `ttl_days` | integer | 365 for both current sources. |

**Unique `(source, native_id, frequency)`** — the upsert conflict target, same
as the cache. Index `source`, `native_id`, and `expires_at`; GIN on `metadata`
only if filtering here proves necessary (it should not — filtering is the
document store's job).

### `ttl_days` means "due for an update"

This is the one semantic that differs from yada's cache. There, expiry forces a
re-fetch for freshness. Here there is no live API to re-fetch from — `expires_at`
tells a future refresh workflow when to go **re-run the WONDER pull** or **check
for a new NVSR volume**. Both sources publish annually, so `ttl_days` is 365.

Keeping this separate from the cache is precisely why the table exists: parking
these series in `time_series_cache` would have needed a ~100-year TTL purely to
stop the cache expiring rows it could never re-fetch.

### `observations` contract

Identical to the cache's, so the hop from here into `time_series_cache` is a
straight copy:

```jsonc
{
  "observations": [
    {"date": "1999-01-01", "value": "7.1",       // value is a STRING, ascending by date
     "deaths": 19469, "population": 279040168, "crude_rate": "7.0"}
  ]
}
```

Annual data snaps to `YYYY-01-01`, matching the BIS/BLS month-start convention.
Extra keys ride along untouched — WONDER carries `deaths`, `population` and
`crude_rate` beside the age-adjusted `value`, and readers that only know
`date`/`value` ignore them.

### What does not go here

**CDC Socrata.** It has a working API, so its ~2,502 series stay catalog-only and
are fetched live through the `cdc_series_data` MCP tool. Only sources without a
usable API are stored.

## Migrations

meida owns its own Alembic chain — `alembic/` + `alembic.ini` at the repo root,
following yada's layout. This is new: meida had no database before, and
`SQLAlchemy` / `psycopg2` / `alembic` were removed from `requirements.in` during
the Python 3.14 upgrade because nothing imported them. All three come back.

## The client

navi gets a `TimeSeriesSourceClient` in `clients/`, beside the HTTP clients,
so the uniform interface is visible in the layout. It follows the
[§5 client pattern](architecture.md#5-the-client-pattern) with one substitution:
where the HTTP clients take `client=` (an `httpx.AsyncClient`), this takes
**`engine=`** (a SQLAlchemy engine). That parameter serves the same purpose —
it is what keeps the test suite hermetic.

```python
class TimeSeriesSourceClient:
    def __init__(self, *, db_url=None, engine=None, timeout=30.0):
        self._engine = engine or create_engine(db_url or get_meida_db_url())
        self._owns_engine = engine is None
    async def __aenter__ / __aexit__ / aclose
    async def get_series(source, native_id, frequency=None) -> TimeSeriesRecord
    async def list_series(source=None) -> list[TimeSeriesRef]
```

Errors translate at the boundary to a `TimeSeriesSourceError`, so callers never
see raw SQLAlchemy exceptions — the same rule the HTTP clients follow.

**Testing** (in `meida/tests`, alongside the vendor-client tests): pass a **SQLite
in-memory engine** with the equivalent table — the direct analog of httpx's
`MockTransport`. Real SQL runs, no Postgres required, suite stays hermetic. This
works only while the client's queries stay simple lookups; JSONB containment
(`@>`) would not run on SQLite, which is another reason filtering belongs in the
document store rather than here.

## How consumers reach it

The point of the design — the chain is identical to an API-backed source, so
yada needs no special case:

```text
navi TimeSeriesSourceClient  →  meida MCP tool  →  yada CachingDataTool  →  time_series_cache
      (reads meida's DB)                              (_fetch_raw)
```

Compare FRED, where the first box is `FredClient` and it reads an HTTP API
instead. Everything downstream — `SeriesRef`, `cache_id`, report rendering — is
unchanged.

## Open decisions

- **Env var name** for the connection URL. `MEIDA_DB_URL` keeps navi ignorant of
  which consumer is asking, matching how `get_cdc_base_url()` and friends are
  written.
- **MCP tool naming** — one generic `timeseries_observations`, or per-source
  (`cdc_wonder_observations`, `cdc_nvsr_observations`)? Per-source matches the
  existing FRED/BLS tool naming; generic is less to maintain.
- **Postgres driver** — `psycopg2` matches yada, `psycopg` (v3) is the current
  library. No reason they must agree, since the databases are separate.
