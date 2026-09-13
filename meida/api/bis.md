# BIS Reference — API and metadata files

Reference for the Bank for International Settlements (BIS) integration: the BIS
**SDMX statistics API** (dataflows, structures, observations — exposed as MCP
tools) and the export that builds the series-metadata catalog. Built and in use
— `BisClient` and its models in `clients/`, three MCP tools, and the metadata
export in `notebooks/bis/utils.py`.

Unlike FRED and BLS, BIS speaks **SDMX 2.1** and needs **no credentials**. Its
model maps cleanly onto what the other sources already do:

| BIS (SDMX) | FRED | BLS | Role |
| --- | --- | --- | --- |
| **Dataflow** (e.g. `WS_CBPOL`) | category | survey | the dataset grouping |
| **DSD dimension** (e.g. `REF_AREA`) | — | facet column | one axis of the series key |
| **Codelist** (e.g. `CL_AREA`) | — | lookup table | decodes a dimension's codes → labels |
| **Series key** (e.g. `D.AR`) | series id | series id | identifies one series |

## Two data paths

Both the metadata and the observations come from the **same** SDMX service (no
auth, one base URL) — they're just different resources:

| | Resource | Used for |
| --- | --- | --- |
| **Metadata catalog** | structure resources (`/dataflow`, `/datastructure` + codelists) | the searchable series catalog (dataflow + series YAML) |
| **Observations** | the data resource (`/data/{flow}/{key}`) | the actual period/value points, fetched on demand |

The catalog is built from the structure resources plus one bulk data pull per
flow (to derive coverage dates); once a series is found, its observations are
fetched on demand from the data resource. This mirrors the FRED/BLS split:
**meida builds the metadata; observations are fetched separately and cached in
yada.**

