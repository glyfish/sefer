# FRED API — Endpoint Reference

Summary of the Federal Reserve Economic Data (FRED) API as used by the MCP
server — meida's `FredClient` and the tools built on it.

Endpoint paths and response shapes below were **verified against the live API**
(26 endpoints probed successfully); auth/limit details come from FRED's official
docs at <https://fred.stlouisfed.org/docs/api/fred/>, which blocks automated
fetching.

## Basics

- **Base URL:** `https://api.stlouisfed.org/fred`
- **Auth:** `api_key` **query parameter** (32-character lower-case alphanumeric).
  There is no header-based auth.
- **`file_type=json` is required for JSON** — the API defaults to **XML**.
  `FredClient._get` injects both `api_key` and `file_type=json` on every
  request, so callers never think about it.
- **Rate limit:** FRED publishes a cap of **120 requests per minute**.
- **Errors** use real HTTP status codes (400 for bad parameters, 429 when
  throttled), unlike BLS. The client wraps them as `FredAPIError`.

### Common parameters

Most endpoints accept: `realtime_start`, `realtime_end` (vintage/ALFRED dates,
`YYYY-MM-DD`), `limit`, `offset`, `order_by`, `sort_order` (`asc`/`desc`).
Paginated responses echo these back alongside `count`.

## Endpoints

All paths are relative to the base URL. ✅ = verified live during this review.

### Categories

| Endpoint | ✅ | Description |
| --- | --- | --- |
| `GET /category` | ✅ | A single category by `category_id` |
| `GET /category/children` | ✅ | Child categories of a category |
| `GET /category/related` | ✅ | Related categories |
| `GET /category/series` | ✅ | Series within a category |
| `GET /category/tags` | ✅ | Tags for the series in a category |
| `GET /category/related_tags` | | Related tags within a category |

### Releases

| Endpoint | ✅ | Description |
| --- | --- | --- |
| `GET /releases` | ✅ | All releases of economic data |
| `GET /releases/dates` | ✅ | Release dates for all releases |
| `GET /release` | ✅ | A single release by `release_id` |
| `GET /release/dates` | ✅ | Release dates for one release |
| `GET /release/series` | ✅ | Series belonging to a release |
| `GET /release/sources` | ✅ | Sources for a release |
| `GET /release/tables` | ✅ | Release table trees (`elements`) |
| `GET /release/tags` | | Tags for a release |
| `GET /release/related_tags` | | Related tags for a release |

### Series

| Endpoint | ✅ | Description |
| --- | --- | --- |
| `GET /series` | ✅ | Metadata for one series |
| `GET /series/categories` | ✅ | Categories a series belongs to |
| `GET /series/observations` | ✅ | **The actual time-series values** |
| `GET /series/release` | ✅ | The release a series belongs to |
| `GET /series/search` | ✅ | Full-text search over series |
| `GET /series/tags` | ✅ | Tags for a series |
| `GET /series/updates` | ✅ | Recently updated series |
| `GET /series/vintagedates` | ✅ | Vintage (revision) dates |
| `GET /series/search/tags` | | Tags for a search result set |
| `GET /series/search/related_tags` | | Related tags for a search |

### Sources and Tags

| Endpoint | ✅ | Description |
| --- | --- | --- |
| `GET /sources` | ✅ | All data sources |
| `GET /source` | ✅ | A single source |
| `GET /source/releases` | ✅ | Releases for a source |
| `GET /tags` | ✅ | All tags |
| `GET /related_tags` | ✅ | Tags related to given `tag_names` |
| `GET /tags/series` | ✅ | Series matching given `tag_names` |

Maps/GeoFRED endpoints (`/geofred/*`) exist for regional data but are outside
this integration's scope.

### Key parameters for `/series/observations`

Beyond the common set: `observation_start`, `observation_end`, `units`
(`lin`, `chg`, `pch`, `pc1`, `log`, …), `frequency` (`d`, `w`, `m`, `q`, `a`,
with aggregation variants), `aggregation_method` (`avg`/`sum`/`eop`),
`output_type`, and `vintage_dates`.

