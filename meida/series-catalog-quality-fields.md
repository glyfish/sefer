# Change Request — quality and size fields in `series_catalog`

**Status:** proposed · **Spans:** meida (schema, loader, exporter, MCP tools) ·
**Blocks:** loading the FBI catalogue

`series_catalog` can say *which series exist* and *what fetches them*. It cannot
say **how big** a series' subject is or **how completely** it was reported. For
every source so far that gap was invisible, because the whole catalogue was worth
having. The FBI is the first source where it is not: 19,636 agencies are
addressable and only a few dozen are usable, and the two facts that decide which
are exactly the two the table cannot hold.

This CR adds them, and says what it deliberately does not add.

---

## 1. Why now

Loading the FBI catalogue (3,886 entries) is otherwise a one-call operation — the
loader is source-generic and every entry carries a `retrieval` block. But the
entries also carry measurements that cost one API call each to obtain, and today
`load_catalog._row()` would discard all of them silently.

Measured across the 3,886 entries:

| Field | Present on | Min | Median | Max |
| --- | --- | --- | --- | --- |
| `coverage_mean_percent` | 3,876 | 60.8 | **95.7** | 100.0 |
| `coverage_min_percent` | 3,876 | 0.0 | **29.2** | 100.0 |
| `participated_population` | 2,736 (arrests only) | 0 | 851,967 | 66,676,608 |
| `filings` | 2,736 (arrests only) | 1 | 104 | 105 |
| `arrests_total` | 2,736 (arrests only) | 0 | 2,645 | 66,217,646 |

No other loaded source carries anything comparable, so every column below is
nullable and every existing row is unaffected.

---

## 2. The distinction this rests on

`facets` already holds numbers (`ccode: 156`, `border_start: 1880`), so the
precedent exists — but everything in `facets` today is a **coordinate**: part of
the series' identity, and the material the `retrieval` block is built from.

These fields are not coordinates. Nobody asks for *the series whose coverage is
87.3%*; they ask for *agencies above 90%*, and for *the hundred largest*. Those
are range and sort operations on quality attributes, which want a btree, not GIN
containment. Keeping them out of `facets` also keeps `facets` meaning one thing.

---

## 3. What to add

Two typed columns, because they are what you filter and sort on and because they
generalise beyond the FBI, plus one JSONB for whatever else a source measures.

```sql
ALTER TABLE series_catalog
  ADD COLUMN population       bigint,
  ADD COLUMN coverage_percent numeric(5,2),
  ADD COLUMN measures         jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE INDEX ix_series_catalog_population       ON series_catalog (population);
CREATE INDEX ix_series_catalog_coverage_percent ON series_catalog (coverage_percent);
```

**`population`** — the size of the thing the series measures. For the FBI this is
the agency's **resident** population. It is the answer to *"the binding constraint
is size, not availability"*, and it generalises to any source with a denominator.

**`coverage_percent`** — how completely the window was reported, as a headline
figure. For the FBI, `coverage_mean_percent`. It is the answer to *"addressable is
not filed"*.

**`measures`** — source-specific measurements that do not generalise, kept rather
than discarded and available without another migration. For the FBI:
`coverage_min_percent`, `filings`, `arrests_total`.

New alembic revision, `down_revision = "8f31c0a4e7d2"`. The database is at that
head. Downgrade drops the three columns and both indexes.

---

## 4. The exporter change this depends on

**`participated_population` is not `population`.** A CDE response carries both —
for San Francisco PD they happen to be equal at 802,856, but for California they
are 39,431,263 residents against 39,392,699 participating. Coverage is
`100 × participated / population`, so the two are only equal at full coverage.

The catalogue currently emits `participated_population` and only on the 2,736
arrest entries. To populate `population` meaningfully the FBI exporter must emit
the **resident** figure, on offence entries as well. Without that change,
`population` lands 70% filled and holding the wrong number, which is worse than
leaving it null.

