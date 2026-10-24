# yada — document search task list

Work queue for making document search good enough to expose over MCP, then better.
Built 2026-10-17 from the eight-claim audit of the four document-search diagnosis
reports, after the user caught the original reports over-claiming.

**Provenance matters here, because the original reports were wrong in ways that cost
time.** Every item below is tagged:

| tag | meaning |
| --- | --- |
| **[V]** | re-verified directly against the live system on 2026-10-17 |
| **[A]** | from the audit's subagents; mechanism plausible, number not independently re-run |
| **[?]** | explicitly unmeasured — do not act as if it is known |

The audit's own one-line summary: *every number the reports **counted** was exact;
every number they **inferred** was wrong.* Treat inherited numbers accordingly.

---

## Phase 0 — fixes that unblock measurement

These come first because **every retrieval measurement taken so far is unreliable**
until §0.1 lands, and because §0.2–0.4 are the mechanisms behind the user's actual
reported failures.

### 0.1 Pin the grader to temperature 0 — **done 2026-10-17**

**[V]** `scoring_llm_model` (`apps/agentic/core/llm_factory.py:217-226`) takes
`temperature=_env_float("LLM_TEMPERATURE", 0.7)`. `.env` sets `SCORING_LLM_MODEL=claude-haiku-4-5`
but no `LLM_TEMPERATURE`, so the grader runs at **0.7**. `filter_llm_model` and
`router_llm_model` do not.

**[A]** The same 8 chunks graded six times kept `[0, 0, 1, 1, 0, 0]`.

This is the "it worked yesterday" intermittency. It is one line. It is first because
**every drop-rate number anyone has quoted is a single roll of a 0.7-temperature die**
— re-run the probes after this lands and the numbers start meaning something.

### 0.2 Fix the advertised filter syntax — **done 2026-10-17**

**[V]** `apps/agentic/agents/document/research_library_agent.py:30-44` teaches the model
`author:` and `date:`. Neither field exists on that store (it has `authors`, and no date
field). They parse to `where=None` *and* leave the literal qualifier text inside the
embedded query string, so they corrupt the vector query too.

**[A]** `apps/agentic/core/query_filters.py:13` claims the vocabulary "applies to ALL
sources" and `:20` claims it "matches substring". Both false.

Pure text edits. Removes a defect the prompt actively causes.

**Three dead qualifiers, not one.** Verified against the live store:

| qualifier | status | why |
| --- | --- | --- |
| `author:` | dead | field is `authors`; parses to nothing |
| `date:` | dead | no qualifier and no `date` key (`published_date` is on 97.5%, unwired) |
| `notes:` | **harmful** | adds `{"source": "research_notes"}`; no `source` key exists, so it forces *every* query using it to zero — and it was in the prompt's own examples |
| `topic:` | **info field** | see below |
| `after:` / `before:` | **github only** | `ts_unix` is on 100% of github, **0%** of research_library/fred/etf |

The `after:`/`before:` row matters: the original reports called them flatly dead. Acting
on that would have removed working github date filtering over 61,781 hits.

### 0.2a `topic` is an info field, not a search filter

**User's call, 2026-10-17.** `topic` is present on 99% of research_library chunks, but its
values are whole prose sentences ("Fundamentals of fractional Brownian motion."), so an
equality filter could never match — it only ever zeroed the result set.

The distinction that settles it: **an info agent shows metadata and no content; a search
agent returns content.** `topic` describes a document, so it belongs in the info agents'
projected rows, not in the search filter vocabulary.

Implemented: the `topic:` qualifier is still *stripped* from the query — so a stray
`topic:...` cannot pollute the embedding — but builds no condition.

**This also resolves the carried "three sibling agents have a literal-placeholder bug"
item.** `FredDataInfoAgent` and `ETFDataInfoAgent` build their rows directly from
`d.metadata` with a `val()` helper that renders missing keys as `"N/A"`
(`fred_data_info_agent.py:94-120`). Their `{{metadata[...]}}` templates are **dead code**,
exactly like `code_repo_agent`'s — nothing to fix, only to delete (§0.6). That explicit
projection with missing-key handling is also the right model for §1.2's structured MCP
hits.

### 0.3 Make an unsatisfiable filter non-fatal — **done 2026-10-17**

**[V]** `apps/agentic/core/agents/chroma_rag_agent.py:58-67` builds `search_kwargs["filter"]`
once at construction and never retries.

