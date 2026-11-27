# Concept registry over the data sources

A source-neutral concept layer, so that a question asked conceptually
("homicide", "real wage", "government debt") resolves to the concrete series
that measure it across vendors — and, more importantly, reports which concepts
nothing measures yet.

**Spans:** meida (owns the registry and serves it) and yada (consumes it; owns
the 58,227-node FRED concept layer that would eventually hang off it). The
near-term step in §3 spans neither — it is a change to one gitignored script.

**Status: deferred, by decision 2026-11-27.** The same sequencing that defers
[bls-catalogue-over-mcp.md](bls-catalogue-over-mcp.md) applies here, and this
design is exactly the kind of thing it was written to defer: finish **document
search in yada's new MCP/UI
design** (no backfill work until it is done), then **FRED over yada's MCP** so
that pattern is fully worked through, then **work through the other data
stores** to get the full picture *before committing to a general shape*. A
registry with a selector contract, an independence key and an authority ranking
is a commitment to a general cross-source shape, made before the two steps that
produce the information those columns exist to encode. Six of the 35 nodes'
most important bindings are BLS, which is later still.

**Do §3 now; leave §4 until the sequence above completes.**

Everything below was verified live on **2026-11-27** against the local databases
and the repos, except where marked *(carried, unverified)* — those figures come
from the analysis pass that produced this doc and have **not** been
independently re-derived. Per the standing rule, re-check them before relying on
any of them.

| Phase | Owner | Work |
| --- | --- | --- |
| 0 | — | Roadmap sequence: document search, FRED over MCP, other stores |
| 1 | sefer | §3 — selector per node + a coverage check that exits non-zero |
| 2 | meida | Land the series-catalog quality-fields CR so FBI rows can load |
| 3 | meida | §4 — `concept_node` + `concept_binding`, seeded by hand |
| 4 | meida | One `concepts` MCP tool |
| 5 | yada | Route `search_fred` through `fred_subcategory.name_tsv` |
| 6 | meida / yada | Splice ledger; qualifier canonicalisation, if ever asked |

---

## 1. The inversion that makes this cheap

The instinct is to derive a concept layer **from** the catalogs — cluster the
titles, expand the synonyms, build a hierarchy. That is the expensive version,
and it answers the wrong question. A layer derived from the catalogs can only
describe series that exist.

The question actually being asked is **"which of my model variables is empty,
over which decades, and from which source"** — a question about things absent
from every index, which no embedding or full-text path can answer at all.

So the shape is a small **registry that the catalogs are joined to**, not a
layer derived from them. That inverts the cost: the registry is tens of rows,
hand-written, and the catalogs stay untouched.

## 2. What already exists

Three pieces, none connected to the others.

**A 35-node model-variable list, already written by hand.** `research/`
(gitignored) holds a Python literal of 35 nodes in 6 blocks — Outcome 5,
Immiseration 10, Elite 6, Enforcement 4, Politics 5, Fiscal 5 — each carrying
coverage spans, a status and a source note. **19 of the 35 have a best status of
`AVAILABLE`**: a source identified, nothing acquired. That list *is* the concept
vocabulary; it does not need authoring.

**A per-source concept slug in meida.** `series_catalog.concept` is `text`, is
indexed (`idx_sc_concept`), and is **100% populated** across all four loaded
sources — but it is a *per-source* vocabulary, not a shared one:

| source | rows | distinct concepts |
| --- | --- | --- |
| clio | 11,042 | 86 |
| cdc | 2,526 | 13 |
| clio_historical | 391 | 3 |
| voteview | 8 | 1 |

103 distinct labels over 13,967 rows, and they do not join. Exactly **three**
labels collide across sources, and all three are clio ↔ clio_historical — the
same vendor in two eras (`exchange_rates_to_uk_pound`, `labourers_real_wage`,
`number_of_days_lost_in_labour_disputes`). Between genuinely different vendors:
**zero collisions**. Meanwhile the semantic overlap is obvious and unexploited —
cdc `life_expectancy` against clio `life_expectancy_at_birth_total` /
`male_` / `female_`; cdc `homicide` against clio `homicide_rates`.

