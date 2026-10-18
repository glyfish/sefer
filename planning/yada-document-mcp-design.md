# yada — document store MCP design

The interface for exposing the **github** and **research_library** Chroma stores over MCP.
Those are the two that stay; `fred` and `etf` move to Postgres with the time-series work.

Designed 2026-10-18. Every number here was measured against the live stores and the
installed `mcp` SDK on that date — nothing is quoted from a spec without checking it.
Task queue and defect list live in `document-search-tasks.md`; this is the contract.

---

## 1. The decision, in short

**Two verbs, two stores, four tools.** `search_*` retrieves documents, `describe_*`
retrieves metadata, one pair per store. The stores cannot share a tool because their filters
are disjoint (§2.3); the verbs cannot share one because a merged tool carries parameters and
result fields that are meaningless in one of its modes (§2.2).

**The server adjudicates values; the client proposes them.** Filter extraction moves to the
client — its model already has the user's words and its own cost counter. That is only safe
because the server *resolves* every proposed value against the index and says what it did.

**A 20 KB manifest serves every metadata question.** Resolution, membership, facets,
discovery and (if wanted) schema enums all read one build artifact. There is no expensive
metadata path, so no judgement about cost is required from the model.

**No orchestration instructions.** The schema carries the meaning. Prose telling a model to
call one tool before another is advisory and gets skipped — the existing
`tool_spec(requires_context=["Call repository_names first..."])` did not prevent a model
emitting `repo: yada`. This principle is what decided §2.3: a single merged tool could state
that `repo` and `shelf` are mutually exclusive *only in prose*, and would have leaned on the
exact mechanism this line rules out.

---

## 2. The four tools

Descriptions are written out in full because **they are the interface** — see §2.6. A bare
`authors: str | None` publishes `{"anyOf":[...], "default":null, "title":"Authors"}` and
tells the model nothing.

```python
async def search_code(
    query: Annotated[str, Field(description=
        "What to look for, in plain language.")],
    account: Annotated[Literal["troystribling", "glyfish"] | None, Field(description=
        "Whose repositories. Omit to search both.")] = None,
    repo: Annotated[str | None, Field(description=
        "Repository name, or a fragment of one. Need NOT be complete or exactly as stored "
        "-- it is resolved against the index. If it matches nothing the result says so and "
        "lists the repositories that exist; no search is performed.")] = None,
    ext: Annotated[str | None, Field(description=
        "File extension such as '.rb' or '.py', with or without the dot. Resolved as "
        "`repo` is. Note this store is 46% .ipynb notebooks.")] = None,
    limit: int = 10,
) -> CodeHits:


async def describe_code(
    account: ... = None, repo: ... = None, ext: ... = None,   # same three, same descriptions
) -> CodeVocabulary:
    """What is in the code store: the values available for every filter, under any
    filters given. `describe_code(repo="zgomot")` answers "what file types are in zgomot"."""


async def search_research_library(
    query: Annotated[str, Field(description=
        "What to look for, in plain language.")],
    authors: Annotated[str | None, Field(description=
        "Author name or fragment. Need NOT be complete or exactly as stored -- "
        "'Matthaeus' matches the five documents whose author list contains it. "
        "Multi-author papers are stored as one combined string, so a single "
        "contributor's name is normally a fragment. If it matches nothing the result "
        "says so and lists the authors that exist; no search is performed.")] = None,
    title: Annotated[str | None, Field(description=
        "Document title, or a fragment of one. Resolved as `authors` is.")] = None,
    shelf: Annotated[Literal["notes","posts","publications","jaynes","reading_list"] | None,
        Field(description=
        "Which collection: 'notes' research notes, 'posts' blog posts, 'publications' "
        "published papers, 'jaynes' papers by E. T. Jaynes, 'reading_list' external "
        "papers.")] = None,
    limit: int = 10,
) -> LibraryHits:


async def describe_research_library(
    authors: ... = None, title: ... = None, shelf: ... = None,
) -> LibraryVocabulary:
```

**`search_*` retrieves documents. `describe_*` retrieves metadata.** Both are searching;
they differ in what they search over and what comes back, so they are separate tools.

`query` is **required** on `search_*`. An optional `query` whose absence switched the tool
into describing put behaviour in an omission, where a schema cannot express it and a reader
cannot see it.