**[A]** Reproduced 3/3 on the verbatim failing query from the user's own LangSmith trace
(20:30:09 today): `{'authors': 'William H. Matthaeus'}` is an equality predicate against a
comma-joined all-authors string → `{"documents": []}` → `(no results)` → a confident
"I don't have any relevant research documents". **Unfiltered, the correct papers rank
1-2-3 at distance 0.189** — the filter is not imperfect, it is *strictly harmful*.

Retry unfiltered on 0 hits and log `filter matched nothing`. This converts the two worst
failures (§0.3 and §0.4) from confident-empty into degraded-but-correct **without touching
any data**, which is why it comes before the proper fix in §2.3.

### 0.4 Index `glyfish/yada` — absolute `repo_path` — **code done 2026-10-17, reload pending**

**[V]** The cause, confirmed with `git check-ignore` inside the clone:

```
GITHUB_LOCAL_PATH = ".repos"            # constants.py:15 — relative
github_document_loader.py:173            GitLoader(repo_path=path, branch=branch)

inside .repos/glyfish/yada:
  git check-ignore -v ".repos/glyfish/yada/README.md"  →  .gitignore:2:.repos   IGNORED
  git check-ignore -v "README.md"                      →  (not ignored)
inside .repos/troystribling/zgomot, same relative path →  (not ignored)
```

The relative path self-matches **only** in the yada clone, because only yada's own
`.gitignore` contains `.repos`. One of 103 clones. Every file is skipped → 0 chunks.

This matters beyond one repo: **[A]** both filter paths (LLM and regex) happily emit
`{"repo": "yada"}`, which then matches 0 of 415,006. The repo list in the Pydantic field
description is prose, not a `Literal`, so the model can emit any unindexed repo — same
failure for `{'account':'troystribling','repo':'navi'}`, since navi is indexed under
`glyfish`.

**[A]** Absolute-path control run produced 167 files → 9,519 chunks.

### 0.5 Fix the comment on the `code_repo_agent` template fix — **done 2026-10-17**

**[V]** The uncommitted fix to `apps/agentic/agents/document/code_repo_agent.py` is
functionally correct — `{account}`, `{repo}`, `{branch}`, `{file_path}`, `{ext}` are each
on 100% of 415,006 chunks. But the comment it carries describes `create_retriever_tool`
formatting each document, and **the compiled graph never takes that path** (see §0.6).
Rewrite the comment to say what is actually true: the template is validated at
construction and otherwise unused.

### 0.6 Resolve the dead code — **done 2026-10-17**

**Decision (user, 2026-10-17): keep the linear graph; revisit the agentic loop after MCP
works.** The reason is that the loop already exists one level up — `DocumentAgent` is a
ReAct graph (`model ⇄ tools`) and the search agents are among its tools, so the model can
already re-query. Under MCP the client takes that role. An inner `rewrite → retrieve` loop
would be a loop nested in a loop, with its own model spending on the server's key,
invisible to the client's cost counter. See §2.2 for what to measure before revisiting.

**Implemented.** `ChromaRAGAgent.DOCUMENT_HEADER_KEYS` — (key, label) pairs prepended to
each retrieved chunk, missing keys skipped. `CodeRepoAgent` declares repo/file_path/branch/
ext/commit; `ResearchLibraryAgent` declares title/authors/shelf/section/path. Deleted:
`_retriever_tool`, `_tools`, `_tooled_llm`, the `tooled_llm` property,
`ChromaRAGAgent._invoke_model`, the `document_prompt` constructor parameter, all four dead
templates, and six now-unused imports. Both `_generate` prompts were rewritten to describe
the header that actually exists.

**Measured.** The citation defect is fixed outright — same query, before:
*"the exact file path is not given in the provided context… possibly named something like
`zgomot/midi/stream.rb` or similar"*; after: *"**lib/zgomot/drivers/core_midi.rb** in the
zgomot repository… as seen in Document 5 and Document 7"*.

**Grading, measured against the real grader (`claude-haiku-4-5` via anthropic, 8 runs
per cell).** Temperature 0.0 unless stated:

| store | bare context | with header |
| --- | --- | --- |
| research_library | 3/8 | 3/8 |
| github/zgomot | **5/8** | **6/8** |