## Response shapes

FRED has **no single envelope** — the wrapper varies by endpoint.

**Paginated collections** (`/category/series`, `/releases`, `/series/search`, …):

```json
{
  "realtime_start": "2026-07-19", "realtime_end": "2026-07-19",
  "order_by": "series_id", "sort_order": "asc",
  "count": 1234, "offset": 0, "limit": 1000,
  "seriess": [ ... ]
}
```

**Unpaginated** (`/category`, `/series/categories`) return just `{"categories": [...]}`;
`/series` and `/release` return `{realtime_start, realtime_end, seriess|releases}`.
`/series/observations` adds `observation_start`, `observation_end`, `units`,
`output_type`, `file_type`.

### Object fields (verified live)

| Collection | Fields |
| --- | --- |
| `categories` | `id`, `name`, `parent_id` |
| `seriess` | `id`, `realtime_start`, `realtime_end`, `title`, `observation_start`, `observation_end`, `frequency`, `frequency_short`, `units`, `units_short`, `seasonal_adjustment`, `seasonal_adjustment_short`, `last_updated`, `popularity`, `group_popularity`, `notes` |
| `observations` | `realtime_start`, `realtime_end`, `date`, `value` |
| `releases` | `id`, `realtime_start`, `realtime_end`, `name`, `press_release`, `link`, `notes` |
| `sources` | `id`, `realtime_start`, `realtime_end`, `name`, `link` |
| `tags` | `name`, `group_id`, `notes`, `created`, `popularity`, `series_count` |
| `release_dates` | `release_id`, `date` |

### Gotchas

- **`seriess`** — the series collection key really is spelled with a double `s`.
- **`value` is a string**, and missing observations come back as `"."` rather
  than null. Verified: `DGS10` on the 2024-01-01 holiday returns `"."`. Callers
  must handle that sentinel before numeric conversion.
- **`last_updated` uses a non-standard short timezone** (`2024-03-28 07:56:01-05`,
  two-digit offset). `Series._parse_last_updated` normalizes `-05` →
  `-0500` and falls back to naive parsing.
- **Pagination caps differ by endpoint** (verified): collection endpoints cap at
  `limit=1000` ("Variable limit is not between 1 and 1000"), while
  `/series/observations` allows up to `limit=100000`. Exceeding either returns
  HTTP 400.

## What the integration wraps

`FredClient` (`clients/fred.py`) covers 7 of the endpoints. The client and its
models are **meida's** — they sat in `navi/lib/clients` while navi was assumed
to be the shared home for everything, and moved here once it was clear meida
was their only consumer. They still import navi's `lib.env` for keys and base
URLs.

| Client method | Endpoint | MCP tool |
| --- | --- | --- |
| `get_category_children` | `/category/children` | `fred_category_children` |
| `get_category_series` | `/category/series` | `fred_category_series` |
| `get_series` | `/series` | `fred_series_info` |
| `get_series_observations` | `/series/observations` | `fred_series_observations` |
| `get_series_updates` | `/series/updates` | `fred_series_updates` |
| `get_releases` | `/releases` | `list_releases` |
| `get_release_series` | `/release/series` | `fred_release_series` |

Typed models live in `clients/models/fred.py`: `CategoryResponse`,
`SeriesResponse`, `ObservationsResponse`, `ReleasesResponse`. They are frozen
and ignore undeclared fields (e.g. `group_popularity` is dropped).

**`CategoryResponse`'s realtime fields are optional**, unlike every other
response's. FRED's category endpoints send no realtime window —
`/category/children?category_id=13` returns a bare `{"categories": [...]}`, with
no `count` either (verified live). Inheriting `realtime_start`/`realtime_end` as
required from `PaginatedResponse` therefore made `get_category_children()` raise
`ValidationError` on *every* real call. The tool layer had been hiding that by
reaching past the client to its private `_get` and returning the raw dict; it now
calls the typed method, and the two fields are optional on `CategoryResponse`
while staying required on the responses that genuinely carry them.

