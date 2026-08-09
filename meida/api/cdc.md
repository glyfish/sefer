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
| --- | --- | --- | --- |
| **w9j2-ggv5** | Death rates & life expectancy, **1900–2018** | `year × race × sex` → `{average_life_expectancy, mortality}` | (metric, race, sex) over year |
| **9j2v-jamp** | Suicide death rates, **1950→** | NCHS "stub" schema: `indicator / unit / stub_label / age / year → estimate` | (stub_label, age) over year |
| **xkb8-kh2a** | Provisional drug-overdose death counts | `state × month × indicator(drug) → data_value` | (state, drug) over year-month |
| **hksd-2xuw** | Chronic Disease Indicators — **Alcohol topic**, 2019–2022 | long: `topic/questionid × location(state) × stratification × yearstart → datavalue` (typed by `datavaluetype`/`datavalueunit`) | ALC08 consumption + ALC06 binge (**exposures**); ALC09 chronic-liver mortality (**alcohol-death proxy**) |

Facet values are precise. For `w9j2-ggv5`: races `All Races / Black / White` (only
these — no Hispanic/Asian breakdown), sexes `Both Sexes / Female / Male`.

## Deaths of despair

= drug overdose + suicide + **alcohol** (Case & Deaton). Overdose (`xkb8-kh2a`)
and suicide (`9j2v-jamp`) each have a dedicated dataset; **alcohol does not** — an
exhaustive catalog sweep found **no alcohol-induced-deaths dataset on the Socrata
portal** (see *The alcohol leg* below). The catalog holds the **components**; the
composite (their sum, for working-age adults) is an **analysis-side** construct
(alef/yada), not stored raw.

## The alcohol leg

Alcohol harm is **multi-channel** and no single Socrata dataset captures it as
deaths, so we curate what exists and defer the exact measure:

- **Chronic disease (liver).** `hksd-2xuw` question **ALC09** "Chronic liver
  disease mortality, underlying cause" (annual 2019–2022, state-level, counts +
  crude/age-adjusted rates) — the recognized but **imperfect proxy** (over-counts
  non-alcohol liver disease: hepatitis, NAFLD; under-counts non-liver alcohol
  deaths). Also in `489q-934x` (VSRR, quarterly, provisional, rates only), which
  co-hosts suicide + overdose.
- **Risk-factor exposures.** `hksd-2xuw` **ALC08** per-capita consumption
  (gallons) and **ALC06** binge-drinking prevalence — alcohol *use*, curated as
  **exposures, not deaths**. ⚠️ At the state-aggregate level these correlate **~0**
  with liver mortality (pooled cross-state Pearson r ≈ −0.04 for both) — ecological
  confounding (sales ≠ resident drinking, demographics, tourism). Not a proxy
  shortcut; a real use→mortality link needs individual/panel modeling (alef/yada).
- **Acute injury.** `haed-k2ka` alcohol-impaired *driving* deaths — a different
  (injury) channel, but a **frozen 2005–2014 cumulative total per state**, not a
  time series (the live version is NHTSA FARS, off-Socrata).
- **The exact measure** — the ICD-10 *alcohol-induced causes* grouping (alcoholic
  liver disease + poisoning + cardiomyopathy + …) — is **CDC WONDER-only**, no
  Socrata mirror. Deferred to a future WONDER source.

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
- **"AH" means "Ad Hoc"**, not alcohol — the `AH Provisional … Death Counts`
  family (`qdcb-uzft` Diabetes, Cancer, Sickle Cell) has **no alcohol member**;
  don't chase it looking for an alcohol sibling.

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

**Notebooks + code** (`notebooks/cdc/`): `api.ipynb` (discover → inspect → query →
plot), `discovery.ipynb` (browse by category/tag), `series_over_multipe_data_sets.ipynb`
(stitch history + current across datasets — suicide 1950→2024, life expectancy
1900→2020, the VSRR despair triad), and `catalog.py` + `catalog.ipynb` (the registry
and series-catalog generator; see *Series catalog* below).

