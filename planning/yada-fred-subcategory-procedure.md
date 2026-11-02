# FRED catalogue discovery and subcategory derivation — the procedure

**Audience: whoever implements this in meida.** It was built in yada because that is where
the context was (2026-11-01), but it belongs in meida, which owns the vendor clients and
builds the metadata catalogues. See `yada-todo.md` §5 for the ownership argument. This
document is the specification, not a description of yada's files — it records what each
step does, why it does it that way, and which decisions were measured rather than assumed.

Reference implementation: `yada/apps/agentic/db/fred_discovery.py`,
`yada/apps/agentic/db/fred_subcategory.py`, migrations `0006`–`0008`.

---

## 0. Why there is a procedure at all

FRED's own taxonomy stops above browsable size. Every one of the 134 categories holding
500 or more series returns **zero children** from `category/children` — checked one at a
time, no exceptions — and the largest holds **53,187 series**. So the nodes between a
category and its series do not exist upstream. They are derived, or there is nothing to
browse.

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
- Live shape: **5,188 categories**, 0 unreachable, 8 real roots.

### 1.2 Stop at excluded subtrees, and record why

An excluded category is **recorded and not descended into** — one request instead of
several thousand. Store the reason on the row.

| excluded | size | reason |
| --- | --- | --- |
| `U.S. Regional Data` (3008) | 4,160 categories | states, counties, metros; `States` alone is 53 categories / ~80,000 series |

Keep the categories that an earlier unscoped walk already discovered. They cost nothing,
they record that the branch exists, and keeping them means including regional data later
is a *fetch*, not another hour of walking. **Do not mark a descendant that already holds
series** — `Census`, `BEA` and `BLS Regions` came through the original export with data,
and calling them excluded would contradict the rows beneath them.

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

Live result: **1,056 of 1,056 categories complete, 0 incomplete, 0 failed**, 2,359
requests, 28 minutes — **424,634 series** and 477,489 memberships, against 186,379 from
the export. 245 country categories carry `page_limit=1`, deferring 51,753 series that
remain visible in `api_series_count`.

### 1.4 Rate and credentials

- FRED documents **120 requests/minute**. Probing at ~480/min returned 429s. Pace at
  ~100/min and back off on 429 and 5xx.
- **A 400 mentioning `api_key` is not rate limiting — fail loudly.** yada's stored FRED key
  was unregistered for an unknown period and nothing noticed, because nothing in yada
  called the API. Construction of the client should raise when the key is absent.

### 1.5 Never delete during discovery

The source is ~2,400 paced requests, any of which can fail. Upsert, so a partial run leaves
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

Recurse: cluster, then re-cluster any child still over the cap. Measured cost **1.58× the
leaf floor**, giving leaves at a median of 16 and depth varying 1–5 rather than a fixed 2.

- Cap branching at 25 as well. A node with 243 children is no more evaluable than a leaf
  with 1,000 series.
- **Force a halving if a clustering pass makes no progress.** k-means can return every
  point in one cluster; without this the recursion never terminates. Arbitrary structure
  is worse than clustered structure but infinitely better than a hang.
- Assert the invariant afterwards: `max(series_count) <= 25` over live leaves. The
  requirement is a ceiling, so it is testable — and this project has repeatedly been bitten
  by things that were true when built and quietly stopped being true.

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

- **Name stability.** A rebuild regenerates names, so a bookmarked subcategory can be
  renamed under its id. If names must be durable, pin them and rebuild only the structure.
- **Pruning series FRED dropped.** Needs a complete scan to be safe; not implemented.
- **Sibling-blind naming.** Each node is named without seeing its siblings, so near-
  duplicate labels occur — one live category produced both *"Crop production and
  agricultural statistics"* and *"Agricultural production and livestock statistics"*. Fixing
  it means passing sibling names into the prompt, which has not been measured.

---

## 5. Cost and scale, measured

| | |
| --- | --- |
| categories, total / fetchable / excluded | 5,188 / 1,058 / 4,130 |
| series | 424,634 |
| distinct titles | 293,210 (69.1%) |
| categories needing subdivision | 753, covering 475,550 series |
| largest category | 53,187 series → 3 derived levels |
| leaf floor at 25 | 16,986 |
| leaves with the 1.58× recursion overhead | ~26,838 |
| discovery | 2,359 requests, 28 min |
| embedding the whole catalogue | ~$0.10 |
| naming, measured per name | **$0.000136** |
| naming the whole catalogue | **~$4.20** |

Measured on two live categories: 454 series → 43 nodes / 31 leaves, max leaf 25, mean 14.6,
0 failures, $0.0059.

---

## 6. Ordering, and what blocks what

1. **Discovery before derivation.** Clustering `Poverty` from 1,000 of its 9,932 series
   yields subcategory names generated from a 10% sample that read as authoritative and
   describe the wrong thing. Derived subcategories built on truncated input are worse than
   none.
2. **Derivation before search tooling.** The searchable surface is the names and concepts.
3. **Resync after both**, since it needs centroids to exist.

## 7. Open, for meida

- **Which repo owns this.** meida owns the vendor clients and the working FRED key; yada's
  is unregistered. `yada-todo.md` §5 argues the whole thing belongs there.
- **Whether derived `concept` shares a column with sourced `concept`.** meida's
  `series_catalog.concept` comes from source columns for CDC and Clio; FRED's would come
  from a clustering run and an LLM call. Same column, very different provenance and failure
  modes — a hallucinated concept is a silent misroute. A `concept_source` discriminator, or
  separate columns, rather than mixing them.
- **One live inconsistency.** `International Data > Countries > United States` holds 2,790
  series with no `page_limit`, because it was fetched in full while testing pagination
  before the cap existed. The other 244 countries are capped at 1,000. The record is
  accurate about what happened, but a re-fetch would cap it and the data would shrink.
