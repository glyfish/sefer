# yada — FRED and ETF discovery in Postgres

The schema for moving the `fred` and `etf` stores out of Chroma. These are the two that
**leave** — `github` and `research_library` stay, per `yada-document-mcp-design.md`.

Designed 2026-11-01. Every number here was measured against the live stores on that date;
the probes are named where a figure comes from one. **For review — no migration written.**

---

## 1. Why these two leave

Not the argument that kept the FBI catalogue out of a document store. That one is specific:
the thing you rank on — agency size, real coverage — is *not in the registry*, so no
retrieval method can surface it and discovery has to be measurement
(`mcp-integration.md` §2). FRED and ETF are the opposite: everything needed to choose is
already in the metadata.

The argument here is that **both stores are relational tables wearing a vector store**, and
the vector store is actively hiding a defect in them.

| | fred | etf |
| --- | --- | --- |
| rows | 145,679 | 36,475 |
| real entities | 123,119 series | 36,475 tickers / **17,533 funds** |
| duplicated | **12,480 series on >1 row** | **8,134 funds on >1 ticker** |
| what varies across duplicates | `category_path` 100%, `category_id` 22% | `exchange` 94.6%, `currency` 23.2% |

A fund like `VANGUARD SCOTTSDAL` sits on 17 tickers. Embeddings rank near-identical rows
near-identically, so duplicates cluster at the top and a "top 5" can be one fund five times.
`DISTINCT ON` fixes it in SQL; nothing fixes it in Chroma short of post-hoc deduplication,
which cannot know which row to keep. This corroborates the suspicion in
`mcp-integration.md` §5 — *"67% of its 36,475 documents are German regional venue
duplicates"* — from the other direction.

Three more, all structural:

- **The real queries are range predicates.** `observation_start` has 1,586 distinct values.
  *"Back to the fifties"* is `WHERE observation_start <= '1959-12-31'`, which Chroma cannot
  express — the loader already writes `observation_start_int` mirror fields solely to work
  around that. Postgres makes the workaround unnecessary.
- **The high-cardinality fields are identifiers.** `series_id` 123,119, `ticker` 36,475.
  Looked up, not embedded.
- **The vocabulary stops being a snapshot.** `SELECT DISTINCT frequency_class FROM
  fred_series` *is* the vocabulary. No `document_vocabulary_combination` rows, no `rebuild`,
  no `is_stale`, no `built_at` revalidation. The staleness problem wired shut on 2026-10-31
  for the two remaining stores never arises for these two.

**Cost note.** These stores were already excluded from the 83M-token re-index estimate in
`document-search-tasks.md` §3.0 because they were going to Postgres. Going FTS rather than
pgvector means they need **no embedding at all** — not now, and not at the next
embedding-model change.

---

## 2. The interface decision: bound parameters, not generated SQL

**The model never writes SQL.** It fills typed parameters; the server owns the statement.
Same shape as `search_code(query, repo, ext)`.

Security is the obvious objection and the least interesting — a read-only role and a
statement timeout settle it. The real reason is that text-to-SQL reintroduces the failure
the resolution layer exists to remove. A model writing `WHERE frequency = 'quarterly'`
against a stored `'Quarterly'` gets zero rows and reports *"no such series"*. With bound
parameters that is a resolution with an `unresolvable_filter` outcome and a list of what
exists; with generated SQL it is indistinguishable from a legitimately empty result.

It would also walk back into the duplication. `DISTINCT ON (series_id)` is in every
statement below because 12,480 series sit on multiple rows; a model writing ad-hoc SQL
omits it and hands back the same series five times.

Goose fills the parameters from the request directly, as it already does for `search_code`.
No extraction agent in between — `llm_filter_extractor.py` exists because the old
orchestrator had to parse prose itself, which is among the things Goose's routing replaces.

---

## 3. The two traps a naive schema walks into

### 3.1 `frequency` has 41 spellings for ~8 frequencies

