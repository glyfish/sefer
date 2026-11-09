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

### 1.2 Nothing is excluded, and there is no way to exclude it

**Superseded 2026-11-08.** This section described a mechanism that no longer exists:
`fred_category.excluded_reason` recorded a branch as deliberately skipped so a reader could
tell an omission from a failed fetch. Migration `0012` dropped the column, along with
`fred_category_scan.page_limit`. The catalogue is now fetched whole, and §1.3's
reconciliation is the only thing that decides whether a category is finished.

It is kept because the argument for it was good and the argument against it is the more
useful one to record. The mechanism existed so that a deliberate omission was
distinguishable from a failure, which is a real distinction and worth having. What it cost
was a *configurable way for data to be absent on purpose*, discoverable only by whoever
later debugged the gap and traced it back to a flag nobody had set. One exclusion was ever
recorded — `U.S. Regional Data` (3008), 4,173 categories — and it was lifted on 2026-11-07
by collecting the branch, 8,342 requests in 45 minutes.

Two details from it are still load-bearing elsewhere:

- **A walk is cheap and a fetch is not, so discovered categories are kept even when their
  series are not wanted.** That is why lifting the exclusion was a fetch rather than another
  hour of walking, and why `walk --revisit` exists separately from `fetch`.
- **Any "deliberately absent" marker has to be reconciled in both directions.** Clearing the
  policy has to clear the stored marks, not merely stop adding them. A one-way reconciler
  leaves a branch that is wanted again still flagged, the pending-work query keeps skipping
  it, and the fetch reports success over data it never requested — the truncated-export
  failure in a new place. The same trap caught `fred_subcategory_build`, which keyed
  pending work on status and versions but not on membership, so a category that *gained*
  series read `ok` forever (fixed 2026-11-08; see §4.3).

### 1.3 Fetch series, paginated, reconciled

For each category — there is no longer any such thing as an excluded one — page
`category/series` with `limit=1000`.

- **Advance `offset` by the page actually returned**, not by the requested limit. Advancing
  by the limit skips a window whenever the server returns a short page.
- Stop when `offset >= count`, so an exact multiple costs no wasted trailing request.
- **Record `api_series_count` beside `fetched_series_count`.** This pair is the procedure.
  `status='ok'` only when they agree.

**There is no deliberate cap, and that is the stronger contract.** A `page_limit` column
carried one from 2026-11-01 to 2026-11-08, so that the inequality could mean a choice
rather than a fault. It is gone, and the inequality now means exactly one thing:

> `api_series_count > fetched_series_count` is a **fault**, always. Nothing configures it
> into a choice.

Live result, after three runs (non-regional 2026-11-01, regional 2026-11-07, the country
remainder 2026-11-08):

| | |
| --- | --- |
| categories complete | 5,201 of 5,201 — 0 incomplete, 0 failed |
| series | **854,318** (against 186,379 from the export) |
| memberships | 1,052,462 |
| requests | 2,359 + 8,342 + 108 |
| wall clock | 28 min + 45 min + 86 s |

The reconciliation closes as an identity: `sum(api_series_count)` and
`sum(fetched_series_count)` are both **1,052,462**, difference **0**. That is what the
removal bought — before it, closure meant "the gap equals the recorded deferral", which
is a weaker statement that needed a second column to be checkable at all.

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

- **Facet-shaped data is not served by this scheme, and it is not where this section
  predicted.** The semantic split clusters series by title text. That works where titles
  differ by *what is measured*, and fails where they differ by *where* — county titles are
  the same measure with a place name substituted, so clustering groups Alabama's counties
  together instead of grouping unemployment measures together. The reasoning is sound. The
  branch it was aimed at was wrong: regional data was named here as "the largest instance",
  and now that both halves are built it is the **least** affected branch measured (§4.5).
  The remedy is unchanged — a facet scheme (measure x place x time) rather than a derived
  tree, which is what BIS's SDMX dimensions look like when a provider supplies it natively
  — but it has to be aimed at *categories*, not at a path prefix.

  The depth and cost prediction can be closed out, because it was the accurate half of the
  argument. Regional categories do sit **5 levels deep** in FRED's own tree, 3,078 of them
  as `States > <State> > Counties > <County>`, and this section projected ~$5.63 and 28,573
  names to derive under them. Measured on the run of 2026-11-09: **$5.99 and 28,566 nodes**,
  with the two stacked trees reaching a median of **7** clicks and a maximum of **9**. So the
  scale was forecast well and the conclusion still does not follow from it — the objection
  was never really the depth, it was the axis, and the axis fails worse in the half that was
  built first.
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
- **Sibling-blind naming, now measured.** Each node is named without seeing its siblings.
  Across the finished catalogue: **6,526 of 58,227 nodes (11.2%) share a name with a
  sibling**, in 860 of 4,606 built categories, worst case **11 sibling leaves under one
  name**. Passing sibling names into the prompt would de-duplicate the labels, but §4.5 is
  why that treats the symptom.