Note also that `despair_composite` and `cardiometabolic` are **own constructs**
stored as if they were CDC concepts. The registry gives them a legible home.

**A rich derived FRED concept layer in yada, with no reader.**
`yada_dev.fred_subcategory` is 58,227 rows over `fred_series`' 850,571, each
with an LLM-generated synonym expansion in `concepts`, a `centroid real[]`
embedding, and a generated `name_tsv` over `name || concepts` with a GIN index.
It is hierarchical (`parent_subcategory_id`, `depth`) and versioned
(`prompt_version`, `embed_model`, `split_version`). It is also **not in the
serving path**.

## 3. Do this first — one sitting, no schema

Keep the node list where it is, as the single source of truth. Add a **fifth
element to each tuple: a selector string**, empty for the unacquired nodes. Then
write a sibling `coverage_check.py`, roughly sixty lines, that:

1. resolves every non-empty selector against `series_catalog`,
2. compares `observation_start` / `observation_end` and row counts against the
   declared spans,
3. prints what disagrees, and **exits non-zero**,
4. regenerates the coverage chart from the same literal, so the image becomes a
   derived output rather than a parallel truth.

That delivers everything §4 would, except the external concept anchors, at the
cost of an hour — no table, no migration, no MCP tool, no new dependency — and
it leaves the artifact in the directory where its only reader already lives.

Record the two good ideas from §4 as one sentence each in the script's
docstring rather than as columns, so they are not lost:

- **A binding holds a selector, never a list of series ids.** Verified
  necessary: both `meida` and `yada_dev` have **only** `plpgsql` installed — no
  `postgres_fdw`, no `dblink`, and `pgvector` is not even among the available
  extensions — so a list of series ids spanning the two databases could never
  be joined. A stored query also absorbs new vendor series without a resync.
- **`origin` is not `source`.** FRED republishing BLS is one origin, not two
  confirmations. Two bindings sharing an origin are not independent
  corroboration.

## 4. The deferred design

Two tables in meida's Postgres, seeded by hand from the existing literal, and
one MCP tool. Roughly 35 nodes and 55–70 bindings — under 110 rows total.

```sql
CREATE TABLE concept_node (
    node_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    slug     text NOT NULL UNIQUE,   -- 'homicide_us'; readable, it is what an LLM sees
    label    text NOT NULL,
    block    text NOT NULL,          -- Outcome|Immiseration|Elite|Enforcement|Politics|Fiscal
    dcid     text,                   -- optional external anchor; NULL = own construct
    note     text NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE concept_binding (
    binding_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    node_id    uuid NOT NULL REFERENCES concept_node(node_id) ON DELETE CASCADE,
    kind       text NOT NULL,   -- 'measures' | 'proxy_for' | 'derived_from'
    source     text NOT NULL,   -- cdc|clio|voteview|fred|bls|fbi|...
    origin     text NOT NULL,   -- the independence key: who produced the number
    selector   jsonb NOT NULL,  -- HOW to find the series, never WHICH series
    era_start  int,
    era_end    int,
    status     text NOT NULL,   -- 'loaded' | 'partial' | 'available' | 'empty'
    rationale  text NOT NULL DEFAULT '',   -- required when kind = 'proxy_for'
    series_count    int,
    last_checked_at timestamptz,
    CONSTRAINT ck_cb_kind   CHECK (kind IN ('measures','proxy_for','derived_from')),
    CONSTRAINT ck_cb_status CHECK (status IN ('loaded','partial','available','empty')),
    CONSTRAINT ck_cb_rationale CHECK (kind <> 'proxy_for' OR length(rationale) > 0)
);
CREATE INDEX idx_cb_node     ON concept_binding (node_id);
CREATE INDEX idx_cb_selector ON concept_binding USING gin (selector);
CREATE INDEX idx_cb_origin   ON concept_binding (origin);
```