**Do not substitute Census population.** The response's own figure is the
denominator the API's rates divide by; ranking on a different one makes selection
and rate silently inconsistent.

---

## 5. Why one coverage column and not two

`coverage_mean_percent` and `coverage_min_percent` say different things — median
95.7 against 29.2 — and the minimum is what reveals that a well-covered series has
a bad patch. Both are worth keeping.

The mean is promoted because it is the one you filter a candidate list on
(*"agencies above 90%"*). The minimum goes in `measures` because it is a caveat you
read once you have chosen, not a selector you sort by. If querying on the minimum
turns out to be common, promote it later — the JSONB keeps that option open at the
cost of one migration.

---

## 6. Deliberately not added

- **`blank_month_notices`** — a caveat about the *observations*. It belongs in what
  the fetch returns, not in discovery. The fetch path must carry it (a run of
  unfiled months becoming nulls with no explanation is its own bug), but not here.
- **`sources`** — provenance. No query value in a discovery index.
- **`arrests_total`** as a column — source-specific magnitude with no cross-source
  meaning; a price series has no "total". It goes in `measures`.

---

## 7. Work items

| # | File | Change |
| --- | --- | --- |
| 1 | `alembic/versions/<new>.py` | The migration in §3, `down_revision = "8f31c0a4e7d2"` |
| 2 | `notebooks/fbi/utils/catalog.py` | Emit resident `population` on every entry, offences included (§4) |
| 3 | `db_import/load_catalog.py` | `_row()` maps `population`, `coverage_percent` ← `coverage_mean_percent`, and gathers the remaining measured fields into `measures` |
| 4 | `mcp_server/series_catalog_models.py` | Add the three fields to `CatalogEntry`, with descriptions saying what they mean and that they may be null |
| 5 | `mcp_server/series_catalog.py` | `search()` gains `min_population`, `min_coverage` filters and an `order_by` accepting `population DESC` — otherwise the columns are stored and unusable, which is the whole point of adding them |
| 6 | `mcp_server/server.py` | Document the new arguments on the `series_catalog_search` tool |

Item 5 is the one that makes the rest worth doing. `search()` currently orders by
`series_id`, so a truncated result is the alphabetically first *n*; ranking by
population is what turns *"the hundred largest departments"* from a client-side
scan into a query.

The `definition` → `description` read in `_row()` is a separate one-line fix,
already in hand, and is not part of this CR.

---

## 8. Verification

1. `alembic upgrade head`; confirm the three columns and two indexes exist and that
   the 13,967 existing rows are untouched, with `measures = '{}'`.
2. Re-run the FBI catalogue export; confirm `population` is present on all 3,886
   entries and equals the response's resident figure, not the participated one.
3. `load_catalog.load(DATA_DIR, "fbi")`; expect 3,886 rows, `is_active` 3,628 true
   / 258 false, `coverage_percent` non-null on 3,876, `measures` carrying
   `coverage_min_percent` on the same 3,876 and `filings` on 2,736.
4. `series_catalog_search(source="fbi", min_coverage=90, order_by="population DESC",
   limit=10)` returns the ten largest well-covered agencies, and `total` reports
   how many qualified before the limit.
5. Confirm no existing source regressed: counts unchanged for clio 11,042,
   cdc 2,526, clio_historical 391, voteview 8.

---

## 9. Open decisions

- **Scale of `coverage_percent`.** `numeric(5,2)` stores 0.00–999.99, which fits a
  percentage with room to spare. If a fraction (0–1) is preferred, decide before
  the loader is written — mixing the two later is the kind of error that reads as
  a coverage collapse.
- **Whether `population` should be nullable for sources with no natural
  denominator** (Clio indicators, Voteview measures). Proposed: yes, null means
  "not applicable", and callers filtering on it must accept that null rows drop out.
- **Whether to promote `coverage_min_percent`** once there is evidence anyone
  filters on it (§5).
