# Data Sources — Backlog and Evaluation

Candidate data sources beyond FRED, Tiingo, and BLS. Each entry records what it
is, how it's accessed, how it fits the current architecture, and what it would
cost to add. Findings below were verified against the live sites except where
marked *unverified*.

See [architecture.md](../meida/architecture.md) for the current client/tool pattern.

---

## The key architectural question

The stack currently assumes one shape: **a series with observations over time**
(meida client → pydantic models → MCP tools → ChromaDB catalog + Postgres cache).

Some candidates fit that shape directly; the rest break it, and each needs a
deliberate decision about whether it belongs in the same stores or gets its own.

| Source | Data shape | Fits current pattern? |
| --- | --- | --- |
| BIS | Time series | ✅ Directly |
| CDC | Time series | ✅ Directly |
| Voteview | Panel → derived series | ✅ Mostly (needs reduction) |
| Clio-Infra | Time series (historical) | ✅ Directly (Excel loader) |
| FRED/BLS overlap | — (reconciliation task) | n/a |
| Polymarket | Ephemeral, high-frequency probabilities | ❌ Different lifecycle |
| LittleSis | Graph (entities + relationships) | ❌ Not time series |
| Congress.gov | Text + cosponsorship graph | ❌ RAG + graph reduction |
| Seshat (cliodynamics) | Polities with dated attributes | ❌ Not time series (graph/RAG) |

Several of these (CDC, Voteview, Congress, Clio-Infra) feed the structural
demographic theory project — see
[structural-demographic-theory.md](structural-demographic-theory.md) for how they
combine.

---

## 1. FRED / BLS overlap — reconciliation, not a new source

**The problem.** FRED republishes BLS data. CPI, unemployment, and payrolls
exist under both a FRED series ID (`UNRATE`, `CPIAUCSL`) and a BLS series ID
(`LNS14000000`, `CUUR0000SA0`). Once both catalogs are in the vector store the
same underlying statistic appears twice, with different IDs, titles, and units
vocabularies — semantic search will return both and the agent has no basis to
choose.

**Considerations.**

- FRED is a *mirror*: it adds its own IDs, consistent units metadata, and ALFRED
  vintage/revision history that BLS's API does not expose.
- BLS is the *origin*: richer faceting (demographics, industry, occupation) and
  the authoritative release.
- Revisions may land at different times, so the two can disagree transiently.

**Options.** (a) Prefer BLS for BLS-origin series and suppress the FRED
duplicate; (b) keep both but tag `provenance` and `is_mirror`; (c) build a
mapping table for the top overlapping series and let the agent pick by need
(vintages → FRED, facets → BLS).

**Value:** high — prevents confusing duplicate results.
**Effort:** moderate; mostly analysis, and only the popular series matter.

---

## 2. BIS — Bank for International Settlements

> **Status: done.** Client + MCP tools (navi `fff84bf`, meida `b05a7c2`) plus the
> document-store catalog (22 flows / ~26.9k series). See the
> [BIS reference](../meida/api/bis.md).

**Access (verified).** SDMX 2.1 API at `https://stats.bis.org/api/v1`, plus a
data portal at <https://data.bis.org/> and **bulk CSV** at
<https://data.bis.org/bulkdownload>. **No credentials of any kind** — verified
on both structure and observation endpoints with only a `User-Agent`. This makes
BIS the only unauthenticated source in the stack, so there is no `.env` entry
and no quota to design around.

**Data.** 29 dataflows: total credit, debt service ratios, residential and
commercial property prices, effective exchange rates, central bank policy rates,
locational and consolidated banking statistics, debt securities, OTC
derivatives, global liquidity indicators, CPMI payments, consumer prices.

**Structural model.** Maps almost one-to-one onto the BLS work:

| BLS | BIS (SDMX) |
| --- | --- |
| Survey (68) | **Dataflow** (29) |
| Facet columns (`lfst_code`) | **Dimensions** (7 for total credit) |
| Lookup files (`ln.lfst`) | **Codelists** (`CL_AREA`, 101 codes) |
| Per-survey column layout | **DSD** (data structure definition) |

