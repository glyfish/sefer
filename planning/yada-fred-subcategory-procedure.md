# FRED catalogue discovery and subcategory derivation — the procedure

**Audience: whoever implements this in meida.** It was built in yada because that is where
the context was (2026-11-01), but it belongs in meida, which owns the vendor clients and
builds the metadata catalogues. See `yada-todo.md` §5 for the ownership argument. This
document is the specification, not a description of yada's files — it records what each
step does, why it does it that way, and which decisions were measured rather than assumed.

Reference implementation: `yada/apps/agentic/db/fred_discovery.py`,
`yada/apps/agentic/db/fred_subcategory.py`, migrations `0006`–`0011`, and the two entry
points `yada/clients/bin/fred_metadata.py` (discovery) and
`yada/clients/bin/fred_subcategories.py` (derivation). Both exist because of §0's first
point: a documented step nobody can invoke is not reproducible, and `build()` had no caller
for a week.

---

## 0. Why there is a procedure at all

FRED's own taxonomy stops above browsable size. **206 categories hold 500 or more series
attached directly to them, and 142 of those return zero children** from
`category/children`. The largest holds **53,187 series**. So for most of the oversized
nodes, the levels between a category and its series simply do not exist upstream.

**Corrected 2026-11-07.** This section previously claimed that *every* one of 134 such
categories returned zero children, "checked one at a time, no exceptions". That check ran
against a partially walked tree — the second full walk found 4,180 more categories — and it
is wrong: 64 of the 206 do have children. The conclusion is unaffected and in fact better
supported, because where children exist they hold almost nothing:

| node | series at the node | in its children |
| --- | --- | --- |
| `Production & Business Activity > Housing` | 53,187 | **254 in 7 children (0.5%)** |
| `National Accounts > Flow of Funds` | 46,124 | 2,359 in 17 children (5.1%) |
| `Population, Employment, & Labor Markets > Productivity & Costs` | 9,633 | 1,110 in 2 (11.5%) |
| `Production & Business Activity > Industrial Production & Capacity Utilization` | 2,672 | 7 in 1 (0.3%) |

So the honest form of the claim is not "there are no subcategories" but **"the subcategories
that exist do not carry the series"** — descending from Housing moves you from 53,187 series
to a sibling set holding 254, leaving the pile untouched. Derived nodes are still the only
way to get a browsable leaf; the argument just rests on where the series are attached rather
than on an absence of children.

The requirement they are built to: **a leaf holds at most 25 series**, so a person can
read it and judge it by eye.

Two things everything else follows from:

1. **A file hand-off cannot report a short fetch.** The original export wrote YAML which a
   loader read back. It was wrong four ways and announced none of them: series lists cut
   at one 1,000-row page (145,192 missing memberships), a tree rooted a level too low,
   `Production & Business Activity` absent entirely, and 881 of 1,029 non-regional
   categories present. A file has no transaction, no row count and nothing to reconcile
   against, so one page of nine looks exactly like completion. **Discovery writes to the
   database, and every fetch stores what the source said beside what was written.**

2. **An unrecorded decision reads as a bug.** Country and state data were deliberately
   limited because of volume. Nothing recorded that, so this session spent an hour
   diagnosing them as faults before being told. **Deliberate omissions are stored, with
   their reason, in the same tables as the data.**

---

## 1. Discovery — the catalogue

### 1.1 Walk the tree from the root

Breadth-first from category `0`, taking `parent_id` from FRED's own response.

**Store the edge, derive the path.** The export kept only a path string, so a subtree
fetched by its own id lost the levels above it and nothing could detect the loss —
`Countries` was really `International Data > Countries`. Store `parent_id` as a column and
compute `category_path` from it with a recursive CTE. The two then cannot disagree.

- Guard the recursion with a maximum depth. A parent/child cycle in a paced walk is a
  silent infinite loop that looks like slow progress.
- Report categories unreachable from the root; **do not delete them.** They may be
  leftovers from subtree fetches, and dropping catalogue rows on one walk turns a
  transient failure into data loss.
- Live shape: **5,201 categories**, 0 unreachable, 8 real roots. 4,173 of them (80%) are
  under `U.S. Regional Data`.