- API entry point: [stats.bis.org/api/v1](https://stats.bis.org/api/v1)
- BIS Stats Explorer (human UI over the same data): [data.bis.org](https://data.bis.org/)
- SDMX RESTful API spec: [sdmx-twg/sdmx-rest](https://github.com/sdmx-twg/sdmx-rest)

## Basics

- **Base URL:** `https://stats.bis.org/api/v1` (`get_bis_base_url()`;
  override with `BIS_BASE_URL`). **No API key, header token, or query param** —
  there is no registration.
- **Two response formats, by resource:**
  - **Structure** (dataflows, DSDs, codelists) → **SDMX-JSON**. The
    `Accept` header must pin the version exactly:
    `application/vnd.sdmx.structure+json;version=1.0.0`. A bare `version=1.0`
    is rejected with **HTTP 406**.
  - **Data** (observations) → request **CSV** (`?format=csv`): one row per
    observation with the series' dimension values repeated on every row. This
    sidesteps SDMX-XML parsing entirely.
- **Errors are true HTTP errors** (unlike BLS's HTTP-200-with-status quirk): a
  bad flow/DSD/key returns `4xx`/`5xx`. `BisClient` raises `BisAPIError` on
  `raise_for_status()`.
- **Frequency codes:** `D` daily, `M` monthly, `Q` quarterly, `S` semiannual,
  `A` annual (the first key position on almost every flow).
- **Period formats** in observations: `YYYY`, `YYYY-MM`, `YYYY-Qn`, `YYYY-Sn`.

## Access & limits

- **No registration, no API key.** BIS publishes no hard rate limits.
- **Be a good citizen anyway.** The export uses the **same rate-limiting
  strategy as BLS** — jittered pacing (`random.uniform(delay, delay*1.8)`) plus
  exponential backoff (`_bis_retry`) — even though BIS has never returned a
  block. BIS does **not** need `curl_cffi`; a plain honest User-Agent
  (`navi-bis-client`) works. See the "be gentle on bulk downloads" project note.
- **Terms / attribution:** BIS statistics are free to use with attribution to
  the BIS as source. See the [BIS terms & conditions](https://www.bis.org/terms_conditions.htm).

## Resources (endpoints)

All paths are relative to the base URL; `{agency}` is `BIS`.

### 1. Dataflows — `GET /dataflow/{agency}`

Lists published datasets (the closest thing BIS has to a survey list). Each
entry carries an `id` (e.g. `WS_CBPOL`), a `name`, and a `structure` URN from
which the DSD id is extracted. `Accept: …structure+json;version=1.0.0`.

### 2. Data structure — `GET /datastructure/{agency}/{dsd_id}?references=children`

Returns the DSD — the **ordered dimensions** of the series key — and, via
`references=children`, every **codelist** that decodes them, in one call. This
is what turns a coded key into labels. Structures are **versioned**
(`BIS_CBPOL(1.0)`); the export takes the bare id and lets BIS serve the latest, so
a version bump is picked up automatically on regeneration.

### 3. Data — `GET /data/{flow}/{key}/{provider}?format=csv`

Observations for a flow. `provider` is `all` (BIS is the sole provider); `key`
is the dot-joined series key (below). Optional `startPeriod` / `endPeriod`
(e.g. `2000`, `2020-Q1`). Two useful `detail` modes:

- `?detail=serieskeysonly` — every series key, **no observations** (used to
  *size* a flow before pulling it).
- `?detail=full` (default) — keys plus observations.

## The series key ⭐

A BIS series is identified by a **dot-joined key of dimension codes, in DSD
dimension order** — one code per dimension. The catalog stores it two ways:
`key` (the dot-joined codes) and `series_id` (`<flow>/<key>`, globally unique).
Two worked examples:

### Example A — `WS_CBPOL` (Central bank policy rates), 2 dimensions

DSD dimension order: `[FREQ, REF_AREA]`. To build the key for *Argentina's
daily policy rate*, take one code per dimension and join with dots:

```text
dimension   code   label (via codelist)
FREQ        D      Daily          (CL_FREQ)
REF_AREA    AR     Argentina      (CL_AREA)
                   ─────────────
key       = D.AR
series_id = WS_CBPOL/D.AR
```

### Example B — `WS_XTD_DERIV` (Exchange-traded derivatives), 6 dimensions

DSD dimension order:
`[FREQ, OD_TYPE, OD_RISK_CAT, OD_INSTR, ISSUE_CUR, XD_EXCHANGE]`. The same
recipe, one code per dimension:

```text
dimension     code   label (via codelist)
FREQ          A      Annual
OD_TYPE       U      Turnover - notional amounts (daily average)
OD_RISK_CAT   B      Foreign exchange
OD_INSTR      A      All instruments
ISSUE_CUR     AUD    Australian Dollar
XD_EXCHANGE   8A     All exchanges
                     ─────────────
key       = A.U.B.A.AUD.8A
series_id = WS_XTD_DERIV/A.U.B.A.AUD.8A
```

**Reading a key back** is the reverse: split on `.`, zip against the DSD's
ordered dimensions, and decode each code through its codelist — exactly what
`build_bis_records` does to populate `facets`.

**Wildcards (querying the data resource):** omit a position to wildcard it
(`M..A`), use `+` for alternatives (`M.US+GB`), or `all` for every series in the
flow. `WS_CBPOL/M.US+GB` = monthly US **and** UK policy rates. Verified live:
`M.` returns all 49 monthly policy-rate series (any country); `.US` returns the
2 US series (daily + monthly); `D.US+GB+JP` returns exactly those three.

### Codes for the worked example (`WS_XTD_DERIV`)

The codes that actually appear in `WS_XTD_DERIV`, so the example above decodes
end to end. Position order is
`FREQ.OD_TYPE.OD_RISK_CAT.OD_INSTR.ISSUE_CUR.XD_EXCHANGE`. Some codelists are
**shared across flows** (`FREQ`, currencies, `CL_AREA` countries); others are
derivatives-specific (`OD_*`, `XD_EXCHANGE`). For any flow's codes at runtime,
use the `bis_datastructure` tool or read the decoded `facets` in the catalog —
this doc documents one flow as a worked reference, not all of BIS's codelists.

**`FREQ`** — frequency (this flow uses 3 of the global codelist's values; it also
has `D` daily and `S` semiannual):

| code | label |
| --- | --- |
| `A` | Annual |
| `M` | Monthly |
| `Q` | Quarterly |

**`OD_TYPE`** — measure (flow vs. stock):

| code | label |
| --- | --- |
| `U` | Turnover – notional amounts (daily average) — trading activity, a flow |
| `A` | Outstanding – notional amounts — open contracts at period end, a stock |

**`OD_RISK_CAT`** — the asset class the derivative's payoff is exposed to (its
market-risk category). This flow covers foreign-exchange and interest-rate
contracts, the latter also split by maturity (short- vs long-term):

| code | label |
| --- | --- |
| `B` | Foreign exchange |
| `C` | Interest rate |
| `I` | Interest rate, short-term |
| `J` | Interest rate, long-term |

**`OD_INSTR`** — the kind of contract. **Futures** lock in a price for future
delivery; **options** grant the right (not the obligation) to trade at a strike
price. `A` (All instruments) is futures + options combined:

| code | label |
| --- | --- |
| `A` | All instruments (futures + options combined) |
| `T` | Total futures |
| `H` | Options, total |

**`ISSUE_CUR`** — the currency the contract is denominated in (for these FX
derivatives, the currency traded against the US dollar — e.g. `AUD` = AUD/USD
contracts). These 25 codes appear in this flow; currencies are a **shared
codelist** reused across flows (via `ISSUE_CUR` and the `BIS_UNIT` attribute), so
other flows may carry more — the full set is available via the `bis_datastructure`
tool. Standard ISO 4217 codes plus two BIS aggregates (`EU1`, `TO1`):

| code | currency | code | currency |
| --- | --- | --- | --- |
| `AUD` | Australian Dollar | `NOK` | Norwegian Krone |
| `BRL` | Brazilian Real | `NZD` | New Zealand Dollar |
| `CAD` | Canadian Dollar | `PLN` | Zloty |
| `CHF` | Swiss Franc | `RUB` | Russian rouble |
| `CNY` | Renminbi | `SEK` | Swedish Krona |
| `DKK` | Danish Krone | `SGD` | Singapore Dollar |
| `GBP` | Pound Sterling | `TRY` | New Turkish Lira |
| `HKD` | Hong Kong Dollar | `TWD` | New Taiwan Dollar |
| `HUF` | Forint | `USD` | US Dollar |
| `INR` | Indian Rupee | `ZAR` | Rand |
| `JPY` | Yen | `EU1` | Sum of ECU, Euro & legacy euro currencies *(aggregate)* |
| `KRW` | Won | `TO1` | Total all currencies *(aggregate)* |
| `MXN` | Mexican Peso | | |

**`XD_EXCHANGE`** — the organized exchange the contracts trade on. BIS aggregates
to **regions** rather than naming individual venues — hence the `8x` codes:

| code | label |
| --- | --- |
| `8A` | All exchanges |
| `8B` | North American exchanges |
| `8C` | European exchanges |
| `8E` | Asian/Pacific exchanges |
| `8F` | Asian exchanges |
| `8G` | Australia/New Zealand exchanges |
| `8K` | Other exchanges |

## Response shapes

**Structure (SDMX-JSON)** — the DSD lists dimensions in order; codelists map
codes to labels:

```jsonc
{ "data": {
  "dataStructures": [ { "id": "BIS_CBPOL", "dataStructureComponents": {
    "dimensionList": { "dimensions": [
      { "id": "FREQ",     "position": 1, "localRepresentation": {"enumeration": "…CL_FREQ(1.0)"} },
      { "id": "REF_AREA", "position": 2, "localRepresentation": {"enumeration": "…CL_AREA(1.0)"} }
    ] } } } ],
  "codelists": [ { "id": "CL_AREA", "codes": [ {"id": "AR", "name": "Argentina"}, … ] } ]
} }
```

**Data (CSV)** — one row per observation; the dimension columns repeat, so the
client groups rows by their dimension tuple to reconstruct series. Beyond the
dimensions, each row carries **attribute columns** (real `WS_XTD_DERIV` header):

```csv
FREQ,OD_TYPE,OD_RISK_CAT,OD_INSTR,ISSUE_CUR,XD_EXCHANGE,AVAILABILITY,DECIMALS,BIS_UNIT,UNIT_MULT,COLLECTION,TIME_PERIOD,OBS_VALUE,OBS_STATUS,OBS_CONF,OBS_PRE_BREAK
A,U,B,A,AUD,8A,K,0,USD,6,E,2025,6197,A,F,
```

| column | meaning | where it lands |
| --- | --- | --- |
| `TIME_PERIOD` | the period the value is for (`YYYY`, `YYYY-Qn`, `YYYY-MM`, …) | `observations[].time_period` |
| `OBS_VALUE` | the reported value — **before** `UNIT_MULT` scaling is applied | `observations[].value` (float; a non-numeric placeholder becomes `null`) |
| `OBS_STATUS` | quality/status of the value: `A` normal, `B` break, `E` estimated, `F` forecast, `P` provisional, plus missing-value variants (`H` holiday/weekend, `L` not collected, `M` cannot exist, `Q` suppressed) | `observations[].status` |
| `BIS_UNIT` | unit of measure (e.g. `USD`, `ARS`) — carries the unit for flows with no `UNIT_MEASURE` dimension | `dimensions` |
| `UNIT_MULT` | **power-of-10 scale** on `OBS_VALUE`: `0` units, `3` thousands, `6` millions, `9` billions, `12` trillions (see below) | `dimensions` |
| `DECIMALS` | display precision — how many decimal places to show | `dimensions` |
| `COLLECTION` | how the value summarizes its period: `E` end-of-period, `A` average, `B` beginning, `S` summed, `H`/`L` highest/lowest, `M` middle | `dimensions` |
| `AVAILABILITY` | dissemination/embargo status — who may see the value: `A` all users (free), `K` free but latest value embargoed, `B`/`C`/`D`… restricted to BIS / central banks / not for publication | `dimensions` |
| `OBS_CONF` | confidentiality: `F` free, `C` confidential, `N` not for publication, `D`/`S` secondary confidentiality | dropped |
| `OBS_PRE_BREAK` | the value before a series break, where one exists | dropped |

`_parse_csv` groups rows by **every** column that is not one of the five
observation columns (`TIME_PERIOD`, `OBS_VALUE`, `OBS_STATUS`, `OBS_CONF`,
`OBS_PRE_BREAK`), and that whole grouping key becomes the series' `dimensions`
map. So the attributes above are *not* discarded — they ride along per series,
next to the real key dimensions, and only `OBS_CONF` and `OBS_PRE_BREAK` are
genuinely lost.

The attribute codes come from BIS's standard SDMX codelists (`CL_OBS_STATUS`,
`CL_CONF_STATUS`, `CL_COLLECTION`, `CL_AVAILABILITY`, `CL_UNIT_MULT`); a
representative subset is shown above.

⚠️ **Value scaling (`UNIT_MULT`).** `OBS_VALUE` is unscaled; the true magnitude is
`OBS_VALUE × 10^UNIT_MULT`, in units of `BIS_UNIT`:

- `WS_XTD_DERIV` AUD turnover: `OBS_VALUE=6197`, `UNIT_MULT=6`, `BIS_UNIT=USD` →
  **6,197 million USD ≈ $6.2 bn** (not 6,197).
- `WS_CPMI_MACRO`: `UNIT_MULT=9` → **billions** of local currency.
- `WS_XRU` (an exchange rate): `UNIT_MULT=0` → value as-is.

`BisClient` **never applies the scale** — `bis_series_data` returns `OBS_VALUE`
as sent. It does carry the ingredients: `UNIT_MULT` and `BIS_UNIT` arrive in the
series' `dimensions` map, so the consumer can do the multiplication. Nothing in
the response *says* the value is unscaled, though, which is the trap.

**No vintages / revisions.** BIS serves current values only — there is no
as-of/real-time history (unlike FRED's ALFRED). `OBS_PRE_BREAK` gives the
pre-break value across a *series break*, the closest thing to a revision signal.

## The API integration (built)

`BisClient` (`clients/bis.py`) wraps the three resources: SDMX-JSON for
structure (with the version-pinned `Accept`), CSV for data (grouped into series
by `_parse_csv`), and `BisAPIError` on HTTP errors. The client and its models are
**meida's** — they sat in `navi/lib/clients` until it was clear meida was their
only consumer; they still import navi's `lib.env`, whose `get_bis_base_url()` is
the whole configuration — **no key accessor, by design**. Three MCP tools in
`mcp_server/server.py`:

| Tool | Wraps | Returns |
| --- | --- | --- |
| `bis_dataflows` | `/dataflow` | `BisDataflowList` — the dataset list (ids + names) |
| `bis_datastructure` | `/datastructure` | `BisDataStructureView` — a flow's dimensions + codelists (`include_codes=false` by default — some codelists have 1000+ entries) |
| `bis_series_data` | `/data` | `BisDataResponse` — observations for a key (codes, not labels — decode via `bis_datastructure`) |

### What the tools publish

BIS is the exception among the sources here: its models need no translation
layer. They are already snake_case, carry no vendor aliases, and have no HTTP
envelope — `BisDataResponse` is `{flow, series[]}` and an observation is
`{time_period, value, status}` — so `bis_series_data` publishes the client model
**unchanged**. `mcp_server/responses/bis.py` therefore holds only two things:

- `BisDataflowList`, an object wrapper, because a bare list produces no
  `structuredContent` at all.
- `BisDataStructureView`, because `bis_datastructure` genuinely returns
  something other than its client model: it blanks each codelist's `codes`
  unless `include_codes=true` and reports `code_count` in their place, so the
  response has to be described honestly rather than as a `BisDataStructure`
  whose `codes` happen to be empty.

`notebooks/bis/client.ipynb` drives `BisClient` directly; `mcp.ipynb` and
`walkthrough.ipynb` go through the server. On `bis_series_data` the two agree
exactly, which is not true of any other source here.

> **Client caveat:** `BisClient._series_key` builds a series' `key`/`title` from
> the CSV columns heuristically — it joins every non-observation column's value
> in **alphabetical column order**, skipping only free text (`TITLE`,
> `COMPILATION`, `SOURCE_REF`, `SUPP_INFO_BREAKS`, `TIME_FORMAT`) plus
> `DECIMALS`/`UNIT_MULT`. Any other attribute column lands in the key, and even
> the real dimensions come out alphabetically rather than in DSD order. Verified
> live: `bis_series_data(flow="WS_CBPOL", key="M.US")` returns
> `key = "M.US.368"` — the SDMX key `M.US` with the `UNIT_MEASURE` attribute
> stuck on the end. Feeding the `WS_XTD_DERIV` CSV row printed above back
> through `_parse_csv` gives `K.USD.E.A.AUD.A.B.U.8A` for a series whose real
> key is `A.U.B.A.AUD.8A`: `AVAILABILITY`, `BIS_UNIT` and `COLLECTION` mixed in,
> the rest re-ordered. `title` is the flow's
> `TITLE` attribute where it has one and `None` otherwise (`WS_CBPOL` has one;
> `WS_XTD_DERIV` does not). The **catalog export sidesteps all of this** by
> rebuilding keys and facets from the DSD dimension list (below); the
> `bis_series_data` tool still has the raw behavior. `dimensions` always carries
> the truth — read the key from there, per column, rather than splitting `key`.
> Fixing the client heuristic is tracked.

---

## Metadata source — the SDMX structure resources

The searchable catalog is built from the structure resources (`/dataflow` +
`/datastructure` with `references=children`), plus one `detail=full` data pull
per flow to derive coverage dates. Keys, facets, frequency, and units are all
decoded from the DSD's dimensions and codelists — **not** from the client's
heuristic key (see the caveat above).

**Scope — 22 flows, not the full ~1.3M-series corpus.** Series count in a flow
is roughly the Cartesian product of its dimension codelist sizes. Six
**giant cross-product flows** (`WS_LBS_D_PUB`, `WS_CBS_PUB`, `WS_DEBT_SEC2_PUB`,
`WS_DER_OTC_TOV`, `WS_NA_SEC_DSS`, `WS_NA_SEC_C3` — locational/consolidated
banking, debt securities, OTC derivatives) hold ~98% of all series through
multiplied high-cardinality dimensions (e.g. two ~200-country dimensions). They
are excluded (`BIS_SKIP_FLOWS`), leaving **22 flows / ~26.9k series**. Like
BLS's OE survey, the giants can later be added as aggregate/headline **slices**
rather than the full cross-product — BIS also offers **bulk CSV** at
[data.bis.org/bulkdownload](https://data.bis.org/bulkdownload), the practical way
to pull a whole giant flow if a slice is ever needed.

### The 22 catalogued flows

The catalog holds **22 flows / 26,902 series**, grouped by theme below (per-flow
counts and key dimensions live in `dataflow.yaml`). CPMI dominates — 8 of the 22
flows and ~60% of all series:

| Theme | Flows |
| --- | --- |
| **CPMI** — payments & market infrastructure (~16.2k) | `WS_CPMI_CT1` · `_SYSTEMS` · `_PARTICIP` · `_CT2` · `_CASHLESS` · `_INSTITUT` · `_MACRO` · `_DEVICES` |
| **Derivatives** (~6.3k) | `WS_OTC_DERIV2` · `WS_XTD_DERIV` |
| **Exchange rates** (~1.3k) | `WS_XRU` · `WS_EER` |
| **Credit & liquidity** (~1.6k) | `WS_TC` · `WS_GLI` · `WS_CREDIT_GAP` · `WS_DSR` |
| **Property prices** (~0.7k) | `WS_DPP` · `WS_SPP` · `WS_CPP` |
| **Central banks** (~0.7k) | `WS_CBTA` · `WS_CBPOL` |
| **Prices** (~0.25k) | `WS_LONG_CPI` |

**No popularity signal.** Unlike BLS (a `popular` endpoint) and FRED
(popularity ranks), BIS exposes nothing to rank series by — so BIS records carry
no `is_popular`. A curated proxy could be added later, but nothing native
supports it.

---

## The catalog files

The export produces one metadata catalog under `notebooks/bis/data/`
(git-ignored, regenerable). It follows the FRED/BLS model, with **dataflow**
standing in for category/survey:

```text
notebooks/bis/data/
├── dataflow.yaml               # all dataflow definitions (the "category" list)
└── bis_series_<FLOW>.yaml      # one per flow; series metadata, references the flow
```

These are **metadata only** — no observed values. They exist so a document
store (yada) can build one searchable document per series; observations are
fetched separately from the data resource.

### `dataflow.yaml`

One entry per flow — the parent that series records reference by code:

```yaml
generated: '2026-07-26'
source: https://stats.bis.org/api/v1
dataflow_count: 22
dataflows:
  - code: WS_CBPOL
    name: Central bank policy rates
    dsd_id: BIS_CBPOL              # DSD id, extracted from the flow's structure URN
    series_file: bis_series_WS_CBPOL.yaml
    series_count: 98
    active_count: 78
    dimensions: [FREQ, REF_AREA]   # the ordered key dimensions
```

### `bis_series_<FLOW>.yaml`

One file per flow; each series record is self-describing except for the `flow`
reference (joined to `dataflow.yaml` for the flow name):

```yaml
flow: WS_XTD_DERIV
generated: '2026-07-26'
series_count: 1296
series:
  - series_id: WS_XTD_DERIV/A.U.B.A.AUD.8A
    key: A.U.B.A.AUD.8A
    title: Exchange-traded derivatives — Turnover - notional amounts (daily average),
      Foreign exchange, All instruments, Australian Dollar, All exchanges
    flow: WS_XTD_DERIV                 # reference -> dataflow.yaml
    units: null                        # some flows carry no UNIT_MEASURE (see gaps)
    frequency: Annual
    observation_start: '1975-01-01'
    observation_start_int: 19750101    # numeric mirror, range-filterable
    observation_end: '2025-01-01'
    observation_end_int: 20250101
    is_active: true
    facets:                            # decoded key dimensions (minus FREQ)
      od_type: Turnover - notional amounts (daily average)
      od_risk_cat: Foreign exchange
      od_instr: All instruments
      issue_cur: Australian Dollar
      xd_exchange: All exchanges
```

#### Field notes

- **`facets`** are the decoded non-`FREQ` key dimensions (code → label via the
  DSD codelists). This is the analog of FRED's `category_path` and BLS's
  `facets` — structured, one entry per key axis.
- **`title`** comes from the flow's `TITLE`/`TITLE_TS` attribute when present.
  Many flows carry none, so the title is then **synthesized** as
  `"{flow name} — {facet labels}"` (mirroring how the BLS catalog builds titles
  from compound lookups), so every series has embeddable text. The example above
  is a synthesized title.
- **`units`** are decoded from the `UNIT_MEASURE` dimension via the unit
  codelist. Flows without that dimension get `units: null` — but many still carry
  a unit in the observation-level `BIS_UNIT` attribute (`WS_XTD_DERIV` → USD,
  `WS_CPMI_MACRO` → ARS), which the export does **not** yet read. See Known gaps.
- **`*_int` date mirrors** exist because a document store can't range-compare
  date strings; recency/coverage filters target the integers (same convention as
  the FRED/BLS stores). Periods map to their first day: `2020-Q3` → `20200701`.
- **`is_active`** = `end_year >= flow_max_end_year - 1` (per-flow, so a flow's
  own publication lag is absorbed). Every series is written, not just active
  ones, so consumers re-filter without regenerating.

### Building a document per series (for yada)

Each record + `dataflow.yaml` gives the document store everything it needs:

- **Embed text:** `title` (which already folds in the flow name + facets) plus
  `units`
- **Filter metadata:** `observation_*_int`, `is_active`, `frequency`, `flow`,
  and each facet
- **Then observations** for a chosen series are fetched from the data resource
  and cached separately — the catalog is a discovery index, not a data store.

### Known gaps

- **`units: null` on ~3.2k series** (`WS_XTD_DERIV`, `WS_XRU`, `WS_CPMI_MACRO`) —
  no `UNIT_MEASURE` dimension. Recoverable for most: the unit is in the `BIS_UNIT`
  data attribute (`WS_XTD_DERIV` → USD, `WS_CPMI_MACRO` → ARS), which the export
  could read from the data pull it already makes. `WS_XRU` is genuinely unitless
  (a rate). Tracked as a follow-up to the title backfill.
- **`UNIT_MULT` scale not applied** — `bis_series_data` values come back
  unscaled (off by 10⁶–10⁹ on monetary flows). The multiplier and `BIS_UNIT` are
  in the series' `dimensions`, so the caller *can* scale, but nothing in the
  response says it must. Folds into the client key/title fix. See Response shapes.
- **`BisClient` key/title heuristic** — `bis_series_data` emits attribute-polluted,
  alphabetically-ordered keys and null titles on flows with no `TITLE` (the export
  doesn't; it builds from the DSD). Tracked.
- **`serieskeysonly` vs with-data counts differ** — the catalog counts series
  that actually have observations, which is fewer than the `serieskeysonly`
  key-combination estimate (e.g. `WS_EER` sized ~271 keys but 89 have data).
  Empty key-combinations are correctly dropped; large gaps are worth a spot
  check.
- **Giant flows excluded** — see scope above; ~98% of the raw corpus is deferred
  to future aggregate slices.

### Regeneration

**No notebook calls this.** `export_bis_catalog` is defined at
`notebooks/bis/utils.py:467` and referenced nowhere else in the repo — no cell,
no `__main__`. The 18 MB / 26,902-series catalog on disk exists because someone
typed the call into a REPL. Run it the same way, from `notebooks/bis/`:

```python
count = await export_bis_catalog()   # 22 flows -> data/dataflow.yaml + bis_series_<FLOW>.yaml
```

`export_bis_catalog()` lists dataflows, skips the giants (`BIS_SKIP_FLOWS`), and
for each remaining flow fetches its DSD (`get_datastructure`, for decoding) and
its full data (`get_data(flow, "all")`, for coverage dates), then
`build_bis_records` decodes keys/facets/units, synthesizes titles where absent,
and derives coverage + `is_active`. Every call is paced by `_bis_retry`
(jitter + backoff). ~4 minutes for all 22 flows. Pass `flows=[...]` to
regenerate a subset.