The github gain is strictly additive — `lost with header: none`, `gained:
lib/zgomot/midi/note.rb`. That chunk's text is `private :pitch_to_midi / end / end`,
meaningless alone; with `File path: lib/zgomot/midi/note.rb` attached its relevance is
obvious. The grader had been rejecting a good chunk for lack of provenance. It also
half-fixes §0.6a: `note.rb` is the file the appendix prints, so appendix and graded set
now agree on this query.

**METHOD WARNING — read before trusting any grader number.** Every grading figure in the
first version of this document was measured on the WRONG MODEL. A test harness that calls
`set_chatgpt_env(filedir=".keys")` does **not** load `.env`, so `LLM_MODEL_PROVIDER` and
`SCORING_LLM_MODEL` fall back to the factory defaults (`openai` / `gpt-4.1-mini`) instead
of the app's `anthropic` / `claude-haiku-4-5`. The two models behave differently enough to
invert conclusions: on gpt-4.1-mini the header appeared to *reduce* kept-count 6->5, and
temperature 0.0 appeared NOT to give determinism. Both were artefacts. **Any harness that
measures agent behaviour must `load_dotenv(".env")`, not `set_*_env(".keys")`.** This is
the same split as §0.8 and it is not only about API keys -- `.keys/` carries no model
configuration at all. See [[yada-langsmith-key-stores]].

### 0.6a Remaining: the second retrieval (not fixed)

**[V]** `ChromaRAGAgent._create_agent` compiles exactly:

```python
START → retrieve → grade → generate → END
```

`_retriever_tool` (`chroma_rag_agent.py:70`), `_tooled_llm` (`:77`) and
`ChromaRAGAgent._invoke_model` (`:281`) are constructed and **never become nodes**. The
only other references are a *different* class's own `_invoke_model` in `react_node.py`.
`_retrieve` (`:197-214`) calls `self.retriever.invoke()` directly and concatenates bare
`page_content`.

Consequence **[A]**: `_generate`'s prompt instructs the model to cite commit hash and
branch from context that never contains them. Ten months of degraded attribution.

`FileChromaRAGAgent._generate` still re-invokes the retriever (2 vector searches per
question) and appends a full-file section for the top hit by `path` — which can be a chunk
the grader rejected. Observed: answer correctly cites `lib/zgomot/drivers/core_midi.rb`
while the appendix shows `lib/zgomot/midi/note.rb`. Not fixed because the obvious fix —
caching hits on `self` — is unsafe under the concurrent requests the MCP server will serve;
the hits need to travel through graph state instead. Fold into §1.2.

Superseded note: Either delete the three, or route `_retrieve` through the retriever tool so the metadata
header actually reaches the model. **Decide before §1** — it changes what MCP exposes.

### 0.7 Notebook: `collection.get(limit=500000)` raises — **done 2026-10-17**

**[V]** `InternalError: too many SQL variables`. Chroma 1.5.9 binds one SQL variable per
row; SQLite caps at 32766. Measured ceiling: 20,000 works, 40,000 fails.

Drop-in replacement, verified to pull all 415,006 in 38 s:

```python
def get_all_metadatas(collection, batch=20_000):
    """collection.get(limit=N) binds one SQL variable per row; SQLite caps at
    32766, so anything over ~32k raises 'too many SQL variables'. Page instead."""
    out, offset, total = [], 0, collection.count()
    while offset < total:
        r = collection.get(limit=batch, offset=offset, include=["metadatas"])
        got = r.get("metadatas") or []
        if not got:
            break
        out.extend(m for m in got if m)
        offset += len(got)
    return out
```

`include=["metadatas"]` matters independently — the default also pulls `documents`,
which is 375 MiB on this store.

Affects `notebooks/documents/github_chroma_query.ipynb` cell 21 and any sibling notebook
using the same pattern.

### 0.8 Collapse the two API-key stores

**[V]** `.keys/` (read by `set_*_env` in `apps/agentic/core/utils.py`, used only by the
five notebooks) and `.env` (read by `load_dotenv` in `api/main.py`, `mcp_server/server.py`,
`apps/core/environment.py`, `clients/bin/fred.py`, used by all app code) hold the same
secrets with no sync.

`set_langsmith_env()` does a bare `os.environ[...] = ...`, so a notebook **overwrites** the
good key. On 2026-10-17 `.keys/.langsmith_key` held a Feb-2025 token that was revoked for
ingestion but still valid for reads — `GET /info` → 200, `POST /runs/multipart` → 403.
Every notebook trace was silently discarded for ~20 months. Synced as a stopgap; old token
at `.keys/.langsmith_key.revoked-20250201.bak`. The other six keys matched.