> The notebooks drive the **running** MCP server, which does not hot-reload — after
> adding/changing tools, fully restart it (and watch for an orphan holding `:8080`).

---

## Series catalog (built)

The **registry** (`notebooks/cdc/catalog.py`) is CDC's hand-written stand-in for
BIS's SDMX structure — ~10 dataset specs (field maps + value-normalization + three
special-case handlers). `export_cdc_catalog()` walks each spec and writes the
**series catalog** to `notebooks/cdc/data/` (gitignored, regenerable; run via
`catalog.ipynb`): a `dataset.yaml` index + one `cdc_series_<group>.yaml` per source
group. **~2,502 atomic series** — one per facet permutation, like FRED/BIS.

Each entry carries **its exact `cdc_series_data` arguments** (`dataset_id` +
`where` + `select`) plus descriptive metadata (`concept`, `unit`, `frequency`,
`cadence`, `provisional`, `observation_start/end`, normalized `facets`). The agent
therefore **replays a stored recipe** from the document store — it never authors
SoQL nor guesses a facet value. `server.py` is unchanged: `cdc_series_data` stays
the raw-SoQL executor (also handy for exploration); `cdc_discover` /
`cdc_dataset_columns` / `cdc_categories` / `cdc_tags` are dev-only.

| group | series | concepts |
| --- | --- | --- |
| `hksd-2xuw` | 1,816 | alcohol_consumption, alcohol_binge, chronic_liver_mortality |
| `xkb8-kh2a` | 424 | drug_overdose |
| `le_snapshots` | 156 | life_expectancy (state, 2018–2021, union) |
| `9j2v-jamp` | 42 | suicide (history 1950–2018) |
| `w26f-tf3h` | 28 | suicide (current 2018–2024) |
| `w9j2-ggv5` | 18 | life_expectancy, mortality (1900–2018) |
| `489q-934x` | 18 | suicide, drug_overdose, chronic_liver_mortality (VSRR) |

**How the registry tames the mess:**

- **Two pivot modes** — *cross* (independent columns: `w9j2` race×sex, `xkb8`
  state×drug) and *stratified* (one active stratification per row + an optional
  location cross: `hksd` state × {Overall|Sex|Race|Age}; `w26f` is national).
- **Reality-driven** — a per-spec `group_by … WHERE value IS NOT NULL` enumerates
  only combos that exist, so suppressed cells, non-curated strata (`Grade`),
  overlapping age aggregates, and meta drug indicators never become entries.
- **Value normalization** — one canonical vocabulary maps to each dataset's exact
  literal (`white` → `White` / `White only, non-Hispanic` / `White, non-Hispanic`),
  so the same token works across datasets.
- **Three special-case handlers** — the suicide **stub parser** (`9j2v` splits the
  colon-delimited `stub_label` into sex/race/age), the LE **snapshot union** (four
  single-year datasets → one per-`(area, sex)` series with a multi-source recipe),
  and the VSRR **column-melt** (`489q-934x` state/sex live in wide columns → the
  value column is chosen in `select`).

### Known gaps

- **Alcohol** has no dedicated Socrata deaths dataset — curated as the ALC09
  chronic-liver proxy + ALC08/ALC06 use exposures (`hksd-2xuw`); the exact
  alcohol-induced grouping awaits a future **CDC WONDER** source.
- **Life expectancy caps at 2020** nationally on Socrata (recent years are the
  state-snapshot union 2018–2021; national only via each snapshot's US row,
  2018–2020). Extending past 2020 needs a non-Socrata NVSR pull — **dropped**;
  CDC stays Socrata-only.
- **`xkb8-kh2a` / `489q-934x` are provisional** and revised (injury deaths lag) —
  each entry's `provisional` flag and `observation_end` (= last populated) reflect
  this; treat the most-recent quarters as preliminary.