BIS is the *easier* of the two: the DSD declares which codelist decodes each
dimension, so nothing has to be reverse-engineered from filenames (the trap that
made `ce`/`sm` fail in BLS), and `?references=children` returns the DSD plus all
codelists in a single request. Units are a real dimension (`UNIT_TYPE`) rather
than three per-survey encodings.

**What was built.**

- `clients/bis.py` — `BisClient` with `get_dataflows`, `get_datastructure`,
  `get_data`; `clients/models/bis.py` — frozen models with
  `BisDataStructure.decode()`.
- MCP tools `bis_dataflows`, `bis_datastructure`, `bis_series_data`.
- 22 tests against fixtures captured live, including one asserting that **no
  credentials are ever sent**.

**Implementation notes worth keeping.**

- **SDMX-JSON needs an exact version.** `version=1.0.0` or `2.0.0`; a bare
  `version=1.0` returns HTTP 406.
- **CSV for data, SDMX-JSON for structure.** Requesting `format=csv` on the data
  path avoids SDMX-XML parsing entirely — dimensions arrive as plain columns.
  This kept the client to ~230 lines instead of pulling in `pandasdmx`.
- **Data responses carry codes, not labels.** `UNIT_MEASURE: '368'`, not
  `'Per cent per annum'`. Decoding requires pairing with `get_datastructure()`.
- **Codelists are large.** `CL_BIS_UNIT` has 1,096 codes; a full DSD dump is
  ~42 KB versus ~1.8 KB without codes. `bis_datastructure` therefore suppresses
  code/label pairs by default (`include_codes=False`) and reports counts.

**Remaining.** Series enumeration strategy (query with wildcards vs the
availability endpoint) determines whether the catalog is thousands or millions
of series — verify this first, as it did for BLS. Then the export:
dataflows → `survey.yaml`, series + dimensions → series files, codelists →
facet decoding. Also the FRED overlap from §1, at smaller scale, since FRED
republishes selected BIS property-price and credit-gap series.

**Value:** high. **Effort:** the catalog export only; the client is done.

---

## 3. Polymarket

> **Sequenced after Clio-Infra — research-first.** Before building: understand how
> its markets/prices work and sketch a couple of concrete scenarios where the event
> probabilities are useful; implement only if it proves easy.

**Access (partly verified).** Public docs at <https://docs.polymarket.com>, with
a machine-readable index at `llms.txt`. Read access needs **no authentication**.
Gamma API (market metadata) and CLOB API (prices, order books), plus official
Python/TypeScript/Rust SDKs. *Endpoint specifics and rate limits unverified.*

**Evaluation.** The most *differentiated* candidate — forward-looking implied
probabilities of future events, which nothing else here provides. Also the worst
fit for the current architecture.

**Challenges.**

- **Lifecycle, not history.** Markets are created, trade, then resolve to 0 or 1
  and stop. That's not a continuing series; the catalog churns constantly.
- **Refresh cadence.** Yearly rebuilds are meaningless here. Prices move
  continuously and a market's interesting window may be days.
- **Modeling.** A price *is* a probability, bounded 0–1, with a resolution date
  and criteria. Needs its own schema, not the series/observation model.
- **The text is the value.** Market questions and resolution criteria are prose,
  making them a natural RAG target — but they'd need a separate store with an
  aggressive refresh, not the annual-rebuild catalog.

Trading later means wallet/auth and a much higher correctness bar; keeping
read-only strictly separate from any future trading path is worth doing from the
start.

**Value:** high but distinct. **Effort:** high — needs its own storage strategy.

---

## 4. LittleSis

**Access (verified).** Free JSON API at <https://littlesis.org/api>, **no API
key or authentication** (may be rate-limited). Endpoints: `/api/entities/:id`,
`/api/relationships/:id`, `/api/entities/:id/relationships`, `/connections`,
`/lists`, and `/api/entities/search?q=`. Bulk dataset download available.
Licensed **CC BY-SA 4.0**.

**Data.** People and organizations, plus the relationships between them: board
memberships, donations, ownership, employment.

**Evaluation.** Genuinely different and complementary — board interlocks,
ownership networks, and influence mapping are questions the time-series stack
simply cannot answer.

**Challenges.**