Point `set_*_env` at `.env` and delete `.keys/`, or document loudly which is canonical.

---

## Phase 1 — expose search over MCP and test from Goose

Gate: Phase 0 complete, because exposing a search whose grader is nondeterministic and
whose filters silently return nothing would make MCP testing uninterpretable.

### 1.0 The design is settled — see `yada-document-mcp-design.md`

**Written 2026-10-18, revised the same day.** The tool surface, result contract, resolution
rules, manifest and build order are specified there. In brief: **one tool per store** —
`search_github` and `search_library` — each both searching and describing over that store's
three filters; the client proposes filter values and the server resolves them against a
20 KB manifest; a value that resolves to nothing is answered in 0.01 ms without searching.
§§1.1-1.3 below are superseded by it; §1.2a (field titles name the metadata key) survives
and is folded in.

### 1.1 Decide the tool surface — SETTLED: one tool per store

The info agents to expose: `CodeRepoAgent`, `ResearchLibraryAgent`, and — pending §2.4 —
`FredDataInfoAgent` / `ETFDataInfoAgent`.

The question was: **one `search_documents(source, query, filters)` tool, or one tool per
store?** The first draft of the design doc chose one. That was wrong, and the measurement
that settles it is that the two stores share **no filter at all** — `CodeRepoFilters` is
`{account, ext, repo}`, `ResearchLibraryFilters` is `{authors, shelf, title}`, and the only
common field is the query text. `source` was therefore not a filter but a discriminator
deciding which other parameters were legal, which a flat tool signature cannot express. The
full argument and its four consequences are in `yada-document-mcp-design.md` §2.1.

The schema-tax argument for one tool (a figure attributed to the migration plan, which
does not contain it — see `yada-document-mcp-design.md` §2.2)
survives but is weak: the two tools publish three filters each rather than six between them,
so the filter half of the tax is unchanged and only the shared `query`/`field`/`limit` block
is duplicated.

The orchestrator point is unaffected either way — its inter-delegate routing is ~40% of its
prompt and dies in the MCP model, and the client does that routing regardless of whether it
picks a tool name or a `source` value. Picking a tool name is the easier of the two.

### 1.2 Return structured hits, not a prose blob

**[V]** Today `_retrieve` concatenates `Document {i}:\n{page_content}` into one string and
`_generate` writes prose over it. For MCP this should return **structured content** — one
record per hit with `path`/`title`, score, the metadata header from §0.6, and the snippet
— so the client can render, rank and cite them.

This is also the natural place to satisfy the user's "return top n hits rather than just
the best" (§2.1): over MCP, top-n *is* the result shape.

### 1.2a Form field labels must name the metadata key

**User's call, 2026-10-18.** When the research-document load form is rebuilt as an MCP
elicitation form, the date field's display name is **`published_date`**, not "Date".

The reason generalises past this one field. Every failure in Phase 0 that produced a
silent zero came from someone naming a field that does not exist — `author:` when the key
is `authors`, `date:` when there is no date qualifier, `topic:` against prose sentences.
A form that says "Date:" while writing `published_date` teaches the wrong word to the one
audience guaranteed to be looking at it.

Current state of the web form (`html/js/forms.js`): six of seven labels already match
their field exactly in title case — Filename/`filename`, Path/`path`, Title/`title`,
Authors/`authors`, Topic/`topic`, Shelf/`shelf`. Only "Date" did not. Changed to
"Published Date", which maps unambiguously to `published_date` and keeps the existing
title-case convention; use the literal `published_date` instead if the snake_case is
wanted verbatim.

**Rule for the MCP elicitation schema:** each field's `title` is its metadata key in title
case, and nothing is labelled with a word that is not a real key. The same applies to any
hit record returned by `search_documents` (§1.2) — if a result displays "Date", a user
will reasonably try `date:` and get nothing.

### 1.3 Wire into `mcp_server/server.py` and test from Goose

Follow the pattern already proven for the plot App. Checklist from that work that applies
here: keep logs on stderr (stdio JSON-RPC corrupts otherwise), set `json_response=True`,
and construct `MCPServer` **after** the tool decorators have run.

### 1.4 Re-run the failing queries and read the traces

**[V]** Tracing now works end to end (fixed today). **[V]** But retention is 14 days and
the workspace held **zero** runs of any age before today — so the "pull traces of the
user's past failing queries" experiment the reports kept recommending **cannot be done
retroactively**. Traces must be generated fresh.