`describe_*` takes no `query` and no `limit` — neither means anything when the answer is a
vocabulary. That is the point of the split: a merged tool carried `limit` that was
meaningless half the time and a `hits` list that was structurally always empty.

`source` is gone: the tool name carries it.

Cost of four tools over two: **+596 tokens** of schema across both stores, about 4% of the
15-17k tax. Measured 2026-10-18.

### 2.1 Naming


`search_code`, not `search_github`. The positive examples in `document_agent.py` show how
these are actually asked for — *"Where is MIDI output handled **in my code**?"*, *"What
programming languages do I use **in my code**?"*, *"Look in **my research library** for the
definition of a Carnot Cycle."* The word "GitHub" never appears. It is the *source* of the
content, not the content, which is why the agent class is `CodeRepoAgent` and only the store
is called github.

The metadata *type* stays `GithubMeta`, after the store (`GITHUB_DB_NAME = "github"`).
That split is deliberate: the tool name is what a model routes on and must say what the
content is; the type name is internal and should say which store it came from.

More seriously, `search_github` **collides with the actual GitHub**. Under a client that also
has a GitHub MCP server, a model must choose between yada's index of 101 cloned repos and
the live API with nothing in the name to separate them. Routing from names alone is this
design's premise, so a name that mis-signals is a correctness problem, not a style one.

### 2.2 Why `search` and `describe` are separate tools

A merged `search_or_describe(query=None, …)` is representable, and it fails the same test
§2.3 applies to merging the stores: it carries fields that are meaningless in one of its
modes.

- `limit` means nothing when the answer is a vocabulary.
- `hits` is structurally always empty without a `query`.
- `facets` means two different things depending on whether `query` was given — the
  retrieved candidates, or the whole filtered subset.
- Behaviour lives in an **omission**. "Leave `query` out to get something else" is a mode
  switch a schema cannot express and a reader cannot see.

Splitting makes `query` **required** on `search_*`, which is the schema finally saying the
obvious thing: you must state what you are looking for.

The cost is +596 tokens of schema across both stores, about 4% of the 15-17k tax. Measured
2026-10-18.

There is also a plain naming argument, which is how this surfaced: with one merged tool
there is no name for the document-search half. A capability you cannot name separately is
one the interface is not expressing separately.

### 2.3 Why the two stores are separate tools


The stores look mergeable — both are Chroma, both are searched the same way — and a single
`query_documents(source, repo, account, authors, title, shelf, ext, …)` is the obvious
simplification. It does not work. Measured against the live filter models, those are six
filters only by appearance:

| | fields |
| --- | --- |
| `CodeRepoFilters` | `account`, `ext`, `repo` |
| `ResearchLibraryFilters` | `authors`, `shelf`, `title` |
| **shared** | `cleaned_query` — and nothing else |

The sets are disjoint. `source` would not be a seventh filter but a **discriminator**
deciding which other three were legal, and a flat tool signature cannot express that. Four
consequences, all avoided by keeping the tools separate:

- **The mutual exclusion could only be prose.** `query_documents(repo="zgomot",
  shelf="jaynes")` is representable and meaningless. The only place to forbid it is the
  description — the mechanism §1 rules out, with a failure already on record here.
- **§4's relaxation would mishandle it.** `repo`+`shelf` is not an empty conjunction to be
  relaxed but a category error: both values resolve, the pair matches zero, and progressive
  relaxation drops one and returns the *other store's* documents, reporting success in
  `filters_relaxed`. The mechanism built to stop silent widening would become a source of it.
- **`metadata` could not be typed.** One tool forces `dict[str, str]` or a union the model
  must discriminate; two give each store a real model. Verified against the installed SDK:
  a nested `GithubMeta` reaches `output_schema` under `$defs` with its `account` enum intact.
- **It would need a `field` parameter, and that parameter would be meaningless.** To ask
  for a breakdown you must say of what, and `field="ext"` means nothing against
  research_library — so one merged tool must take a free string where these need nothing at
  all (§2.4). A parameter that exists only to disambiguate a merge is evidence against the
  merge.

Splitting is the same argument §2.5 makes for enums — make a wrong value unrepresentable —
applied one level up, to a wrong *combination*.