### 4.5 The facet shape belongs to categories, not to a branch

Written after the non-regional run of 2026-11-08 and revised after the regional run of
2026-11-09, because between them they refute §4.4's premise rather than merely sharpening it.

The sibling collisions above are not distributed evenly. They concentrate where the data is
cross-sectional by place — and the branch excluded for being exactly that sits at the bottom
of the table:

| Branch | Collided | Nodes | Share |
| --- | --- | --- | --- |
| `Academic Data > Penn World Table 7.1` | 134 | 298 | 45.0% |
| `Population, Employment, & Labor Markets > Population` | 200 | 604 | 33.1% |
| `Prices > Producer Price Indexes (PPI)` | 156 | 633 | 24.6% |
| `International Data > Indicators` | 1,294 | 5,328 | 24.3% |
| `Production & Business Activity > Housing` | 522 | 3,143 | 16.6% |
| `International Data > Countries` | 733 | 7,716 | 9.5% |
| **`U.S. Regional Data`** | **1,794** | **28,566** | **6.3%** |

Nor is that an artefact of regional categories being smaller, which they are — a mean of
136 series against 720, a median of 88 against 205. Held at equal size the ordering does not
change:

| Category size | non-regional | regional |
| --- | --- | --- |
| 26–99 series | 9.4% | **2.6%** |
| 100–499 | 18.4% | **6.4%** |
| 500–1,999 | 18.1% | **13.0%** |
| 2,000+ | 15.1% | 16.8% |

Only the last row reverses, on five regional categories against sixty-six, which is too few
to carry a claim.

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
differ by place rather than by measure, and treated that as a property of the regional branch.
Neither half of that survived measurement. The shape recurs throughout the catalogue, a sixth
of the non-regional tree is affected by it, and the excluded branch is affected least of all.
Four consequences:

1. **The remedy is one remedy, not two.** Split facet categories by the place named in the
   title — data FRED already supplies and the embedding discards — rather than semantically.
   That serves `International Data > Indicators` and `U.S. Regional Data` alike.
2. **De-duplicating names does not fix it.** Passing siblings into the prompt would make 11
   identical labels into 11 distinguishable ones, all describing arbitrary thirds of one
   undifferentiated pile. The split is what is wrong; the label only reports it.
3. **Detection replaces the path prefix, and is no longer a gate on spending.** A category
   whose titles share a long common prefix is detectable *before* any model call — cheaply,
   from the titles alone. That test is what should mark a category as facet-shaped. It was
   going to gate the regional spend; the spend has happened, so it now has a different job:
   deciding which of the 860 collided categories a facet pass should rebuild, in either half.
4. **`SCOPES` is a way to split a long run, and nothing more.** It was carrying a quality
   judgement, and `--scope` defaulted to `non-regional` on the strength of it, which silently
   withheld 80% of the catalogue from anyone who did not pass the flag. Both defaults this
   ever had were wrong in opposite directions — the earlier one would spend the whole budget
   by accident — so as of 2026-11-09 there is none: `build` and `resync` require `--scope`,
   and the library's `scope` parameter is keyword-only with no default.

Found by `yada/notebooks/data/fred/fred_subcategories.ipynb`, which is read-only and re-runnable
against the live tree.

---

## 5. Cost and scale, measured

Re-measured **2026-11-09**, with the whole catalogue collected and the whole tree built.
Nothing here is a projection any more.

| | |
| --- | --- |
| categories, total / with series | 5,201 / 4,919 |
| series | 854,318 |
| memberships | 1,052,462 |
| distinct titles | 662,658 (77.6%) |
| largest category | 53,187 series → 4 derived levels, 3,127 nodes |
| discovery | 10,701 requests / 73 min on 2026-11-07, plus 108 on 2026-11-08 to refetch the 38 categories `page_limit` had truncated |
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