**Record what the walk has *visited*, not only what it has *found*.** A category is found
when its parent names it as a child, and visited when you ask it for its own children.
Those are different events, and storing only the first makes a node the walk never reached
indistinguishable from a genuine leaf — the same ambiguity that hid the original export's
gaps. A `walked_at` timestamp resolves both: a resuming walk skips what it has visited and
queues children from the database, so a run that dies continues past the previous frontier
instead of restarting at it. In the regional collection that skipped 1,058 categories
without spending a request.

**Make resume-versus-refresh the caller's choice.** Skipping a visited category means not
noticing children FRED has *added*. That is right for resuming an interrupted run and wrong
for a periodic refresh, so the walk takes it as an argument. Defaulting to skip makes every
later run a silent no-op; defaulting to revisit makes resume pointless. Neither is safe
implicitly.

### 1.2 Stop at excluded subtrees, and record why

An excluded category is **recorded and not descended into** — one request instead of
several thousand. Store the reason on the row.

| excluded | size | reason |
| --- | --- | --- |
| `U.S. Regional Data` (3008) | 4,173 categories | states, counties, metros; `States` alone is 53 categories / ~80,000 series |

Keep the categories that an earlier unscoped walk already discovered. They cost nothing,
they record that the branch exists, and keeping them means including regional data later
is a *fetch*, not another hour of walking. **Do not mark a descendant that already holds
series** — `Census`, `BEA` and `BLS Regions` came through the original export with data,
and calling them excluded would contradict the rows beneath them.

**This exclusion has since been lifted** — regional data was collected on 2026-11-07 and the
exclusion table is now empty — which is the point of recording it as data rather than
hard-coding a skip. The row above is kept as the worked example.

**Reconcile exclusions in both directions.** Emptying the table has to *clear* the stored
marks, not merely stop adding them. A one-way reconciler leaves a branch that is wanted
again flagged as excluded, the pending-work query keeps skipping it, and the fetch reports
success over data it never requested — the truncated-export failure in a new place.

### 1.3 Fetch series, paginated, reconciled

For each non-excluded category, page `category/series` with `limit=1000`.

- **Advance `offset` by the page actually returned**, not by the requested limit. Advancing
  by the limit skips a window whenever the server returns a short page.
- Stop when `offset >= count`, so an exact multiple costs no wasted trailing request.
- **Record `api_series_count` beside `fetched_series_count`.** This pair is the procedure.
  `status='ok'` only when they agree.

**Deliberate caps get a `page_limit` column.** Countries stay at one page. Without the
column a capped country reads `status='incomplete'` — alarming, wrong, and retried on
every resume forever. With it:

> `api_series_count > fetched_series_count` **with** a `page_limit` is a choice.
> The same inequality **without** one is a fault.

Live result, after two runs (non-regional on 2026-11-01, regional on 2026-11-07):

| | |
| --- | --- |
| categories complete | 5,201 of 5,201 — 0 incomplete, 0 failed |
| series | **846,628** (against 186,379 from the export) |
| memberships | 1,002,244 |
| requests | 2,359 + 8,342 |
| wall clock | 28 min + 45 min |

The reconciliation closes exactly: `sum(api_series_count)` is 1,052,462 and
`sum(fetched_series_count)` is 1,000,709, and the 51,753 difference equals the deferral
recorded under `page_limit` to the row. Nothing is unaccounted for. 38 capped categories
carry the shortfall, holding 7,690 distinct series we do not have — a number obtained by
listing them, not by subtraction.

### 1.4 Rate and credentials

- FRED documents **120 requests/minute**. Probing at ~480/min returned 429s. Pace at
  ~100/min and back off on 429 and 5xx.
- **A 400 mentioning `api_key` is not rate limiting — fail loudly.** yada's stored FRED key
  was unregistered for an unknown period and nothing noticed, because nothing in yada
  called the API. Construction of the client should raise when the key is absent.

### 1.5 Never delete during discovery

The source is ~10,700 paced requests, any of which can fail. Upsert, so a partial run leaves
the catalogue larger and more correct, never emptier. Pruning series FRED has genuinely
dropped needs a *complete* scan to be safe and is a separate pass.

---

## 2. Subcategory derivation

Per category, three steps. **Cluster within a category, never globally** — it is cheaper,
the naming is sharper because the input is homogeneous, and it keeps FRED's curation as the
spine instead of replacing it with ~27,000 derived nodes and no human structure above them.

### 2.1 Embed the titles

`text-embedding-3-small` at **256 dimensions** (of 1,536). Measured sufficient; 293,210
distinct titles at full width would be gigabytes of vectors and centroids.