Not yet wrapped and plausibly useful: `/series/search` (discovery without
walking the category tree), `/series/categories`, `/tags/series`, and the
sources family.

One naming quirk survives: `list_releases` is the only FRED tool without the
`fred_` prefix. (Two others listed in [architecture.md](../architecture.md) §10
are fixed: `fred_category_children` no longer returns a raw dict, and
`list_releases` no longer carries `fred_release_series`' description.)

## What the tools publish

The client models above exist to *parse* FRED. They are **not** what the MCP
tools return. `mcp_server/responses/fred.py` holds a second, meida-owned layer,
and each FRED tool declares one of its models as its return annotation — which
is what FastMCP turns into the tool's `outputSchema`.

The reason for the second layer is that pydantic publishes each field under its
alias where one is declared and its own name otherwise, so handing the client
models to the tool boundary would publish FRED's wire format as this server's
contract — `seriess` and all:

```text
what the client parses            what the tool publishes
{ realtime_start, realtime_end,   { series: [ … ],
  order_by, sort_order,             count }
  count, offset, limit,
  seriess: [ … ] }
```

- **`seriess` becomes `series`.** FRED's payload really does spell the key with
  a double `s`; the client reproduces that faithfully so parsing works. Nothing
  downstream should have to.
- **The envelope goes.** `realtime_start`/`realtime_end`, `order_by`,
  `sort_order`, `offset` and `limit` describe an HTTP call, not data. `count`
  stays: it is FRED's own total, and comparing it against the returned list is
  how a caller learns the result was truncated. It is null where FRED sends no
  total, as on the category endpoints.
- **Dates are ISO strings, not `date` objects.** The client parses them to
  `datetime.date`/`datetime`; the response models re-emit `YYYY-MM-DD` (and
  ISO-8601 with FRED's US-Central offset for `last_updated`), so every field is
  a JSON primitive and the published schema says `string` rather than a format
  the consumer has to guess.
- **`"."` becomes `null`.** FRED's missing-observation sentinel (and an empty
  string or `NA`, defensively) is mapped to null, and the row is kept — so a gap
  stays visible as a date with no value instead of vanishing from the calendar.
- **Per-observation `realtime_start`/`realtime_end` are dropped.** Under a
  non-vintage request every observation repeats the same pair, echoing the
  request rather than describing the data. Revision history is ALFRED's vintage
  endpoints, not this field.
- **`series_id` is added to observations**, filled from the request, because
  FRED's observations payload does not identify the series it belongs to.

| Tool | Model | Top-level fields |
| --- | --- | --- |
| `fred_category_children` | `FredCategoryList` | `categories`, `count` |
| `fred_category_series`, `fred_series_info`, `fred_series_updates`, `fred_release_series` | `FredSeriesList` | `series`, `count` |
| `fred_series_observations` | `FredObservationList` | `series_id`, `observations`, `count` |
| `list_releases` | `FredReleaseList` | `releases`, `count` |

`fred_series_info` returns a **list** even though it looks up a single series:
FRED returns one shape for all of them, so a caller that handles the list
handles every series tool.

The mappers (`from_category_response`, `from_series_response`,
`from_observations_response`, `from_releases_response`) are pure and total — no
I/O, and a `None`, missing or empty input maps to an empty model rather than
raising at the tool boundary. They read mappings by key as well as by attribute,
so a dict payload (a `model_dump()` round-trip) cannot silently map to an empty
result. Tests: `tests/test_responses_fred.py`.

Both shapes are visible side by side in the notebooks: `notebooks/fred/client.ipynb`
drives `FredClient` directly (the parsing models), while `mcp.ipynb` and
`walkthrough.ipynb` go through the server (the published models).