Once MCP search runs from Goose, replay the known failures (`Matthaeus`, `repo:yada`,
the ones the user hits in practice) and record per query: what `where` was emitted, how
many hits came back, how many the grader dropped.

---

## Phase 2 — retrieval quality

Gate: MCP working from Goose, so improvements can be judged against real use.

### 2.1 Top-n hits instead of a single best answer — **done 2026-10-18**

Pulled forward ahead of Phase 1 once it was clear the change is 27 lines inside one
node, with no graph change.

**What changed.** `DocumentGrade(relevant: bool)` graded one chunk per LLM call, in
isolation. Replaced by `ChunkRanking` — a single call that sees every candidate and
scores each 0-1 against the others. Selection is then:

1. `grade_min_score = 0.15` (absolute) — if even the best chunk is below it, nothing
   retrieved is relevant, return empty honestly.
2. `grade_relative_floor = 0.5` — keep chunks scoring at least half the *best observed*
   score. Relative, so it adapts to the distribution and cannot empty the set.
3. `grade_top_n = 8` — hard cap.

The two thresholds answer different questions and that distinction is the whole design:
*"how many of these candidates are worth keeping"* is comparative; *"is any of this about
the question at all"* is not. Getting that wrong first time produced a real bug — with a
purely relative floor, an off-topic query scored every chunk 0.0, the floor became
`0.0 × 0.5 = 0.0`, and all 8 irrelevant chunks passed. Strictly worse than the gate.

Scores travel with each chunk as `[relevance: 0.95]`, which the generating model can
weigh and which §1.2 needs per structured hit.

**Measured** (claude-haiku-4-5, `.env` config):

| query | retrieved | kept | what survived |
| --- | --- | --- | --- |
| Which file handles MIDI output? | 8 | 2 | both `lib/zgomot/drivers/core_midi.rb`, 0.95 / 0.90 |
| What algorithms generate fBm? | 8 | 2 | two sections of "Fractional Brownian Motion", 0.95 / 0.90 |
| OAuth / Kubernetes / DB migration (absent from zgomot) | 8 | 0 | correctly empty |

Deterministic across 5 runs. **8 LLM calls per query → 1**, ~2 s.

End-to-end, 2 chunks gave a *richer* answer than the gate's 6: three named algorithms
with complexity bounds and equations, citing shelf and section from the metadata header.

**[?] `grade_relative_floor = 0.5` is untuned.** It was not fitted to anything — on the
MIDI query a chunk scoring 0.40 missed a 0.475 floor. Whether 0.5 is right, and whether
the right value differs per store, needs a real query set. Do not treat it as derived.

**Still open from this item:** deduplication. Three of the eight github chunks were the
same file; the ranker happens to pick two of them here. Scoring makes dedup possible
(collapse by `path`, keep the best-scoring chunk) but it is not implemented.

User's request. Two distinct changes hiding in one sentence:

1. **Return n ranked results** rather than one synthesized answer — largely delivered by
   §1.2's structured content.
2. **Stop the binary grader from emptying the result set.** **[V]** `grade` currently
   drops chunks outright and `_grade_documents` can empty the context entirely. Replacing
   the keep/drop decision with a *score* and returning the top n by score means a weak
   result set degrades instead of vanishing. This is the scoring loop the user proposed.

**[?]** Drop rates measured by the audit (research_library 57.8%, github unfiltered 85.9%,
github filtered 45.3%) are each one roll at temperature 0.7 — re-measure after §0.1 before
using them to justify anything.

### 2.2 LLM judge with an agentic loop in the graph

User's request. The graph is **[V]** linear today — `retrieve → grade → generate`, no
loop. An agentic version would let a judge send work back: reformulate the query, widen
or drop filters, fetch more, then re-judge.

Note the interaction with §0.3: a retry-unfiltered fallback is the degenerate, zero-LLM
case of exactly this loop. Build §0.3 first, see how much it recovers, then decide how
much judgment the loop actually needs to add. Design questions: termination condition,
max iterations, and whether the judge is a separate cheap model or the generating model.

**[A]** Note `fred`/`etf` have **no** grade node at all, so "add a loop" is not uniform
across the four stores.

### 2.3 Fix the author contract properly — **mechanism decided 2026-10-24: store a list**