Cache by title across categories. 69.1% of titles are distinct and a series in several
categories would otherwise be embedded repeatedly. Cost for the whole catalogue: **~$0.10**.

### 2.2 Split recursively until every leaf is under the cap

**Not one k-means at `k = n/25`.** Measured: that leaves **37% of leaves over the cap,
holding 56% of the titles**. A mean of 25 is not a maximum of 25.

Recurse: cluster, then re-cluster any child still over the cap.

**Balance the cluster sizes.** This is the step that decides how deep the tree gets, and
getting it wrong is not visible until you look at the depth. Plain k-means optimises
cohesion and says nothing about size; because the recursion continues until every leaf is
under the cap, an uneven split is not absorbed, it is **amplified into depth**. Measured
2026-11-08 on three live categories:

| category | plain k-means | size-balanced |
| --- | --- | --- |
| 454 series | depth 6, 43 nodes, 31 leaves | **depth 2**, 20 nodes, 19 leaves |
| 2,790 series | depth 6, 259 nodes | **depth 3**, 151 nodes |
| 9,932 series | depth 8, 1,105 nodes, **9 leaves of one series** | **depth 3**, 426 nodes, none |

A 454-series category reaching depth 6 is the failure the whole scheme exists to prevent:
one cluster takes 63 of 454 and recurses five more times. Balanced, leaves come out at
22–25 series rather than a median of 16 with singletons in the tail.

Implementation: k-means for the centroids, then assignment capped at `ceil(n / k)` per
cluster, placing points **most-confident-first** so the ones paying for the balance are the
ones that were ambiguous anyway. It costs **2 points of leaf cohesion** (mean cosine to the
leaf centroid 0.953 → 0.931) and **61% of the naming calls** on a large category.

- **Enforce the branch cap, do not merely state it.** It was stated here and in the code
  and neither enforced it: the `k` ceiling read `BRANCH_CAP ** 2`, so a node could take
  **625** children — no more evaluable than the pile it was built to break up. 130 of the
  723 non-regional categories were over the threshold that triggers it. Enforcing 25 does
  not make the tree deeper to browse (section 2.4).
- **Force a halving if a clustering pass makes no progress.** k-means can return every
  point in one cluster; without this the recursion never terminates. Arbitrary structure
  is worse than clustered structure but infinitely better than a hang.
- Assert the invariants afterwards, **both directions**: `max(series_count) <= 25` over
  live leaves, and `max(children) <= 25` over interior nodes. A tree can satisfy the first
  completely and still be unbrowsable at the top, which is exactly how the branch cap went
  unenforced — nothing looked upward.
- **Version the splitter.** The names are not the only derived thing; the shape is too, and
  a tree half-built under two splitters is no more comparable than one half-built under two
  prompts. Store it on every row beside the prompt version, and treat a differing value as
  pending work.

### 2.3 Name every node

Bottom-up. **Leaves are named from their member titles; interior nodes from their
children's names.** Naming an interior node from a sample of its series describes the
sample and reads as describing the subtree — confidently, and wrongly.

Model `claude-haiku-5-5`, 18 members sampled per call, **`max_tokens` 1500**.

**The token budget is not optional.** haiku-5-5 uses adaptive thinking and judges it well:
a six-title leaf returned no thinking block at all and 80 output tokens, while an interior
node summarising 18 child names spent 355. At `max_tokens=400` the latter truncated
mid-JSON and **6 of 75 names failed, including a category's root node.** Thinking is not
the cost — measured at $0.000088 per leaf name with or without it — so leave it enabled and
give it room.

**Check `stop_reason == 'max_tokens'` before parsing, and discard the reply.** A JSON object
cut off mid-string still yields a name that reads perfectly while its concepts are silently
half-missing. Retry once with double the budget, then record a visible failure. Count
truncations separately from parse failures: a rising truncation count means the budget is
wrong, not the model.

### 2.4 Depth comes from FRED's tree, not from the derived levels

Worth measuring before optimising the wrong half. Total depth to reach a series is FRED's
own path plus the derived levels, and the two are **anti-correlated** — the categories
holding the most series sit shallowest upstream.

| | FRED's own tree | with derived levels |
| --- | --- | --- |
| non-regional (1,028 categories) | median 3, max 9 | **median 4** |
| regional (4,173) | **3,845 sit at exactly depth 5** | **median 6**, max 8 |