- **It's a graph.** Entities and edges don't fit the series model. Natural homes
  are Postgres (nodes/edges) or a graph store; forcing it into ChromaDB alone
  loses the traversal that makes it valuable.
- **Provenance.** Activist-curated and partly crowd-sourced. Coverage is uneven
  and framing is not neutral. Fine for exploration and lead generation; needs
  corroboration before anything decision-critical.
- **CC BY-SA 4.0** carries share-alike obligations if data is redistributed —
  worth checking against how yada surfaces it.

**Value:** medium-high, exploratory. **Effort:** medium, plus a storage decision.

---

## 5. Congress.gov

**Access (unverified — docs not reachable in this pass).** Official API at
`api.congress.gov`, believed to require a free **api.data.gov** key with an
hourly request cap. Endpoints for bills, amendments, members, committees,
nominations, treaties, and the Congressional Record. GovInfo offers bulk data as
an alternative. **Confirm key mechanics and rate limits before building.**

**Evaluation.** Legislative and regulatory signal — useful for connecting policy
activity to sectors. Text-heavy, so it suits a RAG document store better than
the numeric pipeline, and bill text is exactly what vector search is good at.

**Challenges.** Volume is large and bills are long (chunking strategy needed).
Mapping legislation to tickers/sectors is a hard, fuzzy problem and probably the
real work — the ingestion is comparatively easy.

**Value:** medium, depends on the mapping. **Effort:** medium for ingest, high
to make it analytically useful.

---

## 6. Cliodynamics — historical databanks (Seshat et al.)

> Corrects an earlier version of this entry that described Columbia University's
> CLIO **library catalog** (MARCXML/CC0). That was the wrong "CLIO." The intent
> is **cliodynamics** — quantitative analysis of history — for a research
> project tangential to finance.

**What it is.** Cliodynamics is a field, not one dataset. It draws on several
long-horizon historical databanks. The flagship is **Seshat: Global History
Databank**; others named alongside it are D-PLACE, CHIA, eHRAF, and the Atlas of
Cultural Evolution. (Clio-Infra — the economic-history databank often lumped in
here — is a different tradition, *cliometrics*, and plays a different role; it is
split out as its own SDT source in §9.)

**Access (verified — Seshat).** Open Django REST API at
<https://seshat-db.com/api/>. **No authentication** for reads, JSON, standard
`count`/`next`/`previous`/`results` pagination. Also GitHub repos and download
pages; a User Agreement & Data License applies. Endpoint groups: `core`,
`sc` (social complexity), `wf` (warfare), `ec` (economy), `crisisdb`,
`general`, `rt`.

**Data.** 864 polities across 47 regions and 10 macro-regions spanning millennia
(e.g. "Early Qing", `start_year 1644, end_year 1796`). Variables cover social
complexity (territory, population, bureaucracy, infrastructure), warfare,
religion, and crisis/instability events — each value carrying uncertainty,
citations, and recorded expert disagreement.

**Evaluation.** Genuinely interesting and cleanly accessible, but the **worst
architectural fit in the backlog**. The unit of record is a *polity with dated
attributes*, not a series of observations over time — `sc/polity-populations`
gives a population estimate scoped to a polity's date range, not a continuous
annual line. It resembles LittleSis's graph-of-assertions more than FRED's
series, and the citations/disagreement metadata are arguably the point, which
also makes it a RAG candidate rather than a numeric one.

**Challenges.**

- **Not a time series.** Needs its own schema (polity → variable → dated value
  with provenance); do not force it into the series/observation model.
- **Sparse and uneven.** Coverage varies wildly by polity and variable; many
  values are ranges or disputed. Fine for exploration, not for precise trends.
- **Separate project.** Flagged as tangential to finance, so it should be its
  own store with no link to the financial pipeline. Sequence independently.

**Value:** high for its own project, nil for finance. **Effort:** low to ingest
(clean API), medium to model the polity/provenance shape well.

---

## 7. CDC — public health statistics