A selector names a source and a filter, not series ids:

```json
{"db": "meida", "source": "clio", "concept": "homicide_rates", "facets": {"ccode": 840}}
{"mcp": "yada", "tool": "search_fred", "series_id": "FYFSGDA188S"}
```

Three decisions carry the weight:

- **Qualifiers never enter concept identity**, and nothing is canonicalised.
  Sex, age, geography and measure basis stay in `series_catalog.facets`. Because
  bindings carry selectors, clio's three life-expectancy slugs become three
  bindings with different facet filters on one node, and the CDC-puts-sex-in-
  facets / clio-folds-it-into-the-slug mismatch dissolves instead of needing a
  normalisation. Putting a qualifier into a key would bake the geography
  inconsistency into every downstream reference; this is the one decision that
  is expensive to reverse.
- **`mirror_of` becomes the `origin` column**, not an edge or a table. The
  general case (same concept, different provider) is subsumed. The exact-twin
  case (`UNRATE` ↔ `LNS14000000` being literally the same series) cannot be
  built yet anyway — `fred_series` has no source or release field, and BLS is
  loaded nowhere. See [known-issues.md](../known-issues.md) for the
  value-fingerprint recipe to use when BLS lands.
- **Population is by hand.** A text crosswalk from meida's 103 slugs to FRED's
  derived nodes was measured at 24 matches, of which roughly 6–8 are correct
  *(carried, unverified)*; `inflation` resolved to thousands of nodes. A
  crosswalk is a candidate generator, not a population method.

## 5. Prior art — adopt, do not invent

**Google Data Commons' `StatisticalVariable` is this product, built.** The model
is `populationType` × `measuredProperty` × `statType` plus constraint
properties, and the definitions are not API-only: `datacommonsorg/schema` is
**Apache-2.0**, 25 MB, with **252 files under `stat_vars/`**. A grammar of a few
hundred measured properties generates the whole vocabulary, and
`measurementDenominator` means per-capita variants derive rather than being
minted as unrelated concepts. Google also ships
`datacommonsorg/agent-toolkit` (Apache-2.0), whose `datacommons-mcp` server
exposes `search_indicators`, `get_variable_metadata` and `get_observations` —
i.e. the deliverable, already written.

Take from it: **hand-type the dozen-odd DCIDs** for the Immiseration, Outcome
and Fiscal nodes into the `dcid` column, and leave it **NULL** for Elite,
Enforcement and Politics, where Data Commons has no coverage — no Polity, no
Voteview, no DW-NOMINATE *(carried, unverified)*. A NULL `dcid` then means
"this is my own construct", which is exactly the discriminator
`despair_composite` currently lacks. Do **not** load the vocabulary; a table of
borrowed definitions with no reader is this project's characteristic failure.

Before building anything, run `datacommons-mcp` beside meida's own server and
ask it the questions you want answered. It is the cheapest possible test of
whether a concept layer earns its keep.

**SDMX is the wrong layer** — worth stating because it is the obvious candidate.
Its cross-domain concept scheme holds 229 concepts and contains no subject
matter: searching the ids for UNEMPL, CPI, GDP, WAGE, MORTAL, DEBT, HOMICID and
the rest returns one hit in total *(carried, unverified)*. BIS's own scheme is
the same shape. SDMX gives you a **qualifier** vocabulary and the
dimension/measure/attribute frame; take its codelists (`CL_SEX`, `CL_AGE`,
`CL_FREQ`) only if and when a qualifier dimension is actually canonicalised.

**OMOP** is the best-engineered example of concept identity anywhere, but its
vocabularies are not redistributable and hold nothing macro. If a merge
mechanism is ever needed, borrow three column names — `valid_from`, `valid_to`,
`invalid_reason` — plus a `same_as` redirect, and nothing else.