Chroma metadata accepts lists, and `$contains` matches an element (verified, chromadb
1.5.9). Storing `authors` as a list makes every author reachable — **27 of 27**, against
**7 of 19** today where only sole authors can be matched exactly — and the vocabulary gets
*smaller*: 191 tokens for 27 individual names against 250 for 19 comma-joined strings.

**The list carries surnames too** — `["Troy Stribling", "Stribling", ...]` — which makes
`$contains "Matthaeus"` work directly. A surname unifies the spelling variants: all five
surnames covering more than one full name are the same person written differently
(Goldstein, Matthaeus, Oughton, Stribling, Taleb), with zero genuine collisions. Vocabulary
goes to 49 values / 293 tokens; the per-chunk list roughly doubles. Resolution survives as a
fallback for misspellings and first-name-only references. And `$eq`/`$in`
stop working on a list field, so query construction changes shape. See
`yada-document-mcp-design.md` §4.

Requires the §3.0 rebuild, since it is a metadata change.

**[A]** 19 distinct `authors` values, 12 multi-author, 64 titles — small enough to
enumerate. 690 of 4,875 chunks (14.2%) are unreachable by any author filter; single-author
papers fail on one token of drift ("Alan Sokal" vs stored "Alan D. Sokal" costs 191
chunks). Either `$in` over known values at `research_library_filters_to_where`
(`apps/agentic/core/llm_filter_extractor.py:430-438`), or a normalized multi-valued field
at load time.

### 2.3a Normalise the research_library date metadata

**Found 2026-10-18** by the user running §"metadata keys" of
`notebooks/documents/document_store_queries.ipynb` — the coverage column made it visible.
Same class as §2.3: the field cannot support the filter people expect of it.

**Two mutually exclusive fields partition the corpus.**

| field | chunks | distinct values | documents |
| --- | --- | --- | --- |
| `published_date` | 4,752 (97.5%) | 52 | all but two |
| `document_date` | 123 (2.5%) | 2 | "What is Fragility?", "Probability as Logic" |

`BOTH = 0`, `NEITHER = 0` — every chunk has exactly one. Two loader eras, never reconciled.

**And `published_date` is not one format but five:**

```
ISO            2010-05-01, 2019-12-02        2 distinct
long           Dec 19, 2020                 38 distinct
abbreviated    Feb. 19, 2017                 \
full month     July 18, 2021                 / 11 distinct, unrecognised by a strict parser
slash          11/12/2018                    1 distinct -- AMBIGUOUS, Nov 12 or Dec 11 is unknowable
```

So a date filter is not merely unwired, it is **unwireable** until the values are
normalised. Any range comparison over these strings is meaningless, and one value cannot
be resolved at all without knowing the source convention.

**Do:** normalise to ISO at load time in the research_library loader, collapse
`document_date` into `published_date`, and resolve `11/12/2018` by hand against its source
document. Only then wire a `before:`/`after:` qualifier for this store — note those
currently work on github only, via `ts_unix`, which research_library lacks entirely.

### 2.4 Audit `fred` / `etf` for the same extract-then-equality pattern

**[?]** They share `_in_filter` and the same extract-then-equality shape and **were not
tested**. Do not call them healthy until they are.

### 2.5 Prune the github corpus by displacement, not volume