**What two tools do not cost.** The case for merging is really a case against the status quo
— seven ad-hoc info tools with no common shape and a vocabulary disagreeing with itself
(`repository` vs `repo`, `author` vs `authors`). Consistent naming across two tools fixes
that as completely as one tool would, and composing filters with description still works:
*"what file types are in zgomot?"* is `search_code(repo="zgomot")` with no `query`, a
question no current tool can answer. Everything in §3–§6 is shared implementation behind
both tools, not duplicated.

The one genuine loss is a single call spanning both stores. Nothing in the codebase asks for
it — the orchestrator's "both stores are considered" at `orchestrator.py:520` is about the
fred and etf *time-series* stores, which move to Postgres. Deferred, with the shape it would
take, in §10.

### 2.4 What the filters deliberately omit


**`path`.** 9,529 distinct values in code, 64 in the library. Listing files is a bounded,
paginated affordance of its own — what `filenames_for_repository` does today — not a filter
and not a breakdown. Keeping it out is what lets a describe return the *complete* vocabulary
in one call.

**Any way to ask for one breakdown rather than all of them.** A describe returns every
field's values because they are small: 1,189 tokens for the library, 2,381 for code. A
search's facets are smaller still — they come from the 8 retrieved candidates, e.g.
`{'.rb': 6, '.rdoc': 2}`. Narrowing would save nothing on a search and would make a describe
worse, since a model that asks for one field and then needs another has spent two calls
where one would have done.

### 2.5 Enums only where the set is tiny, closed and stable


`account` (2) and `shelf` (5) cost 34 tokens between them and make a wrong value
unrepresentable. `repo` (101, 537 tokens), `authors` (19), `title` (64) and
`ext` (189) stay free strings **deliberately** —
an enum would force the model to reproduce `'Troy Stribling, William H. Matthaeus'` verbatim,
when `Matthaeus` is the reasonable thing to say and resolution handles it.

### 2.6 Field descriptions describe the SERVER, not the caller


Every description above states what yada will do with the value. None imposes a requirement
on the caller. That distinction is §1's rejection of orchestration prose, applied one level
down, and it is the opposite of how the current filter models are written:

```
account : "Must be exactly one of: 'troystribling', 'glyfish'."
repo    : "GitHub repository name as stored in the database.
           Must be one of these exact strings: [...101 values...]"
title   : "Document title with spelling corrected."
```

Those were written for a world with no resolver, where exactness was the only defence. **A
requirement is a rule the model can break silently; a described behaviour is a promise the
server keeps unconditionally.** "Must be exact" produces a model guessing at a canonical
form it has no way to know -- which is how `{'authors': 'Matthaeus'}` became a silent zero.
"Fragments are resolved, misses are reported" cannot fail, because the server does the work
either way.

Two consequences:

- **Every resolved field must say it is resolved.** The load-bearing phrase is *"need not be
  complete"*. Without it a model tries to be formal and invents a canonical string.
- **`repo`'s 101-value enumeration comes out of the description.** The manifest is
  authoritative and resolution handles fragments, so the list is redundant prose -- and it is
  the list the plan review found is bypassed anyway, since the regex path returns before the
  LLM ever sees it. The description gets shorter *and* truer.

### 2.7 What these tools replace


Seven ad-hoc info tools exist today with no common shape — `repository_names()`,
`filenames_for_repository(account, repository, …)`, `research_library_titles_by_metadata(author, topic, shelf)`,
`etf_metadata_values(field)` — and their vocabulary disagrees with itself (`repository` vs
`repo`, `author` vs `authors`). Two tools collapse them to one schema per store and one
vocabulary across both, and make filters **compose with description**, which no current tool
can do.

The cost is that search and description share one entry point per store, so the intent rests
on `query` versus `field` rather than on two tool names. That is a smaller ambiguity than the
one §2.3 removes, and unlike it, it cannot produce a wrong answer — only a redundant one.

---

## 3. The result contract

The SDK derives `output_schema` from the return annotation and populates
`structured_content` automatically — verified: a pydantic return type produced a full JSON
Schema including `minimum: 0.0, maximum: 1.0` on a scored field, published in `tools/list`.
Do not hand-build `CallToolResult`.