Among series still running: `Quarterly` 13,338, but also `Quarterly, End of Quarter` 817
and `Quarterly, End of Period` 292. An exact match on `'Quarterly'` silently drops 1,109
series.

So **`frequency_class` is a stored column**, derived at load from the leading word, with the
raw `frequency` kept beside it for display. Same treatment as `ext` normalisation — resolved
once at write time, not guessed at query time.

### 3.2 "Currently relevant" must be measured in periods, not days

This is the highest-value filter in the set, because **two-thirds of the store is a
discontinued series** — only 32.7% of the 123,119 have an `observation_end` in 2025 or later.

But a flat date cutoff is wrong in both directions, and catastrophically in one:

| | series | end 2025+ | end 2024 |
| --- | --- | --- | --- |
| **annual** | **56,170** | **176** | **22,200** |
| monthly | 32,721 | 22,008 | 443 |
| quarterly | 28,583 | 14,447 | 426 |

An annual series reporting 2024 is exactly on schedule. `observation_end >= '2025-01-01'`
would mark **22,200 perfectly current annual series as dead** — 99.7% of the largest class
in the store, which is 46% of all series. Meanwhile it wrongly keeps a daily series that
stopped in January 2025 and has been dead for eleven months.

A second reason no model-supplied date works: the store's own latest data ends in 2025 while
today is 2026, so `now() - interval '6 months'` returns almost nothing. A model asked to turn
"current" into a date reaches for today's and reports the empty result as *"no series found"*.

**The rule, computed at load into a stored boolean:**

> `currently_relevant` = `observation_end >= p95(observation_end within frequency_class)
> − 2 × period_days(frequency_class)`

| class | series | p95 end | derived cutoff | currently relevant |
| --- | --- | --- | --- | --- |
| annual | 56,170 | 2024-01-01 | 2022-01-01 | 31,128 (55.4%) |
| monthly | 32,721 | 2025-11-01 | 2025-09-02 | 13,427 (41.0%) |
| quarterly | 28,583 | 2025-07-01 | 2024-12-31 | 14,447 (50.5%) |
| daily | 2,563 | 2026-01-02 | 2025-12-31 | 1,406 (54.9%) |
| weekly | 1,871 | 2025-12-31 | 2025-12-17 | 916 (49.0%) |
| semiannual | 877 | 2025-01-01 | 2024-01-03 | 629 (71.7%) |
| | | | **total** | **61,971 (50.3%)** |

Every class lands in a 41–72% band; that spread is the evidence the calibration works, against
annual's 0.3% under a flat cutoff.

- **p95, not max** — projections skew the tail. Annual's max is 2030-01-01 against a p95 of
  2024-01-01, so a max-anchored cutoff would sit at 2028 and return nothing.
- **Two periods** — one for ordinary publication lag, one for the store's own staleness.
- **Self-calibrating.** Re-derived on every load, so a fresher store moves every cutoff
  together and the definition never needs revisiting by hand.

**Open:** 318 series (0.26%) have a frequency string the classifier does not parse, and land
at 5% currently-relevant. Too few to matter for retrieval, enough to be worth one look.

---

## 4. The tables

### 4.1 FRED — series, categories, membership

`series_id` is **not** unique in the store: 145,679 rows for 123,119 series, because a series
appears once per category it belongs to. The split is therefore forced, not stylistic.