`Production & Business Activity > Housing` holds 53,187 series at depth 2, so even three
derived levels put it at 5. The deepest FRED paths hold almost nothing and need no derived
levels at all — the record is depth 9 for **2 series**:

```text
International Data > Indicators > Work Started > Construction > Buildings
  > Total Work Started > Construction > Buildings > Total
```

FRED has repeated `Construction > Buildings > Total` twice in one path, and the two levels
above the leaf hold **0 series with exactly one child each**: three clicks offering no
choice. Two cheap levers follow, neither needing a model call and neither a deletion:

- **Collapse pass-through chains.** 71 categories hold no series and have exactly one
  child (45 non-regional, 26 regional).
- **Flag dead categories.** 74 hold no series and have no children.

---

## 3. The classification prompt

Versioned, and the version is stored on **every row it produces**. Names are model output,
not source data: a changed prompt gives different names for identical input, and a tree
half-built under each prompt must not be mistakable for a consistent one. **Bump the
version on any edit, including whitespace.**

Current version: **`2026-11-01.1`**

### 3.1 Leaf system prompt

```text
You name groups of statistical data series in a catalogue, for a browsable tree.

Reply with JSON only, no other text:
{"name": "<4-8 word noun phrase>", "concepts": "<6-12 comma-separated search terms>"}

Rules:
- "name" is a label shown in a tree beside sibling labels. A noun phrase, not a sentence,
  and no trailing punctuation.
- "concepts" are terms a researcher might search for. At least half MUST be words that do
  NOT appear in the titles shown: synonyms, the field of study, the economic concept, the
  industry, common abbreviations. Terms already present in the titles add nothing.
- Describe only what every title shown has in common. Do NOT add a country, region, date
  range or units unless it is in all of them -- you are shown a sample, and a specific
  that fits the sample will be wrong for the rest of the group.
- If the titles have little in common, say so plainly in the name (for example
  "Assorted regional labour indicators") rather than inventing a theme.
```

### 3.2 Interior system prompt

```text
You name a parent group in a statistical data catalogue, given the names of its children.

Reply with JSON only, no other text:
{"name": "<4-8 word noun phrase>", "concepts": "<6-12 comma-separated search terms>"}

Rules:
- "name" must cover ALL the child groups listed, at one level of generality above them.
  A noun phrase, not a sentence, and no trailing punctuation.
- "concepts" are search terms for the whole group. At least half MUST be words that do NOT
  appear in the child names: broader field terms, synonyms, common abbreviations.
- Do NOT name the group after one child, and do NOT add a country, region or date range
  unless every child carries it.
```

### 3.3 User messages

```text
Series titles in this group:
- <title>
- <title>
```

```text
Child group names:
- <name>
- <name>
```

### 3.4 Why each rule is there

| rule | what it prevents |
| --- | --- |
| JSON only | output tokens spent on prose, ~31,000 times |
| **concepts must include words absent from the input** | the model echoing the titles' own vocabulary back, which makes the field worthless — **this is the one rule the whole layer depends on** |
| noun phrase, no punctuation | labels that do not read as labels beside siblings |
| no invented country / region / date / units | a confident, plausible label that is wrong for every member outside the sample |
| say so when there is no theme | an invented theme over a genuinely mixed group |
| interior names cover all children | a parent named after whichever child the model liked |

### 3.5 What the concepts field buys, measured

A leaf of 11 coke-oven series was named *"Coke oven capacity and production"* with concepts
`metallurgical coal, steel industry, coking plants, pig iron, furnace capacity, iron and
steel manufacturing` — **not one of which appears in any member title.**

Full-text search over the derived names and concepts, against the same queries run over the
424,634 titles:

| query | over titles | over derived names |
| --- | --- | --- |
| `industrial infrastructure construction` | **0 rows** | **#1** — Construction, infrastructure and shipbuilding statistics |
| `steel making capacity` | **0 rows** | **#1** — Coke oven capacity and production (11 series) |
| `heavy industry plant buildout` | no match | #1 |

Searching ~27,000 named nodes beats searching 424,634 titles, and `websearch_to_tsquery`
ANDs its terms, so a three-word description of 424,634 prose titles returns silence.

---

## 4. Resync

FRED changes. Discovery is idempotent and re-runnable; the derived tree needs reconciling
afterwards. **Split into a cheap half that runs always and an expensive half that is opt-in.**

