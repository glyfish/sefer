# CDC Reference — API and data source

Reference for the U.S. Centers for Disease Control (CDC) integration: the CDC
open-data **Socrata (SODA) API** — data, dataset metadata, and catalog discovery,
exposed as MCP tools. Built and in use — `CdcClient` + models in navi, five MCP
tools in meida, and two exploration notebooks (`notebooks/cdc/`).

CDC fills the SDT **immiseration health leg** — life expectancy, mortality, and
*deaths of despair* (drug overdose + suicide + alcohol). Unlike BLS surveys or BIS
dataflows (uniform, enumerable), CDC is **one API over ~1,472 heterogeneous
datasets**, so the client stays generic and the useful datasets are **curated**,
not enumerated.

## Access

- **Base URL:** `https://data.cdc.gov` (`get_cdc_base_url()`; override with
  `CDC_BASE_URL`). Reading public data needs **no credentials**.
- **Optional app token** (`CDC_API_KEY`, `get_cdc_api_key()`) — a Socrata *app
  token*, **not** an API key/secret. It only **raises rate limits** and is sent in
  the `X-App-Token` header when present. Get one from a free Socrata account →
  developer settings.
- Two hosts:
  - **Portal** `data.cdc.gov` — a dataset's rows (`/resource/{id}.json`) and its
    columns (`/api/views/{id}.json`).
  - **Discovery** `api.us.socrata.com/api/catalog/v1` — cross-domain catalog
    search + facets. *Not* on `data.cdc.gov`.
- Docs: [Socrata SODA](https://dev.socrata.com/) · [CDC data portal](https://data.cdc.gov/)

## The core challenge → the design

One API, **many datasets with inconsistent schemas** — each dataset has its own
time / value / facet columns (verified: three curated datasets, three totally
different shapes). So the client is a **thin generic Socrata fetcher**, and the
real work is a **per-dataset field mapping** carried by the catalog export, not the
client. A dataset is addressed by a 4×4 id (e.g. `w9j2-ggv5`). **Socrata returns
every value as a string** — casting is the caller's job.

## Resources (endpoints)

### 1. Data — `GET /resource/{id}.json`

Rows via SoQL query params: `$where` (predicate, e.g. `race='All Races' AND
year>2010`), `$select`, `$order`, `$group`, `$limit`, `$offset` (page a large
dataset). String equality is exact/case-sensitive.

### 2. Columns — `GET /api/views/{id}.json`

A dataset's metadata + columns (`fieldName`, `dataTypeName`, `name`). Inspect
these before querying — schemas differ per dataset.

### 3. Discovery — `GET api.us.socrata.com/api/catalog/v1`

- **Search:** `?domains=data.cdc.gov&q=<keyword>&categories=<domain_category>&limit=`.
  ⚠️ Filtering by a **domain category** requires `search_context=data.cdc.gov`;
  the plain `categories` param (canonical Socrata categories) returns 0 because
  CDC uses its own domain categories.
- **Categories:** `/domain_categories?search_context=data.cdc.gov` — the topic map
  with dataset counts (NNDSS 295, National Center for Health Statistics 287, NIOSH
  177, Vaccinations, Behavioral Risk Factors, …).
- **Tags:** `/domain_tags?search_context=data.cdc.gov` — finer topics
  (`mortality`, `covid-19`, `prevalence`, …).

## The curated datasets

The SDT health slice (not the whole portal). Each needs its own field mapping:

| id | dataset | shape | → series |
|---|---|---|---|
| **w9j2-ggv5** | Death rates & life expectancy, **1900–2018** | `year × race × sex` → `{average_life_expectancy, mortality}` | (metric, race, sex) over year |
| **9j2v-jamp** | Suicide death rates, **1950→** | NCHS "stub" schema: `indicator / unit / stub_label / age / year → estimate` | (stub_label, age) over year |
| **xkb8-kh2a** | Provisional drug-overdose death counts | `state × month × indicator(drug) → data_value` | (state, drug) over year-month |
| *alcohol* | alcohol-induced deaths — **to find** | TBD | completes the despair triad |

Facet values are precise. For `w9j2-ggv5`: races `All Races / Black / White` (only
these — no Hispanic/Asian breakdown), sexes `Both Sexes / Female / Male`.

## Deaths of despair

= drug overdose + suicide + **alcohol** (Case & Deaton). We have overdose
(`xkb8-kh2a`) and suicide (`9j2v-jamp`); the alcohol leg is still to be sourced.
The catalog holds the **components**; the composite (their sum, for working-age
adults) is an **analysis-side** construct (alef/yada), not stored raw.

## Data quirks

- **Everything is a string** → cast (`year`, `average_life_expectancy`, … all
  arrive as text).
- **Suppressed cells.** `w9j2-ggv5` omits `average_life_expectancy` for **Black &
  White in 2018** (all sexes) while their mortality is present — so race-broken-out
  life-expectancy ends at 2017 while `All Races` runs to 2018. `xkb8-kh2a` marks
  low-quality rows with a `footnote_symbol` and null `data_value`.
- **Provisional & revised.** `xkb8-kh2a` is provisional, gets revised, and uses a
  rolling **12-month-ending** window (`period`).
- **CDC WONDER** (finer mortality-by-cause/age) is a separate, harder source
  (XML-POST) — out of scope for this Socrata pass.

## The integration (built)

navi `CdcClient` (`lib/clients/cdc.py`) wraps the API:

- `query(id, where=, select=, order=, group=, limit=, offset=)` → rows; `iter_all(…)`
  pages a whole dataset.
- `columns(id)` → a dataset's columns.
- `discover(query="", category=None, limit=)` → catalog search; `categories()` /
  `tags()` → the facet maps.
- Sends `X-App-Token` per-request when `CDC_API_KEY` is set; `CdcAPIError` on HTTP
  errors. Rows are heterogeneous dicts (`CdcDataResponse`); structure via
  `CdcColumn` / `CdcDataset`; facets via `CdcCategory` / `CdcTag`.

**Five MCP tools** in `meida/mcp_server/server.py`: `cdc_discover`,
`cdc_categories`, `cdc_tags`, `cdc_dataset_columns`, `cdc_series_data`.

**Config** in `lib/env.py`: `get_cdc_api_key()` (`CDC_API_KEY`, optional →
`X-App-Token`) and `get_cdc_base_url()` (`CDC_BASE_URL`).

**Notebooks** (`notebooks/cdc/`): `api.ipynb` (discover → inspect → query → plot,
incl. life expectancy broken out by sex and race via `plot_cdc_series_by`) and
`discovery.ipynb` (browse the catalog by category/tag → drill into datasets).

> The notebooks drive the **running** MCP server, which does not hot-reload — after
> adding/changing tools, fully restart it (and watch for an orphan holding `:8080`).

---

## Catalog export — planned

Not yet built. Following the FRED/BLS/BIS model, the export will curate the
datasets above and pivot each into series records via a **dataset registry** — per
dataset a `{time_field, value_field(s), facet_fields, unit}` mapping — emitting a
CDC catalog YAML (metadata only; observations fetched on demand). Because schemas
differ per dataset, the registry is the real work, not the fetch.

### Known gaps

- **Alcohol dataset** not yet found (deaths-of-despair third leg).
- **Catalog export** not built — the dataset registry + series pivot remain.
- **`xkb8-kh2a` is provisional** and revised; treat its values as preliminary.