```sql
CREATE TABLE fred_series (
    series_id            text PRIMARY KEY,
    series_title         text NOT NULL,
    units                text,
    frequency            text,              -- raw, 41 spellings, for display
    frequency_class      text,              -- derived: daily|weekly|monthly|...  (§3.1)
    seasonal_adjustment  text,
    observation_start    date,
    observation_end      date,
    last_updated         timestamptz,
    popularity           integer,
    currently_relevant   boolean NOT NULL,  -- derived per §3.2
    title_tsv            tsvector GENERATED ALWAYS AS
                             (to_tsvector('english', series_title)) STORED
);

CREATE INDEX ON fred_series USING GIN (title_tsv);
CREATE INDEX ON fred_series (frequency_class, observation_start);
CREATE INDEX ON fred_series (currently_relevant) WHERE currently_relevant;
CREATE INDEX ON fred_series (observation_start);

CREATE TABLE fred_category (
    category_id    integer PRIMARY KEY,
    category_name  text NOT NULL,           -- leaf_name is identical on all 145,679 rows
    category_path  text
);

CREATE TABLE fred_series_category (
    series_id    text    REFERENCES fred_series(series_id) ON DELETE CASCADE,
    category_id  integer REFERENCES fred_category(category_id) ON DELETE CASCADE,
    PRIMARY KEY (series_id, category_id)
);
CREATE INDEX ON fred_series_category (category_id);
```

**`leaf_name` is dropped.** Measured: it differs from `category_name` on **0 of 145,679
rows**. Carrying both is the two-spellings-of-one-fact problem that cost the Goose
account/repo table 15 wrong rows.

**`category_path` lives on the category, not the series.** It varies across 100% of
duplicated series precisely because it is a property of the category.

### 4.2 ETF — funds and listings

`ticker` is a true primary key (36,475 distinct over 36,475 rows). But 8,134 of 17,533 names
appear on more than one ticker, and what varies is overwhelmingly the venue — `exchange`
94.6%, `currency` 23.2%. That is one fund cross-listed, and it is what makes a search return
the same fund seventeen times.

```sql
CREATE TABLE etf_fund (
    fund_id         bigserial PRIMARY KEY,
    name            text NOT NULL,
    family          text,                   -- 317 distinct, 74.6% coverage
    category_group  text,                   -- 43 distinct, 69.7%
    category        text,                   -- 51 distinct, 62.4%
    summary         text,
    name_tsv        tsvector GENERATED ALWAYS AS
                        (to_tsvector('english', name || ' ' || coalesce(summary, ''))) STORED
);
CREATE INDEX ON etf_fund USING GIN (name_tsv);
CREATE INDEX ON etf_fund (family);
CREATE INDEX ON etf_fund (category_group, category);

CREATE TABLE etf_listing (
    ticker     text PRIMARY KEY,
    fund_id    bigint REFERENCES etf_fund(fund_id) ON DELETE CASCADE,
    exchange   text,                        -- 50 distinct, 99.9% coverage
    currency   text,                        -- 24 distinct, 99.7%
    isin       text,                        -- 3,663 distinct, 21.7% -- nullable, not a key
    is_primary boolean NOT NULL DEFAULT false
);
CREATE INDEX ON etf_listing (fund_id);
CREATE INDEX ON etf_listing (exchange);
```

**`isin` is not a key.** 21.7% coverage. It is an attribute to display, never to join on.

### 4.2a The USD default, and what it costs

The store is overwhelmingly European: **EUR is 76.4% of listings**, and the five German
regional venues (`BER`, `MUN`, `DUS`, `FRA`, `HAM`) account for **22,984 listings, 63% of
the store**, all EUR. That matches `mcp-integration.md` §5's "67% German regional venue
duplicates" almost exactly.

Defaulting search to USD therefore does two very different things at once:

| | |
| --- | --- |
| **as deduplication** | multi-listed funds fall from **8,134 to 177** (4.2%) — 95.8% of kept funds have exactly one listing |
| **as a filter** | **15,203 of 19,455 funds (78.1%) are hidden** — they have no USD listing at all |

The hidden funds are **not** duplicates of the kept ones. A fund cross-listed in Berlin
keeps its USD listing and survives; the 15,203 are Europe-only funds, mostly UCITS, with no
US line at all.