> **Status: done — all three delivery routes.** What began as the Socrata leg
> now covers Socrata, WONDER and NVSR behind one catalog. See the
> [CDC reference](../meida/api/cdc.md) and
> [WONDER/NVSR](../meida/api/wonder-nvsr.md).
>
> | | series | coverage | how it is fetched |
> | --- | --- | --- | --- |
> | Socrata | 2,346 | varies, to 2018–2024 | live, `cdc_series_data` |
> | WONDER | 9 | 1999–2024 | stored; the API is throttled to 1 query/2 min |
> | NVSR national | 18 | 2018–2024 | stored; xlsx pulled from FTP by hand |
> | NVSR state | 153 | 2018–2022 | stored; 51 jurisdictions × 3 sexes |
>
> Two tables carry it. **`series_catalog`** (2,682 rows, every one with an
> LLM-written description) is discovery — what exists, which facets pick it
> out, and a `retrieval` block naming the tool that fetches it. That block is
> what lets one listing serve both routes. **`time_series_source`** (180
> series, 1,119 observations) holds observations only for the file-delivered
> sources, and stands in for the API endpoint they do not have; its TTL means
> "due for a refresh", not "too old to serve". Socrata is deliberately absent
> from it — it has a working API, so storing it would be a cache that goes
> stale for nothing.
>
> Notebooks per source: `discovery`, `walkthrough`, `mcp`, `client`, `api`,
> `catalog`, `wonder`.
>
> **No open items.** Three were logged and all three are closed:
> - The 156 `le_snapshots` series were discoverable but unfetchable
>   (`tool: null` — they needed four datasets unioned). Those Socrata
>   datasets turned out to be the NVSR state life tables rounded to one
>   decimal, which the stored series already carry with an extra year, so the
>   group was **deleted** rather than given a union tool. Catalog 2,682 →
>   2,526, and every entry now has a route.
> - Three facet keys covered one concept across two vocabularies, so
>   `state=AK` returned 42 of 45 silently. Normalised: `state` holds a postal
>   code everywhere, `geography` means only `national`.
> - The normalized `.jsonl` is no longer gitignored — 224K standing behind 936
>   workbooks hand-pulled from a bot-filtered FTP host.

**Access (verified).** Socrata API at `data.cdc.gov/resource/<id>.json` (also
CSV). **No token required** for reads (an app token raises rate limits). Rows
returned live without auth. Discovery via the Socrata catalog API.

**Data.** Mortality, life expectancy, and cause-of-death series. Confirmed
dataset ids: `w9j2-ggv5` (death rates & life expectancy at birth — fields
`year, race, sex, average_life_expectancy, mortality`), `xkb8-kh2a` (provisional
drug-overdose deaths), `9j2v-jamp` (suicide death rates). CDC WONDER offers finer
mortality-by-cause/age but through a clunky XML-POST API.

**Evaluation.** The contemporary-US **health** leg of structural demographic
theory — the immiseration signal BLS cannot supply. The headline metric is
**deaths of despair** (Case & Deaton: drug + alcohol + suicide mortality),
effectively a purpose-built immiseration index. Fits the time-series model
directly; a thin `CdcClient` mirrors the existing pattern.

**Challenges.** Socrata is one API over *many* independent datasets with
inconsistent schemas, so there is no single response shape — each dataset id
needs its own field mapping. Provisional series get revised.

**Value:** high (for SDT). **Effort:** low — token-free API, standard shape.

---

## 8. Voteview — Congressional roll-call ideology

**Access (verified).** Direct CSV/JSON download, no auth
(`voteview.com/static/data/out/...`). `HSall_members.csv` is 6.2 MB, **51,063
member-Congress rows** with `nominate_dim1`/`dim2` (DW-NOMINATE) plus party and
biographical fields. A ~500 MB MongoDB dump is offered for full programmatic use.

**Coverage.** **Every Congress, 1st through 119th — 1789 to 2027, no gaps.** The
longest span of any source in the stack (~236 years).

**Data.** Member ideology (DW-NOMINATE), roll-call votes, members' votes, and
party-polarization/unity series. The authoritative source for Congressional
voting behavior over time.

**Evaluation.** Supplies the cheap, robust half of the **intra-elite cohesion**
leg of SDT: the shrinking moderate "overlap" bloc and bipartisan-vote fraction,
both derivable from the member file. Turchin uses DW-NOMINATE polarization
directly in *Ages of Discord*. Complements the (harder) cosponsorship and
Record-text metrics — see the SDT doc.