### 4.1 The cheap half — no model calls, safe on a schedule

1. **Re-run discovery.** Upserts, reconciles, reports.
2. **Find series in a built category that no leaf holds.** These are the normal product of
   a resync, not errors — but a series in no leaf is unreachable by browsing even though it
   is in the catalogue, so it must not stay invisible.
3. **Assign each to the nearest leaf centroid.** This is what storing `centroid` is for:
   a few hundred new series cost a few embeddings instead of a rebuild and thousands of
   names. No LLM call, no re-clustering.
4. **Recount.** Leaf counts from memberships; interior counts summed from children, so they
   cannot drift.
5. **Mark emptied leaves, and revive refilled ones.** Never delete — a subcategory id may
   be referenced from outside the schema.

### 4.2 The expensive half — opt-in

Assignment can push a leaf past 25. **Leave it over the cap and report it.** Splitting needs
naming, so it belongs to a build pass; the `over_cap` status and the violation query make
the debt visible rather than quietly breaking the invariant.

When asked, rebuild only the offending categories. Clearing and rebuilding one category's
derived rows is the only delete in the derivation — scoped to one category, never to
`fred_series`, and necessary because an appending rebuild would silently double every node.

### 4.3 Rebuild triggers

| trigger | action |
| --- | --- |
| new series in a built category | assign by centroid (cheap) |
| a leaf over the cap after assignment | rebuild that category (opt-in) |
| a leaf emptied | mark, keep the row |
| `prompt_version` differs from current | treat the category as pending — names are not comparable across prompts |
| a category's series count changed substantially | rebuild; centroids drift as membership shifts |

### 4.4 What is not solved

- **Facet-shaped data is not served by this scheme, and regional data is only the largest
  instance.** The semantic split clusters series by title text. That works where titles differ
  by *what is measured*, and fails where they differ by *where* — county titles are the same
  measure with a place name substituted, so clustering groups Alabama's counties together
  instead of grouping unemployment measures together. Regional data is 4,173 of 5,201
  categories and 529,345 memberships, and it wants
  a facet scheme (measure x place x time) rather than a derived tree. BIS's SDMX dimensions
  are what that looks like when a provider supplies it natively. **Settle this before
  spending the regional half of the naming budget in §5** — a tree built on the wrong axis is
  not cheaper to discard than to skip.

  The depth measurement in §2.4 makes this sharper than "the clustering groups on the wrong
  axis". Regional categories already sit **5 levels deep** in FRED's own tree, 3,078 of them
  as `States > <State> > Counties > <County>`. Deriving under that reaches a median of 6 and
  a maximum of 8 clicks — to browse data whose natural shape is **two selections**, a place
  and a measure. The scheme would be spending ~$5.63 and 28,573 names to build a deep tree
  over a problem that a pair of dropdowns answers, and the place hierarchy FRED already
  supplies is one of the two facets, sitting there unused as a hierarchy instead.
- **Name stability.** A rebuild regenerates names, so a bookmarked subcategory can be
  renamed under its id. If names must be durable, pin them and rebuild only the structure.
- **Pruning series FRED dropped.** Needs a complete scan to be safe, and now has one
  precedent rather than a general mechanism. Category 34111 held 2,398 memberships against
  FRED's 1,398; the 1,000 extra were the retired `ALLQ*` family, pruned 2026-11-08 once
  every check agreed — the surplus matched the `ALLQ%` prefix exactly, FRED returned 400 for
  each, 0 of 1,000 carried `notes` against 100% of the 1,398 retained, the retained
  prefixes were disjoint, and the retired rows stopped at `observation_end 2025-01-01`
  against 2026-07-01. `surplus_categories` now returns **0** across 5,201 categories.
  The 1,000 `fred_series` rows were kept, so the delete is reversible by one insert; they
  are now series in no category, which is the next thing to decide.
- **Sibling-blind naming, now measured.** Each node is named without seeing its siblings. The
  completed run put a number on the consequence: **4,445 of 27,385 nodes (16.2%) share a name
  with a sibling**, across 366 categories, worst case **11 sibling leaves under one name**.
  Passing sibling names into the prompt would de-duplicate the labels, but §4.5 is why that
  treats the symptom.

### 4.5 The facet shape is in the half that was built

Written after the non-regional run of 2026-11-08, because it revises §4.4's premise.

The sibling collisions above are not distributed evenly. They concentrate exactly where the
data is cross-sectional by place:

| Branch | Collided | Nodes | Share |
| --- | --- | --- | --- |
| `Academic Data > Penn World Table 7.1` | 132 | 298 | 44.3% |
| `Population, Employment, & Labor Markets > Population` | 193 | 604 | 32.0% |
| `Prices > Producer Price Indexes (PPI)` | 156 | 633 | 24.6% |
| `International Data > Indicators` | 1,277 | 5,328 | 24.0% |
| `Production & Business Activity > Housing` | 458 | 3,143 | 14.6% |
| `International Data > Countries` | 418 | 5,440 | 7.7% |

Read the member titles of any one of them and the cause is unambiguous — they are identical
except for a place name, which sits at the *end* of a long string:

```text
Purchasing Power Parity Converted GDP Per Capita (Chain Series) for Belgium
Purchasing Power Parity Converted GDP Per Capita (Chain Series) for Canada
```

The embedding of such a title is nearly constant across the category, so there is no semantic
axis to cluster on. The splitter carves equal parts because that is what it is told to do, and
every part is then honestly described by the same name. The name is simply the first place the
absence of a semantic axis becomes visible.

**What this changes.** §4.4 excluded the regional half on the grounds that regional titles
differ by place rather than by measure, and framed that as a property of the regional branch.
The exclusion was right and the framing was wrong: the shape recurs throughout the catalogue,
and roughly a sixth of the tree that was just paid for is affected by it. Three consequences:

1. **The remedy is one remedy, not two.** Split facet categories by the place named in the
   title — data FRED already supplies and the embedding discards — rather than semantically.
   That serves `International Data > Indicators` and `U.S. Regional Data` alike.
2. **De-duplicating names does not fix it.** Passing siblings into the prompt would make 11
   identical labels into 11 distinguishable ones, all describing arbitrary thirds of one
   undifferentiated pile. The split is what is wrong; the label only reports it.
3. **Detection should precede the regional spend.** A category whose titles share a long
   common prefix is detectable *before* any model call — cheaply, from the titles alone. That
   test is what §5 should gate the regional half on, rather than the regional/non-regional
   path prefix, which is now known to be the wrong discriminator.

Found by `yada/notebooks/data/fred_subcategories.ipynb`, which is read-only and re-runnable
against the live tree.

---

## 5. Cost and scale, measured

Re-measured **2026-11-08**, after the regional subtree was collected and after the splitter
was balanced (section 2.2). Both numbers moved, in opposite directions.

| | |
| --- | --- |
| categories, total / with series / excluded | 5,201 / 4,919 / 0 |
| series | 846,628 |
| memberships | 1,001,244 |
| distinct titles | 659,829 (77.9%) |
| largest category | 53,187 series → 3 derived levels |
| discovery | 10,701 requests, 73 min across two runs |
| embedding the whole catalogue | ~$0.20 |
| naming, measured per name | **$0.000197** |
| naming throughput, 8 concurrent | **4.38 names/s** |

**Why the per-name cost rose from $0.000136 to $0.000197.** It is a consequence of the
balance fix, not a regression. Balanced leaves are *full* — 22–25 series against a former
median of 16 — so more of the 18-title sample is actually sent, and the model spends more
output tokens on it. The totals still fell, because the node count fell faster: the
454-series probe went from 43 names at $0.00586 to **20 names at $0.00494**.

**Fewer, fuller, costlier names.** Quoting $/name alone hides that, which is why the table
below is built from node counts rather than scaled from a dollar figure.

**Split by scheme, because only half of it is designed.** The semantic scheme in section 2
was measured on non-regional data; regional data is facet-shaped and section 4.4 is why that
is not the same problem.

| | non-regional (measured) | regional (projected) | whole |
| --- | --- | --- | --- |
| categories with series | 924 | 3,995 | 4,919 |
| categories over the cap | 723 | 3,883 | 4,606 |
| memberships covered | 469,329 | 529,345 | 998,674 |
| names projected | 27,384 | 28,573 | 55,957 |
| names generated | **27,385** | — | — |
| naming cost projected | ~$5.39 | ~$5.63 | ~$11.02 |
| naming cost actual | **$4.81** | — | — |
| wall-clock at 8 concurrent | **1 h 57 m** | ~1.8 h | ~3.5 h |
| sequential, for comparison | 10.4 h | 10.9 h | 21.3 h |