**So the default is correct exactly when it matches fetchability, and that has not been
checked.** If Tiingo does not carry a Europe-only fund, surfacing its ticker produces a row
nothing can fetch — worse than omitting it. If Tiingo does carry it, the default is hiding
three-quarters of the universe. One cross-check against meida's coverage decides it, and
decides `is_primary` with it.

**It must never be silent.** Hiding 15,203 real funds without saying so is the
confident-wrong-answer shape this project keeps removing: a request for a real UCITS fund
returns *"no such fund"*. It belongs in `filters_applied`, with the excluded count, the way
the document tools already report a narrowed search:

```
filters_applied: { currency: "USD (default)" }
detail: "4,252 funds match. 15,203 more exist only on non-USD venues, excluded by
         the default -- pass currency=null to include them."
```

**"USD" and "US exchange" are not the same filter.** `EBS` is SIX Swiss and 39% of its
1,461 listings are USD-denominated. The US venues are `PCX` (NYSE Arca, 1,702), `BTS` (484)
and the Nasdaq codes in the tail. Whichever becomes the default should be an explicit
enumerated set, not inferred from currency.

### 4.2b Tiingo coverage, measured — and it inverts this section

**Checked 2026-11-01** against Tiingo's published `supported_tickers.csv` (109,176 rows,
refreshed that morning), matched on exact ticker with currency agreement required.

**Match method matters.** Stripping the venue suffix (`003D.BE` -> `003D`) and matching is
**88% false positives**: of 2,421 such matches, 2,135 had a disagreeing `priceCurrency`.
Exact matching is clean -- 2,530 agree, 1 does not. Only exact matches count below.

| | funds |
| --- | --- |
| in the store | 19,455 |
| **fetchable from Tiingo** | **2,618 (13.5%)** |
| with a USD listing | 4,252 |

**86.5% of the ETF store cannot be fetched at all.** Not filtered out -- unreachable. Every
one of those is a search result that leads nowhere.

And the gap runs the other way too. Tiingo lists **9,885 ETFs, 7,751 still trading**, of
which **5,640 (72.8%) are absent from our store** -- 4,885 of them USD-denominated. So the
store is simultaneously **six times too large** and **missing most of what is usable**.

Two questions this settles outright:

- **`is_primary` is not a real problem.** Of the 2,618 fetchable funds, **2,592 have exactly
  one fetchable listing**. Only 26 (1.0%) need a tiebreak, and a fixed venue preference
  (`PCX` > `BTS` > `NMS` > ...) covers them.
- **The venue default is right, and nearly free.** Coverage and venue are different axes --
  coverage is *can this be fetched*, venue is *which listing you want* -- and both belong.
  Measured on exact matches: of **2,462 fetchable funds, 2,456 (99.8%) have a fetchable
  US-venue listing** *by FinanceDatabase's exchange code*. The other 6 are not foreign and
  not unusable -- they are **US OTC listings whose exchange our source left blank**:

  | fund | our exchange | Tiingo |
  | --- | --- | --- |
  | Vanguard FTSE Developed (`VFDEF`) | *(blank)* | OTCMKTS, USD, ETF, trading to 2026-10-30 |
  | Vanguard S&P 500 UCITS (`VGFPF`) | *(blank)* | OTCMKTS, USD, ETF |
  | Vanguard USD Corporate (`VNGCF`) | *(blank)* | OTCMKTS, USD, ETF |
  | WisdomTree US Quality Div (`WDSSF`) | *(blank)* | PINK, USD, ETF |
  | WisdomTree Europe Equity (`WSDMF`) | *(blank)* | PINK, USD, ETF |
  | ZKB Gold ETF (`ZKBHF`) | *(blank)* | PINK, USD, ETF |

  Irish-domiciled UCITS funds with US over-the-counter lines. Fetchable, currently trading,
  USD. **So `is_us_venue` must be derived from Tiingo's `exchange`, not FinanceDatabase's.**
  Tiingo populates it for every covered ticker because it is the venue they trade it on;
  FinanceDatabase leaves it blank on 27 listings. Sourced that way the US-venue default
  hides **zero** fetchable funds.

  This is the second field where Tiingo's data beats the one this design had assigned to
  FinanceDatabase -- which argues for option B/C below rather than A.

  It also all but finishes `is_primary`: only **4** fetchable funds have more than one
  fetchable listing.

  Currency is the weaker proxy and should not be the filter: a USD default hides 16, and
  `EBS` (SIX Swiss) carries USD-denominated listings. Default on **venue**, keep coverage as
  the separate constraint, and report both in `filters_applied`.