`Outcome` carries what both verbs owe the caller — what was asked, what actually ran, how
values resolved. `Hits` adds the documents; `Vocabulary` adds the counts. Parameterising
`Hit` by the store's metadata model is what makes `metadata` a real schema rather than an
open dict.

The two verbs share `facets`, and the field means something different in each: in `Hits` it
describes **the retrieved candidates** and is free; in `Vocabulary` it describes **the whole
filtered subset** and comes from the manifest. Same name because it answers the same
question — *what is in what I just got* — at two scopes.

Verified against the installed SDK on 2026-10-18, not assumed: a generic parameterised by
publishes `$defs: ['GithubMeta', 'Hit_GithubMeta_']` with `hits.items` a `$ref` to the
latter and `account`'s enum intact. Pydantic mangles the generic's name into
`Hit_GithubMeta_`, which is ugly in the published schema and harmless — it is a `$defs` key,
never a value a model has to produce.

```python
class GithubMeta(BaseModel):              # keyed EXACTLY as search_code's filters
    account: Literal["troystribling", "glyfish"]
    repo: str
    ext: str

class LibraryMeta(BaseModel):             # keyed EXACTLY as search_research_library's filters
    authors: str
    title: str
    shelf: Literal["notes","posts","publications","jaynes","reading_list"]

class Hit[M](BaseModel):
    rank: int
    score: float = Field(ge=0.0, le=1.0,
        description="Relevance within THIS result set; not comparable across calls")
    source: Literal["github", "research_library"]   # implied by the tool, kept so a hit
                                                    # stays self-describing once a client
                                                    # collates results from both
    path: str
    snippet: str
    metadata: M
    document: ResourceLink       # yada://{source}/{path} — fetch the full file on demand

class Outcome(BaseModel):        # shared by both verbs: what was asked, what actually ran
    status: Literal["ok", "no_match", "unresolvable_filter",
                    "filters_relaxed", "store_empty", "retrieval_error"]
    request: str                 # the argument AS RECEIVED; may already be a client rewrite
    filters_requested: dict[str, str]     # what the client proposed
    filters_applied:   dict[str, Any]     # what actually ran, incl. {"$in": [...]}
    filters_resolved:  dict[str, str]     # how: "exact" | "substring, 5 of 19" | "none"
    filters_relaxed:   dict[str, str]     # dropped to avoid an empty conjunction
    available: dict[str, list[str]]       # on unresolvable_filter: what DOES exist

class Hits[M](Outcome):
    query: str                   # the text actually embedded, after any stripping
    hits: list[Hit[M]]
    facets: dict[str, dict[str, int]]     # of the retrieved candidates only — free
    best_score: float | None

class Vocabulary(Outcome):
    facets: dict[str, dict[str, int]]     # every filter's values, from the manifest
    documents: int                        # how many documents the filters match
    chunks: int

class CodeHits(Hits[GithubMeta]):      pass
class LibraryHits(Hits[LibraryMeta]):  pass
class CodeVocabulary(Vocabulary):     pass     # same shape; the facet KEYS differ
class LibraryVocabulary(Vocabulary):  pass
```

Four fields are load-bearing and were added for specific observed failures:

- **`request`** — `_original_request` (`document_agent.py:42`) exists because *"the routing
  model tends to paraphrase… which silently drops the where-clause"*. Its `InjectedState`
  trick has **no MCP equivalent**: the tool receives an argument, not the user's sentence.
  Echoing the argument back does something better than hiding it — it makes a paraphrase
  visible to the caller.
- **`filters_relaxed`** — §0.3 retries unfiltered when a filter matches nothing and logs only
  to stderr, so `repo:yada` silently returns chunks from `BAP3` and `alef`. Without this
  field §1.4's replay would read that as working.
- **`best_score`** — separates *retrieved 8, best 0.05* from *retrieved nothing*. Identical
  today.
- **`available`** — turns a dead end into a next step.

`ResourceLink` per hit **retires the second-retrieval hack**: `FileChromaRAGAgent._generate`
re-invokes the retriever and staples a whole file onto the answer — sometimes a chunk the
ranker rejected — because prose had no way to say *"more is available here."* MCP does.

---

## 4. Resolution