**Split by half, because the two were run separately.** Not because the scheme fits one and
not the other — §4.5 is why that framing is retired.

| | non-regional | regional | whole |
| --- | --- | --- | --- |
| categories with series | 924 | 3,995 | 4,919 |
| categories built (over the cap) | 723 | 3,883 | 4,606 |
| categories skipped (under the cap) | 201 | 112 | 313 |
| memberships covered | 522,486 | 529,976 | 1,052,462 |
| names projected | 27,384 | 28,573 | 55,957 |
| names generated | **29,661** | **28,566** | **58,227** |
| naming cost projected | ~$5.39 | ~$5.63 | ~$11.02 |
| naming cost actual | **$5.86** | **$5.99** | **$11.85** |
| wall-clock projected | — | ~1.8 h | — |
| wall-clock actual, 8 concurrent | **2 h 17 m** | **7 h 31 m** | **9 h 48 m** |
| throughput | 216 names/min | 63 names/min | — |

Non-regional is the run of 2026-11-08 (720 categories, plus 3 from probes, $4.81, 1 h 57 m)
*plus* the rebuild of 2026-11-08 that followed lifting `page_limit` — 38 country categories
that had gained series, 2,462 more names, $1.05, 20 m. Regional is the run of 2026-11-09,
restarted once after 121 categories to fix the naming retry (§2.3), so its figure includes
$0.004 paid twice.

**The cost model was right and the time model was wrong by 4x.** Node counts came in within
0.01% of the simulation in aggregate, and dollars followed them: $11.85 against $11.02
projected, the 7% gap being the per-name cost rising on fuller leaves. Wall-clock was
projected by scaling the non-regional run's names-per-minute, and that rate is not a
property of the pipeline — it is a property of the *shape* of what is being named.
Concurrency is 8 calls in flight **within one level of one tree**, so a tree wide enough to
fill 8 workers sustains 216 names/min while a tree averaging 7.4 nodes in total cannot keep
them busy, and regional averages 136 series per category against non-regional's 720. Scale
a future estimate from names/min measured on categories of comparable *size*, or model the
concurrency directly; do not scale it from a different half of the catalogue.

**`sum(cost_usd)` reads $11.45, not $11.85.** A rebuild replaces a category's build row, so
the 38 countries' original cost went with it. The $11.85 is from the run summaries, which is
the figure to trust for what was actually spent; the column is the cost of the tree as it
now stands.

**The node count is accurate in aggregate, and that is the claim worth making.** Because
balanced clustering divides each node evenly, simulating the recursion tracks the real
splitter: 20 / 151 / 426 nodes modelled for the 454 / 2,790 / 9,932-series categories, and
20 / 151 / 426 produced. Under plain k-means no such claim was possible — the same three
categories came out at 43 / 259 / 1,105 against a floor of 20 / 112 / 398.

Measured against the completed build across all 4,606 categories: **predicted 58,222
against 58,227 actual (-0.01%)**, exact for **98.1%** of categories individually. But it is
not a per-category guarantee — 12 categories were under-predicted and the worst is a third
low (637 series, 50 modelled against 74 produced), because `k` is itself capped at the
branching ceiling, so above 625 series the recursion takes a turn simple division does not.
Authorise a run from the total; treat any one category's figure as indicative. A unit test
holds the model and the splitter to each other at six sizes, so a plan cannot quote a total
the run will not reproduce.

Read the 98.1% with the mix in mind, because it flatters the model: small categories are
predicted exactly and most regional ones are small, so regional scores 99.6% against
non-regional's 90.2%. The aggregate improved because the population got easier.

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
- **Resolved 2026-11-08.** `International Data > Countries > United States` held 2,790
  series with no `page_limit` while the other 244 countries were capped at 1,000 — it had
  been fetched in full 41 minutes before the cap existed, and `status='ok'` meant it was
  never offered to a fetch again. That asymmetry is what made the cap indefensible rather
  than merely stale: the one country anyone would drill into was uncapped *by accident*,
  and its 151 derived nodes against a uniform 76 for every capped peer showed the cap was
  halving browsable structure. The cap is removed and all 245 are whole.