The non-regional column is now the run of 2026-11-08, not a projection: 720 categories built
in that run plus 3 already built from probes, 0 failed, 201 skipped as already under the cap,
26,922 model calls. The regional column is still a projection and still blocked on §4.4.

**The node count is accurate in aggregate, and that is the claim worth making.** Because
balanced clustering divides each node evenly, simulating the recursion tracks the real
splitter: 20 / 151 / 426 nodes modelled for the 454 / 2,790 / 9,932-series categories, and
20 / 151 / 426 produced. Under plain k-means no such claim was possible — the same three
categories came out at 43 / 259 / 1,105 against a floor of 20 / 112 / 398.

Measured against the completed run across all 723 built categories: **predicted 27,384
against 27,385 actual**, exact for **93.4%** of categories individually. But it is not a
per-category guarantee — 8 categories were under-predicted and the worst is a third low
(637 series, 50 modelled against 74 produced), because `k` is itself capped at the branching
ceiling, so above 625 series the recursion takes a turn simple division does not. Authorise a
run from the total; treat any one category's figure as indicative. A unit test holds the model
and the splitter to each other at six sizes, so a plan cannot quote a total the run will not
reproduce.

**Correcting the previous estimate.** This section said **~$4.29** for the non-regional half
and called it a validation of the model, "$4.29 against the $4.20 estimated from the
424,634-series catalogue". That agreement was a coincidence of two compensating errors: the
node count was low (it counted the leaf floor, which under-reports by a third, and it
assumed the unenforced `BRANCH_CAP ** 2` ceiling) and the per-name cost was low. The honest
figure for the committed half is **~$5.39**.

Wall-clock, not cost, was the real constraint and the previous estimate did not mention it:
naming was sequential at 1.37 s a call, which is **10.4 hours** of waiting on HTTP for the
non-regional half alone. Siblings are independent, so a level can be named at once.

**What was actually run:** the non-regional half, **$4.81 and 1 h 57 m**, completed
2026-11-08. Cost came in 11% under projection because the per-name figure had been measured on
probe categories, whose interior nodes summarise more children than the average; wall-clock
came in 15% over, because the two largest categories (`Housing` at 53,187 series and
`Flow of Funds` at 46,124) are a serial tail no concurrency within a level can remove.

The regional half still waits on section 4.4 — and the completed run strengthens that, because
the facet shape it describes turned out to be present in the non-regional half too. See §4.5.

## 6. Ordering, and what blocks what

1. **Discovery before derivation.** Clustering `Poverty` from 1,000 of its 9,932 series
   yields subcategory names generated from a 10% sample that read as authoritative and
   describe the wrong thing. Derived subcategories built on truncated input are worse than
   none.
2. **Derivation before search tooling.** The searchable surface is the names and concepts.
3. **Resync after both**, since it needs centroids to exist.
4. **Measure the shape before paying to name it.** Out of order, this is the expensive
   mistake: naming is the only step that costs money, and it is the last one, so a defect
   in embedding or splitting is paid for in names. Both of the splitter defects in §2.2
   were found by reading a built tree's depth and node count against the model — $0.09 of
   probe runs against the $5.39 they would otherwise have been baked into. Build three real
   categories, read their depth, leaf sizes and branching, *then* commit to the scope.

## 7. Open, for meida

- **Which repo owns this.** meida owns the vendor clients and the working FRED key; yada's
  is unregistered. `yada-todo.md` §5 argues the whole thing belongs there.
- **Whether derived `concept` shares a column with sourced `concept`.** meida's
  `series_catalog.concept` comes from source columns for CDC and Clio; FRED's would come
  from a clustering run and an LLM call. Same column, very different provenance and failure
  modes — a hallucinated concept is a silent misroute. A `concept_source` discriminator, or
  separate columns, rather than mixing them.
- **Whether the regional facet scheme belongs here at all.** §4.4 argues the semantic
  tree is the wrong shape for 4,173 of 5,201 categories. If meida builds facets, the place
  hierarchy FRED already supplies is one axis for free and the derived tree is needed only
  for the measure axis — which would make the regional half cheaper than the non-regional
  one rather than slightly dearer.
- **One live inconsistency.** `International Data > Countries > United States` holds 2,790
  series with no `page_limit`, because it was fetched in full while testing pagination
  before the cap existed. The other 244 countries are capped at 1,000. The record is
  accurate about what happened, but a re-fetch would cap it and the data would shrink.