Every proposed filter value is resolved against the manifest before anything else happens.

```
exact match           -> use it
substring match       -> {"$in": [all matching stored values]}
no match              -> ANSWER NOW: status="unresolvable_filter", no search performed
```

Measured on the live research_library:

| proposed | resolves to | result |
| --- | --- | --- |
| `Matthaeus` | substring, 5 of 19 | `$in` → 5 hits, correct paper at rank 1 |
| `William H. Matthaeus` | substring, 2 of 19 | works |
| `Thermodynamics` | exact | 1 value |
| `Einstein` | none | **0.01 ms**, definitive negative, no search |

**The short-circuit is the single biggest win.** Today `authors="Einstein"` costs 3.0 s and
an LLM call and returns *the wrong thing* — the filter matches nothing, §0.3 widens silently,
and one chunk by a different author is returned as though it answered. Resolution answers
correctly in 0.01 ms with no embedding and no ranker call.

**Scope the negative to the claim, not the request.** A content search for Einstein returns
`'Brownian Motion'` documents. So *"no document has Einstein as an author"* is true while
*"nothing about Einstein"* is false. Say the first, and offer the unfiltered search.

**What resolution makes impossible, and what it does not.** A single-field filter built from a
resolved value can never match zero — the value exists by construction. A **conjunction** of
individually-valid values still can:

```
repo=zgomot AND ext=.rb   -> >=1
repo=zgomot AND ext=.py   -> ZERO   (both values real, the pair empty)
repo=zgomot AND account=glyfish -> ZERO
```

So §0.3's blanket unfiltered retry is **mostly superseded** — it can now only fire on
conjunctions, where dropping every filter is far too blunt. Replace it with progressive
relaxation that drops the least-specific term and names it in `filters_relaxed`.

**Splitting the tools makes relaxation safe.** Every conjunction a tool can now express is
within one store, so the worst a dropped term costs is a broader answer from the right
corpus. A merged tool would admit `repo=zgomot AND shelf=jaynes` — two resolvable
values whose pair is empty *by category, not by coverage* — where relaxation would have
dropped one and returned the other store's documents under `status="filters_relaxed"`,
reading as a successful widening. That failure is unrepresentable here, which is why §2.3
treats it as the decisive argument rather than a tidiness one.

---

## 5. The manifest

A build artifact emitted by the loader, loaded at boot, queried in microseconds.

```
github manifest            20 KB        for 415,006 chunks / 11 GB on disk
build                      41 s         once, at index time
'repos under an account'    0 µs        vs 6.7 s live
'exts in zgomot'            9 µs        vs 4.0 s live
```

Contents: per-field value→count maps, plus the cross-tabs worth having
(`account→repo` 101 entries, `repo→ext` 865 entries). Distinct values are four orders of
magnitude smaller than the chunk count — **2 accounts, 101 repos, 189 extensions, 9,529
paths**; research_library is **19 authors, 64 titles, 5 shelves**.

**Live faceting is not an option and that is why this exists.** Cost does not scale with what
matches — Chroma scans regardless:

| filter | chunks matched | time |
| --- | --- | --- |
| `repo=zgomot` | 384 | **4.0 s** |
| one account | 110,963 | 6.7 s |
| none | 415,006 | 33 s |
| the retrieved candidates | 8 | free |

**Fingerprint it.** A manifest is a second source of truth about the index, and this
codebase's signature failure is exactly that — `.repos` self-matching a `.gitignore`, `.keys`
shadowing `.env`, `repository_names()` reading disk and reporting a repo with 0 indexed
chunks. The manifest must carry the collection id and chunk count, and the server must
compare on load and refuse or warn loudly on mismatch. Generated by the loader, never by
hand; regeneration belongs to §3.0's rebuild.

---

## 6. Extraction moves to the client

`extract_research_library_filters` is a `claude-haiku-4-5` call costing **1.03 s per search**
on the server key, invisible to the client's cost counter. Its knowledge is already a
pydantic model with field descriptions — *"Must be exactly one of: 'jaynes' (papers by
E. T. Jaynes)… Map user language: 'blog'/'posts' → 'posts'"* — which is precisely what an MCP
`input_schema` is, so the *shape* ports directly.