**Venue codes are spelled differently by the two sources**, which is the
two-spellings-of-one-fact hazard this project keeps paying for. Tiingo writes `NYSE ARCA`,
`BATS`, `NASDAQ`, `PINK`; FinanceDatabase writes `PCX`, `BTS`, `NMS`/`NGM`, `PNK`. Normalise
once at load into an `is_us_venue` boolean on `etf_listing` -- never a code list repeated at
each query site, which is how the two spellings drift apart.

**The consequence for §4.2: FinanceDatabase is the wrong spine.** Tiingo's supported-ticker
list is the fetchability constraint, is refreshed daily, costs one unauthenticated request,
and is authoritative for what yada can use. FinanceDatabase becomes an *enrichment* join,
not the source of truth.

The catch is that Tiingo's bulk file carries **no name and no description** -- only ticker,
exchange, assetType, currency and date range. So the 5,640 missing ETFs are fetchable but
**undiscoverable**: there is nothing to run FTS against. Their names come from
`get_meta(ticker)`, one call each.

That is exactly the **probe catalogue** shape from `mcp-integration.md` §2 -- the thing you
need is not in the bulk export, so you measure it once and keep it. The ETF catalogue turns
out to be a *mirror* catalogue for the 2,618 FinanceDatabase matches and a *probe* catalogue
for the 5,640, which is the distinction that file warned against conflating.

**Three options, for §8:**

| | fetchable funds | description coverage | new work |
| --- | --- | --- | --- |
| **A** keep FinanceDatabase spine, filter to fetchable | 2,618 | complete | none |
| **B** Tiingo spine + FinanceDatabase enrichment | ~8,258 | 2,618 of them | load one CSV |
| **C** B, plus a one-time `get_meta` probe of the 5,640 | ~8,258 | complete | 5,640 rate-limited calls, once |

**A** is defensible and ships now. **C** is where this should end up: it triples the usable
universe and the probe is a one-off against a file that refreshes daily thereafter.

**`is_primary` is the open question in this file.** Searches should return one row per fund,
and the fetch needs a ticker. Which listing? Candidates: the US venue, the one whose currency
matches the fund's domicile, the one Tiingo actually carries. **The last is the only one that
cannot produce a ticker nothing can fetch** — and it needs a cross-check against meida's
coverage, which this design has not done. Until then, `is_primary` is unset and search groups
by `fund_id`, returning every listing in a nested array for the picker (§6) to choose from.

### 4.3 Grouping the name collisions

8,134 duplicated names, but **`family` differs on 251 of them and `category` on 888** — so
`name` alone is not a safe grouping key. Same name, different family is a different fund.
Group on `(name, family, category_group, category)` with nulls normalised, and record the
collision count at load so a regression shows up as a number rather than as a duplicate in
a search result.

---

## 5. The queries the tools issue

### `search_fred_series`

*"Quarterly unemployment data going back to the fifties that's still being updated"*

```sql
SELECT DISTINCT ON (s.series_id)
       s.series_id, s.series_title, s.units, s.frequency,
       s.observation_start, s.observation_end, s.popularity,
       ts_rank(s.title_tsv, q) AS rank
FROM   fred_series s, websearch_to_tsquery('english', $1) q
WHERE  s.title_tsv @@ q
  AND  ($2::text IS NULL OR s.frequency_class    = $2)
  AND  ($3::date IS NULL OR s.observation_start <= $3)
  AND  (NOT $4::boolean   OR s.currently_relevant)
ORDER  BY s.series_id, rank DESC, s.popularity DESC
LIMIT  $5;
```

