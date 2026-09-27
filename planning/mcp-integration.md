# MCP Integration — Reaching What meida Built

meida publishes **32 MCP tools** over eight sources; yada binds **four**. This is
not a plan to add data sources — every source below is already built, tested and
serving. It is a plan to close the gap between what meida serves and what yada
can reach.

Companion to [architecture.md](../meida/architecture.md) for the client and tool
pattern, [series-catalog.md](../meida/series-catalog.md) and
[time-series-source.md](../meida/time-series-source.md) for the two tables, and
[data-sources-backlog.md](data-sources-backlog.md) for sources that do *not* yet
exist anywhere.

Verified against the live repos, both databases and the running MCP server on
2026-09-27.

**Spans:** meida (tools, catalogues, correctness) and yada (fetch, cache,
discovery, plots). No navi or alef work.

| Phase | Owner | Work |
| --- | --- | --- |
| Wave 0 | yada | Generic stored-series fetch, catalogue-backed discovery, retrieval dispatch |
| Wave 0 | meida | `clio_historical` in the `timeseries_source` arg description; optional FBI response memo |
| Wave 1 | yada | Delete the per-source tax (after the agentic redesign) |
| Wave 1 | meida | A facet-vocabulary tool — the highest-leverage cross-repo ask |
| Wave 2 | both | FRED, BLS, BIS discovery (after the document-store redesign) |

---

## 1. The gap

| Source | Tools | Bound by yada | Series behind them |
| --- | --- | --- | --- |
| FRED | 7 | 2 | 220,401 (yada holds its own Chroma copy) |
| Tiingo | 2 | 2 | — (no catalogue exists) |
| BLS | 5 | 0 | 288,085 |
| BIS | 3 | 0 | 26,902 |
| FBI | 3 | 0 | 1,150 catalogued — a deliberate slice, see §2 |
| CDC | 6 | 0 | 2,346 live Socrata |
| `timeseries_source_*` | 3 | 0 | **11,621 stored** |
| `series_catalog_*` | 3 | 0 | **13,967 catalogue entries** |

The two database-backed families are the ones that matter most: meida built a
working discovery layer with GIN-indexed facet containment and a `total` counted
before the limit, and **yada has never called it**.

The tool surface is not the obstacle. All 32 tools cost roughly **6,950
model-facing tokens** — the adapter discards `outputSchema` — which is less than
yada's own system prompt. Any argument for narrowing the surface on cost grounds
does not survive measurement.

---

## 2. The organising idea: cost follows the route, not the source

### Route A — stored series

`timeseries_source_data(source, native_id, frequency)` serves **all 11,621**
stored series. One request returns one `TimeSeriesRecord`, whose observation
payload was written to match yada's `time_series_cache` contract verbatim.

| Stored source | Series | Origin |
| --- | --- | --- |
| `clio` | 11,042 | Clio-Infra workbooks |
| `clio_historical` | 391 | DataverseNL deposits |
| `cdc_nvsr` | 171 | **Excel workbooks on CDC's FTP** (`Table01–18.xlsx`) |
| `cdc_wonder` | 9 | **Excel** — the WONDER API is throttled to ~1 query / 2 min behind an Akamai bot filter |
| `voteview` | 8 | DW-NOMINATE tables |

These are the only sources whose **observations** live in meida's Postgres. Being
spreadsheet-derived is *why* they are stored rather than fetched: there is no
per-request API behind them, so they cannot be refreshed on demand and
`timeseries_source_stale` exists to make refreshing a deliberate act.

**One tool class covers five sources. The marginal cost of sources two through
five is zero.**

### Route B — live API with a catalogued retrieval block

CDC Socrata (2,346) and the FBI (1,150). Every catalogue row carries a
`retrieval` block whose keys **are the tool's argument names**:

```json
{"tool": "cdc_series_data", "dataset_id": "hksd-2xuw", "concept": "alcohol_binge",
 "facets": {"state": "NJ", "race": "multiracial", "rate_type": "crude"}}
```

One dispatcher reads `retrieval.tool` and passes the rest as arguments. The
marginal cost of each further catalogued source is zero.

### Route C — live API with no retrieval block

BLS and BIS. No `retrieval`, no `description`, catalogues only as gitignored
YAML. These are the genuinely document-store-gated sources.

### CDC straddles two routes, and its history breaks at 2018

Only the **NVSR and WONDER components are in Postgres** (180 series, Excel-derived,
Route A). The other **2,346 are live Socrata** (Route B) and nothing of them is
stored. Discovery does not follow that split: all 2,526 sit in `series_catalog`
under the single source name `cdc`, and the route is told apart by
`retrieval.tool` — `timeseries_source_data` for the stored 180,
`cdc_series_data` for the live 2,346.