**The descriptions do not port unchanged.** They were written for a world with no resolver and demand exactness that resolution
makes unnecessary — `repo` carries a 101-value enumeration, `account` says "must be exactly
one of". Ported verbatim they would contradict §4. Rewrite each per §2.6.

```
today :  extract 1.0s (haiku) + retrieve 1.0s + rank 2.0s + generate 7.1s (opus)  ~11s, 3 LLM calls
MCP   :  [client extracts] + retrieve 1.0s + rank 2.0s                            ~ 3s, 1 LLM call
```

Both calls that disappear were on the server key and invisible to the client — the standing
complaint about agent-backed tools in `yada-mcp-migration-plan.md`.

**Keep the server-side extractor.** `api/main.py` still uses it, and it is the fallback when a
client passes only a raw sentence. The tool accepts both typed filters and a bare `query`.

**Accept the cost honestly:** extraction quality becomes the client's, and there is no eval
for it. Resolution catches an invalid *value*; it cannot catch a wrong *field* or a filter the
client never proposed.

---

## 7. Mechanisms considered and ruled out

**MCP completions do not apply to tool arguments.** `CompleteRequestParams.ref` is
`ResourceTemplateReference | PromptReference` — there is no tool arm. `completion/complete` is
for prompt arguments and resource-template variables, i.e. human autocomplete. Verified
against the installed SDK.

**Instructing call order in the tool description.** Advisory. The precedent is already in the
codebase and already failed.

**Enums for everything.** Only viable for small closed sets, must be regenerated with the
data, and actively harmful for `authors` — see §2.

---

## 8. What this requires of the internals

`WorkerState` is `{messages}` and nothing else, so the ranker's `(score, index, chunk)`
tuples are flattened into the string `[relevance: 0.95]` at the node boundary and both
surviving agents inherit a `_generate` that returns one `AIMessage`. **Producing this contract
is impossible without widening the state** — the interface changes to serve the contract, not
the reverse.

```python
class WorkerState(TypedDict):
    messages: Annotated[Sequence[BaseMessage], add_messages]
    hits: NotRequired[list[Hit]]      # survives intact to the MCP boundary
```

Also required: a git sha in `serverInfo` (`VERSION` is the literal `"0.1.0"`, so every build
reports identically), and a restart — the process Goose currently talks to started
**2026-10-11 18:28** and serves only `['plot', 'plot_report']`.

---

## 9. Build order

```
1  metadata capability    manifest emitted by the loader; resolve(exact|substring|none);
                          fingerprint check. Pure Python, testable in the notebook.
                          Fixes author/authors, disk-vs-index, and the limit=100_000 crash.
2  extractor consumes it  deterministic resolution, $in on widening, short-circuit answer
                          on no match, model escalation only when ambiguous or over-broad.
3  widen WorkerState      hits survive to the boundary.
4  the four tools         search_* and describe_* per store, the contract, over MCP.
                          One shared implementation; the tools differ only in which three
                          filters they publish and which metadata model they return.
```

Steps 1–3 are not MCP work and can be built and measured before any protocol code exists.

---

## 10. Open

- **`search_all(query, limit)`** — one call spanning both stores. Deferred, not rejected.
  Nothing in the codebase asks for it today and a model can call both `search_*` tools, which also tells
  it which store answered. If it is ever wanted the shape is already determined: **no
  store-specific filters**, because the cross-store case is exactly the case where none
  apply. That is what keeps it from reintroducing §2.3's problem, and it is why adding it
  later costs nothing — it is a third tool, not a change to these two.
- **`ask_documents`** — a tool that runs `generate` server-side. Probably unnecessary,
  since the client is a model and hits now carry the metadata needed to cite. Decide once
  `search_code` and `search_research_library` are real.
- **`grade_relative_floor = 0.5` is untuned** and was chosen for a generation cutoff. A hit
  list should cut looser — §2.1 of `document-search-tasks.md`, not this document.
- **Deduplication.** Three of eight github chunks for one query were the same file. Invisible
  inside prose; conspicuous in a displayed list. Collapse by `path`, keep the best score.
- **Does a model orchestrate from the interface alone?** The premise of §1 is that schemas
  suffice. Untested, and testable the moment step 4 runs against Goose.