`DISTINCT ON (series_id)` is what stops one series arriving once per category.
`popularity` as the tiebreak is FRED's own usage signal — the nearest thing to "the one you
probably meant".

### `describe_fred_series`

Facets off real `GROUP BY`s, not a cached table — the same shape `describe_code` returns, with
nothing to keep in step:

```sql
SELECT frequency_class, count(*) FROM fred_series GROUP BY 1 ORDER BY 2 DESC;
```

### `search_etf`

One row per fund, listings nested:

```sql
SELECT f.fund_id, f.name, f.family, f.category_group, f.category,
       ts_rank(f.name_tsv, q) AS rank,
       jsonb_agg(jsonb_build_object('ticker', l.ticker, 'exchange', l.exchange,
                                    'currency', l.currency) ORDER BY l.ticker) AS listings
FROM   etf_fund f
JOIN   etf_listing l USING (fund_id),
       websearch_to_tsquery('english', $1) q
WHERE  f.name_tsv @@ q
  AND  ($2::text IS NULL OR l.exchange = $2)
GROUP  BY f.fund_id, rank
ORDER  BY rank DESC
LIMIT  $3;
```

---

## 6. Where the human goes

`§5.3` of the migration plan names the residual risk this schema does not remove:

> **Selection**, not invention: the model may pick the wrong series from search results.

Fabrication is already blocked — `create_time_series_report` dereferences every `cache_id`
and refuses invented ones. What it cannot catch is a *real* series that is the wrong one, and
with 123,119 to choose from and titles that differ by one word, that is the live failure mode.
So the chain is:

```
search  ->  [human picks]  ->  fetch  ->  create report  ->  plot
```

The picker is already §5.5 step 3 of the migration plan. This is the **third** thing to land
on the MCP App path, after display control / image bytes (§5.4) and the backend cost total
(`yada-todo.md` §4) — worth weighing when the plot refactor (`yada-todo.md` §3) is picked up.

---

## 7. FTS now, pgvector only if measured

Postgres full-text search is lexical: it stems and matches words. It will find *"consumer
sentiment"* in a title containing those stems; it will **not** find *"how optimistic
households feel"*. An embedding would.

Start FTS-only on both, because it is free, needs no API key, and never goes stale against a
model version. FRED titles are formulaic — *"Real Gross Domestic Product"*, *"Unemployment
Rate in Tennessee"* — and someone searching already has the vocabulary. The ETF `summary`
column is free prose and is where semantic search has something to offer.

Adding pgvector later is an `ALTER TABLE`. It does not invalidate anything here, so there is
nothing to decide now that cannot be decided by measurement later.

---

## 8. Open questions for review

1. ~~Tiingo coverage decides the USD default and `is_primary`.~~ **Measured 2026-11-01,
   §4.2b.** Both dissolve: `is_primary` matters for 26 funds, and coverage beats currency as
   the filter. What replaced them is bigger — **86.5% of the ETF store is unfetchable, and
   5,640 actively-traded Tiingo ETFs are missing from it.** The live decision is now
   **A, B or C in §4.2b**: whether Tiingo's supported-ticker list becomes the spine, and
   whether the 5,640 get a one-time `get_meta` probe to make them discoverable.
2. **Keep the Chroma stores during the transition, or cut over?** Keeping both means two
   answers to the same question, which is the failure mode this project keeps removing.
3. **One table per source, or a shared `series_catalogue`?** `mcp-integration.md` §5 asks the
   same thing about meida's catalogues and leaves it open. Deciding it in two repos
   independently is how they diverge.
4. **The 318 unparsed `frequency` strings** (§3.2).
