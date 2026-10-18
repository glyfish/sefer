# yada — document store MCP design

The interface for exposing the **github** and **research_library** Chroma stores over MCP.
Those are the two that stay; `fred` and `etf` move to Postgres with the time-series work.

Designed 2026-10-18. Every number here was measured against the live stores and the
installed `mcp` SDK on that date — nothing is quoted from a spec without checking it.
Task queue and defect list live in `document-search-tasks.md`; this is the contract.

---

## 1. The decision, in short

**One tool.** `query_documents` both searches and describes, because the same six filter
parameters mean the same thing either way and the client is a language model that can tell
which it wants.

**The server adjudicates values; the client proposes them.** Filter extraction moves to the
client — its model already has the user's words and its own cost counter. That is only safe
because the server *resolves* every proposed value against the index and says what it did.

**A 20 KB manifest serves every metadata question.** Resolution, membership, facets,
discovery and (if wanted) schema enums all read one build artifact. There is no expensive
metadata path, so no judgement about cost is required from the model.

**No orchestration instructions.** The schema carries the meaning. Prose telling a model to
call one tool before another is advisory and gets skipped — the existing
`tool_spec(requires_context=["Call repository_names first..."])` did not prevent a model
emitting `repo: yada`.

---

## 2. `query_documents`

```python
async def query_documents(
    # ---- filters: identical for searching and describing ----
    source:  Literal["github", "research_library"] | None = None,
    repo:    str | None = None,          # resolved: "zgomot", or a partial
    account: Literal["troystribling", "glyfish"] | None = None,
    authors: str | None = None,          # resolved: "Matthaeus" -> 5 full strings
    title:   str | None = None,          # resolved
    shelf:   Literal["notes","posts","publications","jaynes","reading_list"] | None = None,
    ext:     str | None = None,          # resolved; 189 distinct values
    # ---- what to do with them ----
    query:   str | None = None,          # semantic search; omit for a pure description
    field:   str | None = None,          # restrict the breakdown to one field
    limit:   int = 10,
) -> DocumentsResult:
```

`query` set → search, with facets computed free from the retrieved candidates.
`query` omitted → describe, served from the manifest.
Both → search plus a manifest-backed breakdown.

**Enums only where the set is tiny, closed and stable.** `source` (2), `account` (2) and
`shelf` (5) cost 38 tokens between them and make a wrong value unrepresentable. `repo` (101,
537 tokens), `authors` (19), `title` (64) and `ext` (189) stay free strings **deliberately** —
an enum would force the model to reproduce `'Troy Stribling, William H. Matthaeus'` verbatim,
when `Matthaeus` is the reasonable thing to say and resolution handles it.

### Why one tool rather than `search_documents` + `describe_documents`

Seven ad-hoc info tools exist today with no common shape — `repository_names()`,
`filenames_for_repository(account, repository, …)`, `research_library_titles_by_metadata(author, topic, shelf)`,
`etf_metadata_values(field)` — and their vocabulary disagrees with itself (`repository` vs
`repo`, `author` vs `authors`). Merging collapses them to one schema and one vocabulary, and
makes filters **compose with description**: *"what file types are in zgomot?"* is
`query_documents(repo="zgomot", field="ext")`, a question no current tool can answer.

The cost is that one tool with eight optional parameters is less self-evident than two
well-named ones. `query` versus `field` carries the intent.

---

## 3. The result contract

The SDK derives `output_schema` from the return annotation and populates
`structured_content` automatically — verified: a pydantic return type produced a full JSON
Schema including `minimum: 0.0, maximum: 1.0` on a scored field, published in `tools/list`.
Do not hand-build `CallToolResult`.

```python
class Hit(BaseModel):
    rank: int
    score: float = Field(ge=0.0, le=1.0,
        description="Relevance within THIS result set; not comparable across calls")
    source: Literal["github", "research_library"]
    path: str
    snippet: str
    metadata: dict[str, str]     # keyed EXACTLY as the filter parameters
    document: ResourceLink       # yada://{source}/{path} — fetch the full file on demand

class DocumentsResult(BaseModel):
    status: Literal["ok", "no_match", "unresolvable_filter",
                    "filters_relaxed", "store_empty", "retrieval_error"]
    request: str                 # the argument AS RECEIVED; may already be a client rewrite
    query: str | None            # the text actually embedded, after any stripping
    hits: list[Hit]
    facets: dict[str, dict[str, int]]     # field -> value -> count
    total: int | None
    filters_requested: dict[str, str]     # what the client proposed
    filters_applied:   dict[str, Any]     # what actually ran, incl. {"$in": [...]}
    filters_resolved:  dict[str, str]     # how: "exact" | "substring, 5 of 19" | "none"
    filters_relaxed:   dict[str, str]     # dropped to avoid an empty conjunction
    best_score: float | None
    available: dict[str, list[str]]       # on unresolvable_filter: what DOES exist
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
`input_schema` is. Publishing the same model as the tool's parameters moves the knowledge
without rewriting it.

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
4  query_documents        one tool, the contract above, over MCP.
```

Steps 1–3 are not MCP work and can be built and measured before any protocol code exists.

---

## 10. Open

- **`ask_documents`** — a second tool that runs `generate` server-side. Probably unnecessary,
  since the client is a model and hits now carry the metadata needed to cite. Decide once
  `query_documents` is real.
- **`grade_relative_floor = 0.5` is untuned** and was chosen for a generation cutoff. A hit
  list should cut looser — §2.1 in the task doc.
- **Deduplication.** Three of eight github chunks for one query were the same file. Invisible
  inside prose; conspicuous in a displayed list. Collapse by `path`, keep the best score.
- **Does a model orchestrate from the interface alone?** The premise of §1 is that schemas
  suffice. Untested, and testable the moment step 4 runs against Goose.