**Challenges.** It's a **panel, not a series** — one row per member per Congress.
Producing a cohesion *time series* means a reduction step (e.g. count members
between the party medians per Congress). Straightforward, but not a plain load.

**Value:** high (for SDT). **Effort:** low — download + a reduction pass.

---

## 9. Clio-Infra — historical economic & well-being data

**What it is.** Long-run datasets on **economic and social well-being** — GDP per
capita, real wages, human height, life expectancy, literacy, income inequality —
by country/region over the past several centuries (strongest coverage 1800→, some
series back to ~1500). The quantitative **cliometrics** tradition (IISH / Utrecht;
van Zanden et al.), distinct from Seshat's cliodynamics (§6) despite the shared
"Clio."

**Access (unverified — licensing).** Per-indicator spreadsheet (`.xlsx`)
downloads; **no API**. Each indicator is one file of country × year values.
Licensing terms are unstated on the site — confirm reuse before redistributing
derived data.

**Data.** Dozens of indicators, each a set of country/region time series —
directly the series/observation shape (one indicator file → many per-country
series).

**Evaluation.** The **historical backbone** of the SDT project: it extends the
contemporary US immiseration and inequality signals (BLS, CDC) back centuries and
is the part meant to be *written about*. Unlike Seshat (§6) it drops straight into
the existing series model — an Excel loader, no new machinery.

**Challenges.** No API (parse `.xlsx` per indicator); coverage and methodology
vary by indicator and era; **splicing** historical series onto contemporary
BLS/CDC needs a documented join (differing definitions/boundaries — the `_int`
date-mirror and provenance conventions apply).

**Value:** high (for SDT — the long backdrop). **Effort:** low–medium (Excel
loader; the splice is the fiddly part).

---

## 10. CMS — Medicare, Medicaid, and health expenditure

> **Status: evaluated, mostly skip.** Take three non-Medicare series; skip the
> Medicare provider-payment catalogs entirely. No client needed.

**Access (verified).** Four independent portals, all **PUF tier — no key, no
DUA, no bot filter**:

- [data.cms.gov](https://data.cms.gov) — 159 datasets. UUID-keyed REST at
  `data-api/v1/dataset/{uuid}/data`, JSON with all values as strings, `.csv`
  suffix for bulk. **Weaker than Socrata**: a `filter[State]=` query returned 0
  rows, and JSON paging silently caps at 6,500.
- [data.cms.gov/provider-data](https://data.cms.gov/provider-data) — 236 Care
  Compare datasets on a separate DKAN stack (OpenAPI 3.0.2, SQL endpoint).
- [openpaymentsdata.cms.gov](https://openpaymentsdata.cms.gov) — 74 datasets,
  same DKAN surface, so one parameterised client would serve both.
- [data.medicaid.gov](https://data.medicaid.gov) — 552 catalog items (~513 real;
  39 are `CoreSEt` dev/test artifacts), plus direct CSV at `download.medicaid.gov`.

The restricted tier is sharply separated and not worth pursuing: LDS files need a
DUA and cost $100–$7,000+; RIFs need a DUA *plus* CMS Privacy Board review via
ResDAC. Nothing above requires either.

**Data.** Overwhelmingly healthcare-industry structure — provider payments
(Physician & Other Practitioners, Inpatient/Outpatient, DME, Part D Prescribers),
quality ratings, Open Payments. The exceptions, none of them Medicare:

| Series | Shape | Access |
| --- | --- | --- |
| Medicaid applications + enrollment | 51 states × 109 months, 2013-09 → 2026-05 | **file** — 4.4 MB CSV |
| ACA Exchange effectuated enrollment | 52 states × 2016–2026 monthly, 6,588 rows | **API** |
| NHE by State of Residence | 50 states × 1991–2020 | **file** — ZIP of plain CSVs |

**Evaluation.** Medicare covers 65+ and SSDI-disabled, so it is **structurally
blind to the 25–54 cohort** where deaths of despair concentrate — the CDC leg
(§7) dominates it on mortality. The three above earn their place by seeing the
working-age population Medicare cannot: Medicaid *applications submitted* is a
responsive distress flow rather than an enrollment stock, and ACA *effectuated*
enrollment counts premiums actually paid, so it reads as affordability rather
than intent. NHE adds a state panel for health-cost burden.

Architecturally these need **no new client**: the two file sources fit the
WONDER/NVSR source-table pattern, and the ACA set is small enough (6,588 rows)
to fetch whole.

**Challenges.** The catalog's `temporal` field **lies about coverage** — it
reports the latest vintage, not the span (one dataset advertised a single month
while holding 2013–2026). Verify ranges by querying, never from metadata. NHE
state estimates stop at 2020 and are not being extended, so they splice to
nothing recent. CMS bulk URLs change annually.

**Value:** low–moderate — three useful series, no mortality gain over CDC.
**Effort:** low — no client, no auth, direct downloads.

---

## Priority

Guiding principle: **financial first, then demographic, then other** — and within
that, **easy sources before hard.** Financial (FRED, Tiingo, BLS, BIS) is **done**;
the sequence below is the working roadmap.

### Build sequence

1. **CDC** — health leg (deaths of despair, life expectancy). *(easy)* —
   **✅ done** (§7), and larger than scoped: Socrata turned out to be one of
   three routes, with WONDER and NVSR needing a stored-series table because
   neither has an API to call. **Voteview is now the front of the queue.**
2. **Voteview** — cheap half of elite cohesion (DW-NOMINATE overlap, bipartisan
   fraction). CSV, no auth, + a reduction pass. *(easy)*
3. **Clio-Infra** — historical backbone (real wages, inequality, life expectancy,
   ~1500→). Excel loader, no API. *(easy)*
4. **Polymarket** — **research first**: understand how its markets/prices work and
   sketch a couple of concrete scenarios where the event probabilities are useful;
   implement only if it proves easy. Pulled up from the Other tier (§3).

   → **Milestone:** with CDC + Voteview + Clio-Infra + Polymarket there is enough
   data to stand up the **trading analysis pipeline (yada)** and begin the **SDT
   work**.

5. **Trading infrastructure** — the next build-out (beyond this source list).
6. **LittleSis + Congress.gov** — potentially **original research**; do an
   **academic literature review first** to ground the method before building.
   Deferred — likely a while out.
7. **FRED/BLS overlap** — **deferred** (not worth solving yet; the human resolves
   it at selection today). Logged in [known-issues.md](../known-issues.md).
8. **Seshat** — separate cliodynamics project; whenever.

### By tier

| Tier | Source | Note |
| --- | --- | --- |
| **Financial** | FRED · Tiingo · BLS · BIS | **done** — clients + MCP tools + catalogs |
| **Financial** | FRED/BLS overlap | correctness task; yada-gated |
| **Demographic (SDT)** | CDC · Voteview | token-free/no-auth; health + cheap cohesion legs; fit the series model |
| **Demographic (SDT)** | Clio-Infra | historical backbone (§9); Excel loader, no API |
| **Demographic (SDT)** | Congress.gov | cosponsorship + Record text + policy→sector; key + graph/NLP — **lit review first** |
| **Other** | Polymarket | forward-looking event probabilities; **research first**, after Clio-Infra (§3) |
| **Other** | LittleSis | corporate/ownership graph; **lit review first** (§4) |
| **Other** | Seshat (cliodynamics) | separate research project (§6) |
| **Other** | CMS (Medicaid · ACA · NHE) | 3 series only; no client needed — **mostly skip** (§10) |

**Why this order.** The demographic easy-three (CDC, Voteview, Clio-Infra) are
thin loaders over the existing series model — a few days each — delivering the SDT
immiseration, cohesion, and historical legs. **Polymarket** is pulled up because
it is the one *forward-looking* signal (implied event probabilities) and, with the
easy three, rounds out enough data to stand up the trading pipeline and SDT; it
needs its own storage model, so it gets a research pass first. The graph/text
sources — **LittleSis** and **Congress.gov** — verge on original research and wait
on a literature review; **Seshat** is a separate project. See
[structural-demographic-theory.md](structural-demographic-theory.md) for how the
demographic sources combine.

> The numbered sections above are in discovery order and act as a reference
> catalog; this sequence is the actual roadmap.