The Socrata half does not give a continuous modern series. Measured:

| Dataset | Series | Covers |
| --- | --- | --- |
| `w9j2-ggv5` death rates & life expectancy | 18 | 1900–**2018** |
| `9j2v-jamp` suicide rates | 42 | 1950–**2018** |
| `hksd-2xuw` chronic disease / alcohol | 1,816 | **2019**–2023 |
| `w26f-tf3h` | 28 | 2018–2024 |
| `489q-934x` | 18 | 2023–2025 |
| `xkb8-kh2a` VSRR provisional | 424 | 2015–2026 |

**Both long-history datasets stop at 2018**, and 77% of the Socrata catalogue is a
five-year BRFSS window opening in 2019. So CDC Socrata is not a contemporary
deaths-of-despair source on its own — it is deep history that ends at 2018 plus a
recent narrow window, with the discontinuity falling exactly between them. The
stored NVSR life-expectancy series (2018–2024) bridge that seam, which is why the
Excel route exists at all.

Two consequences for this work. **Rank CDC on that basis, not on its 2,346
count.** And **the source vocabularies differ between meida's two tables** —
`series_catalog` says `cdc`, `time_series_source` says `cdc_nvsr` and
`cdc_wonder`. A dispatcher keyed on `retrieval.tool` is unaffected, but anything
filtering or grouping by source name must not assume the two agree.

Joining the halves into one continuous series is **deferred** until modelling says
what is needed (§5).

### The FBI catalogue is a deliberate slice, not the source

The 1,150 entries are **not** an enumeration of what the FBI serves. Measured
across the eleven export files:

- **57 scopes**: national, the 50 states plus DC and five territories, and
  **five hand-picked agency ORIs** (`NY0303000`, `ILCPD0000`, `DCMPD0000`,
  `PAPEP0000`, `CA0194200`).
- **`count` only** — no `rate` variants, though the tools serve them.
- **Offences and clearances only** — employment covers just five scopes, and
  **arrests are not catalogued at all**. A harvest of 2,736 code × scope pairs is
  running as this is written and will add them.

The dimension that is missing is the one the research wants. The CDE registry
holds **19,636 agencies, 11,784 of them city departments**, and the
enforcement-cycle work needs a *city* panel of offences against officers per head.
Fully enumerated, agency scope is roughly 19,636 × 10 offences × 2 measures ≈
**390,000 series** — larger than the FRED catalogue, for one source.

**So the FBI is the source where enumeration stops being the right model.** Its
discovery has to be *generative*: search the agency registry, then construct the
`retrieval` block from the chosen ORI, rather than pre-catalogue the cross
product. That distinction should be settled in the document-store redesign, and
it is a second argument — beside scale — against assuming every source's
discovery is a table of rows.

---

## 3. The topic id, and the one place it strains

Series ids across CDC, NVSR, Voteview, Clio-Infra and the FBI follow one
pattern, and the same string serves as both **catalogue id and series id**:

```text
clio/cropland_per_capita/romania
cdc/alcohol_binge/hksd-2xuw/state=nj/race=multiracial/crude
fbi/homicide/CA/offenses
```

It is best read as a **data topic id**. The topic plus the request parameters in
the `retrieval` block is what resolves to an actual series. This abstraction came
out of working around Socrata's SoQL interface — the MCP layer translates named
facets into SoQL — and it was reused for sources that are not Socrata at all.
It is the reason a generic dispatcher is possible.

**Preserve the property that facet keys are argument names.** It is what makes
the round trip work without per-source code, and it is the thing most at risk in
a redesign.

### The contract is uniform

Every route resolves to **one request, one series**, which is also exactly how
yada's cache is keyed.

| Route | Request → series |
| --- | --- |
| A — stored | 1 → 1 |
| B — CDC, faceted | 1 → 1 |
| B — FBI | 1 → 1 |

The FBI is worth a note because it *looks* like an exception and is not. One
upstream CDE call carries offences and clearances, as counts and as rates, but
`measure` and `unit` never reach the API — meida selects from the payload and
returns a single series, publishing the rest as context fields rather than as
extra series. The multi-measure payload is absorbed at the MCP boundary and yada
never sees it.

One consequence belongs to meida, not to this work: four MCP calls differing only
in `measure` or `unit` produce four identical upstream calls, against a 1,000
requests/hour allowance with a key-wide lockout on failures. A response memo in
`_call_fbi` would collapse them. That is an optimisation, not a design blocker,
and it does not change anything in yada.