**[A]** Only 41% of top-10 is answerable. But the causal story in the original reports
inverts: base64 is 43% of the corpus and only **24% of top-10 (0.56× base rate)**. The
over-weighted noise is HTML/KaTeX (**2.8×**) and LICENSE boilerplate (**25×** — `LICENSE.md`
was the #1 hit for two Brownian-motion queries).

So the order is displacement-per-chunk, not size: LICENSE/boilerplate (339 chunks, 25×) →
`_site/` + `_production/` duplicate renders (23,592, 2.8-4.1×) → `.ipynb_checkpoints/`
(32,711) → notebook output payloads (178,743, 0.56×). **The base64 purge belongs last**,
not first: it removes 43% of the index to recover 24% of top-10 slots.

**[V]** `GitLoader` is constructed with no `file_filter` at all
(`github_document_loader.py:173`), which is where most of this should be enforced.

### 2.6 Deterministic chunk ids

**[A]** Chroma ids are random uuid4, regenerated on delete-then-insert reload (reproduced:
0 id overlap across a reload of identical content). A hash of `account/repo/path/start_index`
(and `series_id` for catalogues) makes reloads idempotent and is the **precondition for
incremental re-index**, which is what makes a refresh schedule affordable.

**[A]** Related and worth checking before any reload: `fred_document_loader.py` has zero
`delete` calls, so re-running it would duplicate all 145,679 docs.

### 2.7 Refresh stale repos

**[A]** 7 repos lag, not 1. `alef` is **533 days** behind the live working repo (the
reports' 342 was measured against the wrong reference); `troystribling.github.io` is 756
days. There is no scheduled refresh. Depends on §2.6 to be affordable.

### 2.8 Delete `RAG_SCORE_THRESHOLD`

**[A]** Silently dropped by `langchain_chroma` under `search_type="mmr"`. Wiring it up is
*worse* than removing it: observed relevance band is 0.511-0.646, so 0.5 passes everything
and 0.52 zeroes a working query.

---

## Corrections owed to other documents

**[A]** `sefer/planning/yada-mcp-migration-plan.md` has two claims the audit overturned:

1. **§5.3 is not broken by uuid4 ids.** It passes `series_id`/`ticker` — Chroma *metadata*,
   re-derived identically on reload — and Postgres `cache_id`/`report_id`. No Chroma id is
   exposed anywhere. Record the real constraint instead: there is no durable chunk handle,
   so no incremental re-index (§2.6).
2. **A Postgres structured metadata-filter search path already exists** — 3 live GIN
   indexes from migration `0001`, `metadata_filter.metadata_where`,
   `report_cache._search_by_title_sync`, exposed as `list_time_series`. The
   don't-migrate-to-Postgres recommendation still stands, but the reason is "no *vector*
   search", not "no search". Do not plan to build the metadata-filter layer twice.

**[V]** The `pgvector not installed` / `alembic at 0001` / `empty tables` premises are
confirmed in both `yada` and `yada_dev`, and `0001` is **head**, not lagging.

---

## Known-unknowns — do not quote these as fact

- **[?]** All grader drop rates — one roll each at temperature 0.7 (§0.1).
- **[?]** MMR actively preferring base64 is a mechanism, not a measurement; the 24% figure
  is the *pre-MMR* similarity ranking.
- **[?]** Recall was measured on ~10 hand-written queries, never on real user traffic, and
  there is no trace history to compare against (§1.4).
- **[?]** Whether `fred`/`etf` share the equality-vs-list defect (§2.4).
- **[?]** FRED loader duplication on re-run is inferred from absent `delete` calls, not
  executed (§2.6).

---

## 3. Deferred

### 3.0 Rebuild the document stores — do the data fixes here

**Planned 2026-10-18 at the user's request:** finish the code work, then rebuild. Several
defects are fixed in code but survive in the data, and a rebuild is the only moment some
of them can be addressed at all.

**Carry these into the rebuild:**

1. **Drop the `document_date` key.** 123 chunks carry it because
   `load_research_document` wrote the form's field name straight into Chroma while
   `_append_research_document_metadata` renamed it to `published_date` for the yaml — two
   sinks, one dict, disagreeing. Renamed everywhere in code (form model, tool schema,
   function parameter, `meta_data`, `html/js/forms.js`); the 123 existing chunks need the
   rebuild. Exactly two documents are affected: "What is Fragility?" and "Probability as
   Logic".
2. **Normalise `published_date` to ISO** (§2.3a) — 52 distinct values across five formats,
   one of them (`11/12/2018`) ambiguous and needing a human decision.
3. **Normalise `authors`** (§2.3) — the comma-joined string that makes author filters
   unsatisfiable. A rebuild is the chance to store a normalised multi-valued field.
4. **Deduplicate `research_documents.yml` first.** `_append_research_document_metadata`
   appends without checking for an existing record, so "Probability as Logic" has **six**
   entries with conflicting `authors` ('E. T. Jaynes' / 'E.T. Jaynes'), `published_date`
   ('Jan 01, 2003' / '2003-01-01' / '1990-01-01'), `shelf` ('jaynes' / 'publications') and
   four different `topic` texts. This yaml is the input to the rebuild, so it must be
   cleaned before, not after.
5. **Drop the redundant github metadata keys.** Verified identical across all 415,006
   chunks: `file_name` == `filename`, `file_path` == `path` == `source`,
   `commit_ts` == `ts_iso`, `commit_ts_unix` == `ts_unix`. Sixteen keys carrying about
   eleven facts, roughly 63 MB of stored metadata. Note `before:`/`after:` filter on
   `ts_unix`, so pick which name survives before deleting either.
6. **Apply a `file_filter`** (§2.5) — `GitLoader` is constructed without one. Prune by
   displacement, not volume: LICENSE/boilerplate (25x over-represented), `_site/` and
   `_production/` duplicate renders, `.ipynb_checkpoints/`.
7. **Deterministic chunk ids** (§2.6) — makes the rebuild idempotent and is the
   precondition for incremental re-index afterwards.
8. **Include `glyfish/yada`** (§3.1) — 167 files, currently 0 chunks.

**Switch the embedding model while you are here.** The stores are on
**`text-embedding-ada-002`**, which nobody chose — `OpenAIEmbeddings()` is constructed in
`chroma_document_loader.py:33` with no `model=` argument, so it takes langchain's legacy
default. `text-embedding-3-small` is the same 1536 dimensions, scores better on MTEB, and
costs a fifth as much. Query and index embeddings must match, so **a rebuild is the only
time this can change.**

| model | $/1M tokens | rebuild cost |
| --- | --- | --- |
| `text-embedding-ada-002` (current) | 0.10 | **$8.30** |
| `text-embedding-3-small` | 0.02 | **$1.66** |

Measured 2026-10-18 from live chunk sizes: github 415,006 chunks at ~786 chars average
(326 M chars) plus research_library 4,875 at ~1,120 (5.5 M chars) — about **83 M tokens**.
`fred` (145,679 chunks) and `etf` (36,475) are excluded; those move to Postgres.

**Sequence:** clean the yaml → fix remaining loader-side normalisation → rebuild → re-run
`notebooks/documents/document_store_queries.ipynb` and confirm the §"metadata keys" cell
shows no partial-coverage surprises.

### 3.1 Reload `glyfish/yada` into the github store

**Deferred 2026-10-18 at the user's request.** The code is fixed; only the data is stale.

`repo:yada` still matches **0 of 415,006 chunks**, so it remains a live example of a filter
that is syntactically valid, names a repo that exists on disk, and returns nothing. Until
this runs, that failure stays reachable from the agent and from §6 of
`notebooks/documents/document_store_queries.ipynb`.

**What is already done.** The cause was `GITHUB_LOCAL_PATH = ".repos"` being relative:
GitLoader resolves each file against that prefix when asking git whether it is ignored, and
the yada clone's own `.gitignore` line 2 is `.repos`, so the probe path self-matched and
every file was reported ignored. One clone of 103 — only yada's `.gitignore` carries that
line. Fixed twice: `os.path.abspath` at the GitLoader call (`f1c9b74`) and
`GITHUB_LOCAL_PATH` anchored to the repo root (`895b8e9`).

```
git check-ignore -v ".repos/glyfish/yada/README.md"  ->  .gitignore:2:.repos   IGNORED
git check-ignore -v "README.md"                      ->  (not ignored)
```

**What a reload picks up**, measured 2026-10-18:

```
167 files, 7.3 MB of text
.md 69 | .py 59 | .ipynb 12 | .js 8 | (none) 3 | .json 3
```

**Open question before running: include the 12 `.ipynb` files?** The audit found notebooks
are the main index pollutant — 46% of github chunks are `.ipynb`, much of it base64 output
that displaces real code in ranked results — and `GitLoader` is still constructed with no
`file_filter` (§2.5). Indexing yada's notebooks adds a little more of the same. Either run
it as-is and let §2.5 clean up uniformly later, or exclude `.ipynb` now and accept that
yada is filtered differently from the other 102 repos.

**Safety.** `load_github_repo` calls `_delete_repo(account, repo)` before re-adding. For
yada that deletes nothing (0 chunks exist), so it is effectively append-only. It writes to
the 11 GB store and costs embeddings for 7.3 MB.

**Rejected alternative: deleting `.gitignore` from the clone.** It would work — the clone is
pristine, `git status --ignored` reports 0 ignored paths — but it is the wrong layer. It
does not survive a `git pull` or re-clone, since `.gitignore` is tracked; it fixes only this
repo, while any future repo whose `.gitignore` names the local path breaks identically; and
the zero-ignored-paths state is luck, not a property — run anything in that clone and
`__pycache__` appears, at which point removing `.gitignore` means indexing bytecode,
`.db`, `.langgraph` and `clients/fred/`. The bug was yada passing a relative path into a
tool that resolves it against a repo yada does not control; the fix belongs in yada.