**STW Thesaurus** (7,328 descriptors, CC BY 4.0) is a candidate replacement for
yada's LLM-generated synonym field in the economic domain, once that layer is in
the serving path and synonym quality becomes the limiting factor.

## 6. What not to build

- **A second exhaustive classification.** 58,227 nodes over 850,571 FRED series
  already exist and have no reader. The measured defect in the one that exists
  is precision, not coverage.
- **Any change to `series_catalog`.** No `concept_id` column, no FK, no
  tsvector. A concept node has no `retrieval` block, and the registry must
  reference FRED and BLS series that will never be rows there.
- **A graph database, RDF or SPARQL.** Thirty-five nodes. Postgres is already
  overkill.
- **A custom Data Commons instance.** Containers plus Cloud SQL to re-host data
  already owned.
- **An embedding or synonym layer for meida's 103 slugs.** The entire vocabulary
  fits in a tool description. meida has no embedding dependency at all, and
  adding one for 35 nodes is absurd.
- **A query-time write path for demand-driven nodes.** Concurrent sessions
  create duplicates, so the merge problem arrives on day one. New nodes arrive
  by reviewed insert.
- **`postgres_fdw`, `dblink` or `pgvector`.** The selector design makes all
  three unnecessary, and installing an extension is a superuser act not worth
  taking for 35 rows.

## 7. Open questions

- **Does anything actually ask a cross-source concept question?** Of the 35
  nodes, only about 9 need cross-source resolution at all (the 8 multi-span
  nodes plus Government debt). Revealed demand to date is 16 cached FRED series
  and two report fixtures *(carried, unverified)*. If the answer stays "nine
  rows, no queries", §3 is the whole project and §4 never happens.
- **The splice method is still undecided.** Era bounds live on the binding, so a
  `concept_splice` table is additive whenever the Clio-to-contemporary join
  method is documented. Until then "here are the two series to splice" is the
  most the registry can say.
- **Does a node key reopen `search_all`?** yada's document-MCP design defers
  cross-store search on the ground that the cross-store case takes no
  store-specific filters. A concept node key is precisely such a shared filter,
  so its existence invalidates that premise. Decide both deliberately when
  document search ships — do not let a decision made under the opposite
  assumption stand by default.

## 8. Check this first on return

Three things that were true on 2026-11-27 and will mislead if assumed still
true.

**The node list is stale, and its own doc says so.** The research note instructs
"Regenerate `coverage_chart.py` — … starts at 1985 rather than 2000". The script
still carries `2000`. Timestamps show the note was edited at 18:09 on 20
September, **two hours after** the script at 15:56 — the instruction was written
and never run, and that was 68 days before this doc. Any selector transcribed
from that table needs checking against live data first: of the Clio rows spot-
checked here, `total_gross_central_government_debt` **is not a concept that
exists** — the actual slug is
`total_gross_central_government_debt_as_a_percentage_of_gdp`.

**The Enforcement block is not actually empty.** The same note records the FBI
client as *built*, monthly from 1985, with 1,150 catalog entries written for
non-fatal crime alone. There are **no `fbi` rows in `series_catalog`** — the
entries sit in gitignored YAML, blocked on the series-catalog quality-fields
work. So at least three of the 19 "available" nodes have data that exists and
cannot be reached, and a drift check against `series_catalog` would report "still
empty" and be wrong. **Landing that CR is worth more than this registry.**

**Verify a facet filter before writing it into a selector.** The first draft of
this design specified a `canonical_basis` of `rate_type=crude` for the CDC
homicide binding, to stop the age-adjusted rate silently entering a Clio join.
That filter matches **zero rows**: there is exactly one CDC homicide series,
`cdc/homicide/wonder/national/age_adjusted`, its facet key is `measure` rather
than `rate_type`, and no crude variant is stored at all. The field had been
transcribed from a sentence in the research note that the database contradicts.
A rate-basis mismatch is the one error class here that yields a *wrong number*
rather than a missing one, so it still needs solving — but it cannot be solved
by a filter over data that is not there.