---

## 4. Waves

### Wave 0 — unblocked, reaches 13,967 series

Needs no document store, no agentic redesign and no migration. Ordered so each
step de-risks the next.

**W0-1 · Generic stored-series tool and registry generalisation.**

[`series_fetch.py`](../../yada/apps/agentic/agents/data/series_fetch.py)'s
`SERIES_SOURCE_SPECS` is a 4-tuple carrying exactly **one** id keyword. That
single shape blocks `timeseries_source_data` (three arguments),
`cdc_series_data`, `bis_series_data` and all three FBI tools at once. Replace it
with a spec object carrying an `args(native_id) -> dict` callable.

Add one `CachingTimeseriesSourceTool` registered for `clio`, `clio_historical`,
`cdc_wonder`, `cdc_nvsr` and `voteview`. Two details decide whether it works:

- `_fetch_raw` must wrap the observation list as `{"observations": [...]}` — the
  plot loader reads `entry["observations"]["observations"]`.
- Stash the fetched record on the instance so `_fetch_metadata` reads it rather
  than making a second network call. Instances are built per call, so the stash
  is safe.

Carry the record's source-keyed `metadata` into the cache: it already arrives in
the `{source: {field: [value]}}` shape `metadata_where` expects, with
`observation_start_int`/`observation_end_int` mirrors. **Stored sources become
filterable in Postgres with no vector store involved** — the first sources for
which that is true.

Put MCP response normalisation in a **shared** helper, not in the tool. The
adapter returns content blocks; each existing subclass calls `json.loads` on its
own (see §6), so a shared normaliser is also where those fixes land later.

Add the missing frequencies to `_FREQUENCY_TTL_DAYS` — `BIENNIAL`, `DECADAL`,
`EVERY 20 YEARS`, `EVERY 50 YEARS` cover 4,943 series — and drop the `alpaca`
entries, which reference a source that exists nowhere else.

**W0-2 · Catalogue-backed discovery, no agent in the loop.**

Wrap `series_catalog_search`, `series_catalog_concepts` and
`series_catalog_entry` as deterministic calls returning rows in the shape
`/api/series/search` already emits, **plus the raw `retrieval` block**. Make the
`/api/series/search` source guard a registry lookup instead of a literal tuple.
Add `series_catalog_search` and `timeseries_source_data` to the startup
`required` list so a stale server warns at boot rather than failing at first use.

Two contracts the tool already enforces, which the caller must honour: `limit`
clamps silently to 200, and results are `ORDER BY series_id` — so a truncated
result is the **alphabetically first** *n*, not the best *n*. Surface `total`
against `returned`; never present a truncated list as complete.

Guard the FastMCP stale-server trap: an **unknown argument is silently dropped**,
so a server started before a tool gained a parameter answers a different question
with a 200. Validate arguments against the advertised input schema before
calling, as `notebooks/fbi/utils/mcp.py` already does.

**W0-3 · Retrieval-driven dispatch.**

Add `fetch_from_retrieval(retrieval, series_id)` dispatching on
`retrieval["tool"]` and passing the rest of the block as arguments. This is what
makes every future catalogued source free, and it is what replaces
`SERIES_SOURCE_SPECS` entirely in Wave 1.

Take **CDC Socrata first**: its 2,346 live series are already *catalogued* in
`series_catalog` with complete retrieval blocks — catalogued, not stored; no
observation of them exists in Postgres — so it exercises the live-fetch path with
no policy decision attached. One guard is needed — `cdc_series_data` has `limit=1000`, **no offset
and no vendor total**, so a truncated result is indistinguishable from a complete
one. Set `truncated: true` in cache metadata when `row_count == limit`.

The FBI follows, and needs three things beyond the dispatcher: a decision about
where its catalogue lives (§5); its `notices` carried into cached metadata rather
than dropped, or a run of unfiled months becomes nulls with no explanation; and a
way to reach **agency scope**, which the catalogue deliberately does not
enumerate (§2). For Wave 0 the five catalogued ORIs are enough to exercise the
path; the general case is a discovery question, not a fetch one.

**W0-4 · Plot and report path.**

Add `_CATEGORY_FIELD` entries for the new sources or the legend table loses its
description column. Two shapes must break rather than bridge: Clio-Infra has 722
gaps longer than a year (longest 117), and Voteview's gated Congresses are
**absent, not null** — a plot that interpolates draws through values nobody ever
computed.

### Wave 1 — after the agentic redesign

Not new sources; removal of the per-source tax. A source costs roughly **18–22
edit sites across 12 files, five of them LLM prompts** —
[architecture.md](../yada/architecture.md) §12 names three of them. Delete
`SERIES_SOURCE_SPECS`, the near-duplicate per-source info agents, the four-branch
`search_series_rows`, the `_SOURCE_EXTRACTORS` map and the hand-typed filter
vocabularies.

**The highest-leverage cross-repo ask lives here:** a
`series_catalog_facets(source, concept)` tool in meida over the GIN-indexed
`facets` column. yada's hand-typed vocabularies exist *only* because nothing
serves the vocabulary; `cdc_dataset_facets` already proves the shape.

### Wave 2 — after the document-store redesign

The remaining ~536,000 series: FRED 220,401, BLS 288,085, BIS 26,902. BIS also
needs a correctness fix in meida first — `bis_series_data` never applies
`UNIT_MULT`, so monetary values are wrong by factors of 10⁶–10⁹ with nothing in
the response saying so, and `_series_key` builds keys heuristically in
alphabetical column order.

---

## 5. Questions the redesigns decide

Recorded here so the integration work does not pre-empt them.

- **Do the catalogues move into Postgres?** The question is narrower than it
  looks, because **this generalisation has already happened twice in this repo.**

  `time_series_source` exists because NVSR and WONDER have no per-request API —
  they are Excel workbooks, so serving them at all required an observation store.
  That store was built for those 180 series and then absorbed Clio-Infra, Clio at
  historical borders and Voteview with **zero source-specific server code**
  (`grep` for source names in `mcp_server/timeseries_source.py` returns none). It
  now serves **11,621** series: a 65× expansion over the requirement that forced
  it into existence.

  `series_catalog` was built for CDC and has the same shape — a
  source-parameterised loader, upsert on `(source, key)`, prune scoped to one
  source — and it has **already absorbed three further sources**. Its only source
  references are a default argument and two doc examples; there is no
  behavioural branching.

  So the open questions are not "will it generalise". They are:

  1. **Scale.** Everything consolidated is roughly **553,000 rows**. The standing
     objection — "BLS alone is 288,085 series" — has never been benchmarked, and
     550k rows with a GIN index is unremarkable; `pg_trgm` is available and
     uninstalled. **Measure before accepting it as a constraint.**
  2. **The file-catalogue sources.** FRED, BLS, BIS and the FBI export YAML that
     lacks `retrieval`, and BLS/BIS/FBI lack `description` — so consolidating
     them means synthesising a retrieval block per source, not just loading rows.
     The FBI's already has one; the others do not.
- **Is the ETF store the outlier?** Probably, and for a structural reason: it is
  not a series catalogue but instrument metadata, and 67% of its 36,475 documents
  are German regional venue duplicates of US listings.
- **Is filter extraction the caller's job or the store's?** If the agent keeps
  extracting a where-dict, the store can be a facet index with better embed text.
  If it passes raw natural language, the store needs hybrid retrieval, generated
  vocabularies and reranking. These are different systems, and only the agentic
  redesign picks.
- **One discovery index or one per source?** Collection-per-source makes the
  FRED/BLS twin problem structurally unsolvable rather than merely unimplemented.

---

## 6. Carried debts

Known, deliberately not fixed here.

- **yada's fetch path is broken.** `langchain_mcp_adapters` returns content
  blocks, so `json.loads(raw)` raises `TypeError` in both
  `caching_fred_tool.py` and `caching_tiingo_tool.py`; `time_series_cache` is
  empty in both databases. meida is fine — its notebooks use navi's
  `lib.mcp_client`, which returns text. Two lines per subclass, absorbed by W0-1's
  shared normaliser.
- **`fred_series_info` reads the wrong key.** `info.get("seriess", [])` is FRED's
  raw spelling; meida's response model normalises it to `series`.
- **`MCP_URL` is set in yada's `.env` and never read** — `constants.py` hardcodes
  it. Silent footgun.
- **`apps/backtrader` owns a second price store**, `public.price_series`, fed by
  Yahoo CSVs and keyed `(ticker, date)` with no TTL, no `cache_id` and no
  metadata. Any generic fetch spine has two consumers, not one.
- **`list_releases`** is the only FRED tool without a source prefix.
- **`timeseries_source`'s argument description omits `clio_historical`**, so a
  model reading the schema will not know it can filter for it. One line.
- **Gap filling is deferred** until modelling says what is needed. The obligation
  on this work is only to preserve the evidence: keep provenance, and break gaps
  rather than bridging them.
