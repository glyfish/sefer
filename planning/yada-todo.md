# yada — todo

---

## 1. A dark plot style

**Deferred 2026-10-11.** Goose is set to the **light** theme for now, which sidesteps both this
and the palette bug in §5.4 of `yada-mcp-migration-plan.md`. Theme support comes after a dark
style exists — the style is the hard part, the plumbing is not.

### What exists

navi ships two house styles (`navi/lib/config.py:21-22`), differing only in text size:

| style | for |
| --- | --- |
| `gly.fish.mplstyle` | notebooks, interactive display |
| `gly.fish-web.mplstyle` | PNG for embedding, where text must stay legible at fixed size |

Both are light: `figure.facecolor: white`, `axes.facecolor: white`, `grid.color: e0e0e0`, and a
12-colour cycle beginning `0067C4` (blue), `FF9500` (orange), `5600C9` (violet).

yada's three plot agents apply the web style **once, at construction**
(`bar_chart_agent.py:69`, `time_series_plot_agent.py:129`,
`time_series_report_plot_agent.py:321`).

### Why the obvious approaches are wrong

Two suggestions came from Goose's own agent. Both have problems worth recording, because they
are the approaches anyone would reach for first.

**`pyplot.style.use('dark_background')` at module level in navi** — discards the house style
entirely: the 12-colour cycle, the web text sizing, the grid treatment. It is also a global
mutation in a library that meida, alef and every notebook import, and a module-level side
effect at that.

**`pyplot.style.use(...)` per request, inside the tool** — `style.use` writes process-global
`rcParams`. The MCP server handles concurrent requests, so two overlapping plots would race and
one would render in the other's theme. Non-deterministic and very hard to reproduce.

### The shape to aim for

1. **A third style sheet**, `gly.fish-web-dark.mplstyle`, sitting beside the other two. Same
   structure, dark values. This is the actual design work: the light cycle does not invert —
   `0067C4` on a dark ground is poor contrast, so the cycle needs picking for luminance against
   dark, not flipping.
2. **Scope the application, do not mutate globally.** `pyplot.style.context(...)` around figure
   creation, or pass the style into the figure. Note even `style.context` is not safe across
   concurrent `await`s in one process, since `rcParams` is global — so either serialise plot
   rendering or set the style on the figure itself.
3. **Only then** thread a `theme` argument through the MCP tools. Default it to the host's
   `hostContext.theme` once that is trustworthy — see the caveat below.

### How the theme reaches the tool

**Only an App can know it.** `hostContext` is delivered to the app at `ui/initialize`; a plain
tool result has no view of the client's appearance. So `plot(request, theme=...)` called
directly by the model would depend on the model guessing — unreliable, and it spends tokens
carrying a UI setting.

In the App design (`yada-mcp-migration-plan.md` §5.4) the path already exists:

```
Goose  --ui/initialize-->  app (reads hostContext.theme)
app    --tools/call-->     plot(request, theme="dark")      # zero-token, no model turn
```

The theme travels client → app → tool and never enters the model's context. This is a third
argument for the App path, alongside display control and keeping image bytes out of context.

**Trust `theme`, not the variables.** Verified on the probe: Goose reported `theme=dark`
correctly while Goose was in dark mode — that field is accurate. What was wrong was
`hostContext.styles.variables`, which carried **light-palette values** alongside it
(`--color-background-primary` at luminance 1.00). So:

| field | trustworthy |
| --- | --- |
| `hostContext.theme` | **yes** — use it to select the style file |
| `hostContext.styles.variables` | **no** — do not derive plot colours from it |

The style-file approach avoids the broken half entirely: the app reports *which* theme, and
navi's style sheet decides *what the colours are*.

### Related

Bar charts render at `dpi=300` (`navi/lib/plots/dash/curve.py:348,402`) while every other plot
function uses matplotlib's default 100 — 2529×1967 against 1000×600, ~8× the pixels for the same
information. Only `bar` and `multibar` do this; `fbar` and `positive_negative_bar` do not, which
suggests it was never a deliberate policy. It costs real bytes now that images cross the wire as
base64. Worth fixing in the same pass as the dark style, since both are edits to the same file.

---

## 2. Moving prod to the new server splits the stores from the database

**Noted 2026-10-25.** A dedicated always-on server is on order, expected around 2026-12. Prod
moves there with the database; dev stays on the laptop and reaches that database over the
network (see `meida-todo.md` §4 for the connection shape).

The Postgres half is routine. The problem is what does **not** live in Postgres:

| | size | moves how |
| --- | --- | --- |
| `.db/github` | 11 GB | copy, or re-index on the new host |
| `.db/fred` | 2.4 GB | copy, or re-fetch |
| `.db/etf` | 1.3 GB | copy, or re-fetch |
| `.db/research_library` | 120 MB | copy, or re-index |
| `.repos` | 3.2 GB | re-clone — it is a git mirror, so this is free |

### The hazard: the vocabulary describes a store it cannot see

`document_vocabulary_combination` is derived by scanning a **local** Chroma directory, and
after the move it is written to a database on **another machine**. Nothing ties a row to the
filesystem that produced it, so two machines with different `.db` contents can write vocabulary
into databases on one host, and each serves whatever it finds.

The hazard is that the **store and its vocabulary can move independently**. A store copied
without a rebuild leaves prod resolving against a stale vocabulary; rows written from a machine
whose store differs leave it resolving against values its Chroma has never held. Either way a
filter resolves cleanly and the search returns nothing, with nothing to say why.

Rebuilding on prod after every copy (below) removes the first case by construction and the
second by never copying rows at all. `is_stale` remains the backstop for the one thing left —
a copy whose rebuild was skipped — and it is cheap: one check per process on first resolution,
3.8 s on github and 69 ms on the library.

### Decided: copy the store, rebuild the vocabulary, build in dev

**2026-10-25.** Copy the stores to prod initially, keep loading in dev, and re-copy. Rebuild
on prod only when that becomes tedious.

This lasts longer than the 15 GB suggests, because size and change-rate run opposite ways:

| store | size | changes |
| --- | --- | --- |
| `research_library` | 120 MB | often — every document added |
| `etf` | 1.3 GB | on refresh |
| `fred` | 2.4 GB | on refresh |
| `github` | 11 GB | rarely — only on re-index |

So **copy per store, never the whole `.db`**. The one touched most is 1% of the total.

Three things the file layout dictates. A store is two monolithic files —
`chroma.sqlite3` (6.6 GB for github) and the HNSW `data_level0.bin` (4.5 GB) — so rsync's
delta pass saves little and each sync should be budgeted as a full transfer. Nothing may hold
the store open during the copy, or the SQLite file tears; stop the prod server first. And
`.repos` (3.2 GB) is a git mirror, so re-clone it rather than copying.

**Rebuild the vocabulary on prod after the copy; do not copy the rows.** Copying a
byte-identical store does yield an identical vocabulary, so dumping the rows would work — but
it leaves two artifacts to keep paired, and pairing is the thing that breaks. Deriving the
vocabulary where it is read makes divergence *unrepresentable* rather than merely detectable,
and it holds however the store arrived: copied, rsynced, rebuilt, or restored from backup.

Verified 2026-10-25, with no API keys set at all — the builder opens the collection without an
embedding function, so `.get()` never embeds and prod needs no credentials to do this:

| store | changes | rebuild |
| --- | --- | --- |
| `research_library` | often | **0.5 s** |
| `github` | rarely | 36.5 s |

The cost falls the right way round: the expensive rebuild belongs to the store that almost
never changes.

This also collapses the special case. The rule is **"after a store changes, rebuild its
vocabulary"** — identical in dev and prod, whether the change came from a load or a copy. Prod then
needs no copy procedure of its own, only the same rule.

**Wired 2026-10-31.** The loaders now rebuild after every write, and `is_stale` runs as the
backstop at first use — which is the case a copy produces. Two things the wiring turned up
that this section assumed away: the rows were cached *once per process*, so a rebuild in the
loader's process never reached the server's, and `rows` now revalidates against `built_at`;
and `rebuild`'s own chromadb client does see writes made through langchain in the same
process, which the copy-then-rebuild plan depends on.

**The signal to stop copying is frequency, not size** — and more sharply, the day prod needs
to accept a write of its own. While every load happens in dev, copy is strictly simpler than
keeping two stores independently correct.

### The embedding switch now needs its own pass

Copying means the stores are not rebuilt on arrival, so moving
`text-embedding-ada-002` → `text-embedding-3-small` ($8.30 → $1.66) no longer rides along for
free. Do it in dev as its own change and let the copy carry it to prod — which is the same
procedure as any other load, so it costs nothing extra beyond the one rebuild.

### Watch for, but do not pre-solve

A locally-hosted model is wanted on the new machine eventually. Chat models slot into
`llm_factory` behind the existing provider switches. **Embeddings do not** — the vector store is
tied to the model that wrote it, so changing the embedding model is a full re-index of all four
stores, not a configuration change. That makes it another reason to settle the embedding choice
at move time rather than after.

---

## 3. The plot refactor

**Deferred 2026-10-31.** Finish moving the remaining agents over to MCP first, then come
back to this. Recorded now because the reason it is deferred is also the reason it would be
easy to get wrong later: the plot path already answered the §5.6 router question by default,
and a default is harder to notice than an open question.

### What is actually there

`plot` is a router behind a tool. `mcp_server/server.py:242` delegates straight to
`PlotAgent`, which owns no tools of its own and only dispatches between `BarChartAgent`
(2 plot tools) and `TimeSeriesPlotAgent` (6). So §5.6's choice — collapse the four routers
into the client's routing, or keep them as agent-backed MCP tools — was settled for this
path by porting the router unchanged, not by deciding anything.

`plot_report` is the opposite shape, and the right one: an id in, a server-rendered image
out, zero LLM below the tool.

The cost of the first shape is visible in `plot`'s own description, which has to warn the
model away from its own tool:

> this charts whatever it is given — it does not look anything up, and the result carries no
> provenance

That is the §5.3 id-passing exception written into user-facing text. `plot` takes values from
the model and draws them, and nothing downstream can tell a fetched series from an invented
one. The Tennessee incident of §5.2 is this tool's failure mode, not the chain's.

### The test to decide by

Does the router encode a **sequence** that should not be improvised, or only a **dispatch**?
Dispatch is what the client-side agent does better — it has the whole thread, a stronger
model, and the option to ask a follow-up, none of which a single-shot classifier had.

| router | what it owns | leaning |
| --- | --- | --- |
| `PlotAgent` | dispatch between bar and time-series | **collapse** — pure dispatch, deletes code |
| `TimeSeriesReportAgent` | report CRUD *and* delegation of report plotting | **split** — the CRUD is tools, the delegation is dispatch |

`TimeSeriesReportPlotAgent` is the one to look at hardest. If a report plot means batch into
groups of ≤5 → pick plot type from units → render, in that order, with each step feeding the
next, that is a sequence and belongs in code. Letting a model re-derive the order on every
call is how reports come back silently different run to run. It already runs with zero LLM
(`time_series_report_plot_agent.py:141`), so the sequence is in code today — the task is to
keep it there, not to create it.

### What rides along in the same pass

Three items already queued against the same files, cheaper done together than apart:

1. **The plot App** — §5.5 step 2 of `yada-mcp-migration-plan.md`. Wrapping the chart in a
   `ui://` resource is what keeps image bytes out of the model's context, and it is also the
   only path by which `theme` can reach the tool at all (§1 above).
2. **The dark style** — §1 above. The style sheet is the design work; the plumbing arrives
   with the App.
3. **Bar-chart dpi** — §1, "Related". `bar` and `multibar` render at `dpi=300` against
   matplotlib's default 100 for every other plot function, ~8× the pixels for the same
   information, now paid in base64 across the wire.

### Not to be confused with

This is the *shape* of the plot path. The replacement of the `<img>` payloads and the custom
web UI is §5.4 and happens regardless. This item is about which agents survive underneath.

---

## 4. Showing LangSmith cost in Goose

**Raised 2026-11-01.** The web UI already displays per-request tokens and cost. The question
is how to carry that to Goose, and the answer is not "port the existing code" — the mechanism
it uses does not exist over MCP.

### What exists

`api/main.py:253-282` (and again at `:389` for the report path):

1. Yield the `result` SSE event immediately — the comment is explicit, *"do not block on
   LangSmith"*.
2. Then poll `client.read_run(root_run_id)` up to **8 times at 1 s intervals**, waiting for
   LangSmith to finish ingesting the root run, which aggregates every subagent.
3. Yield a **second** SSE event, `meta`, carrying `input_tokens`, `output_tokens`,
   `total_tokens`, `cost_usd` and `trace_url`.

`run.total_cost` is LangSmith's own figure; `estimate_cost` (`apps/agentic/core/pricing.py`)
is the local fallback when it has not been computed yet.

### Why it does not port

**The web UI can send a second message. A tool call cannot.** SSE is a stream, so the answer
goes out at once and the cost arrives up to 8 s later on the same connection. An MCP
`tools/call` is request/response: it returns once, and there is no channel to revise it. Every
option below is a way around that one fact.

| option | latency | shows | verdict |
| --- | --- | --- | --- |
| block the tool on the poll | **+1–8 s** | LangSmith's own figure | no — the search itself is ~3 s |
| local estimate in result `_meta` | none | `estimate_cost` from token usage | **start here** |
| `trace_url` in `_meta` | none | a link, not a number | **do this regardless** — it costs nothing and is always right |
| an MCP App (`ui://`) | none | LangSmith's figure, filled in late | the only path to the authoritative number |
| a `show_cost()` tool | a model turn | either | last resort; the model must decide to call it |

**Recommended:** local estimate plus `trace_url` in `_meta` now, the App later. This is a
fourth argument for the App path in `yada-mcp-migration-plan.md` §5.4, alongside display
control, keeping image bytes out of context, and `theme` (§1 above) — an App has a second
message where a tool does not, so it can poll and update itself.

### What Goose already shows, and what that implies

**Goose displays a running session total**, not a per-request figure. Two consequences,
both of which cut against the obvious design:

1. **The labelling problem is gone.** The earlier worry here was that a cost shown in
   Goose would be read as the whole cost when it covers only yada's server-side calls.
   But Goose is already showing its own total beside it, so a yada figure is *additive* —
   the two together are the real number, and neither is pretending to be it.
2. **Per-call cost is the wrong granularity.** A line of cost appended to each tool result
   is noisy and does not sum where anyone can see it. What is wanted is a **running
   backend total** that reads alongside Goose's, so the two can be added by eye.

That makes the mechanism a per-connection accumulator rather than a per-call
measurement: add each call's cost to a total keyed by the MCP session, and report the
total, not the increment. Streamable-http carries a session id, so the key exists.

### The timing problem disappears for a running total

Per-call cost does not need LangSmith at all. The token usage is already in the LangChain
response, and `estimate_cost` turns it into dollars locally — no ingest wait, no 8 s
poll. LangSmith stays what it is good for: the aggregate and the audit trail, reachable
by `trace_url`.

One blocker, and it is small. `chroma_rag_agent.py:177` builds the ranker with
`scoring_llm_model().with_structured_output(ChunkRanking)`, which returns the parsed
object and **throws the `AIMessage` away** — so `usage_metadata` is lost today. The fix
is `include_raw=True` and unwrapping `["parsed"]`, which also hands back `["raw"]` with
the token counts on it.

### Open question before building

**Verify Goose renders custom `_meta`.** Its own docs cover `_meta.ui.resourceUri`, which
it certainly reads, but that is a field it looks for by name — not evidence that arbitrary
keys are displayed. One client is already on record silently dropping custom `_meta` from
tool results. If Goose does not show it, the only reliable channels are the result **text**
(certain, ~20 tokens a call) and the **App** (full control). One probe settles it.

### Defect found while looking — fixed 2026-11-01 (`3a578ed`)

`AGENT_LLM_MODEL=claude-opus-4-8` was not in the pricing table at all, so `estimate_cost`
returned `None` for the model doing nearly all the work, silently. Two prices that *were*
present were also wrong: `claude-opus-4-6` carried 15.00/75.00 against a real 5.00/25.00,
and `claude-haiku-4-5` carried 0.80/4.00 against 1.00/5.00 — and that one is
`SCORING_LLM_MODEL`, so **every ranker cost reported before today was about 20% low**.

Fixed, with the Claude 4 and 5 families added, a once-per-model warning when a price is
missing, and `unpriced_models()` plus a test that reads the configured models and asserts
they are priced. The failure here was never a wrong formula — it was a table going stale
by sitting still while the configured model changed around it.

### Decided: session-scoped, not monthly

**2026-11-01.** The total reported to Goose resets with the connection. It is not a
monthly figure, and the server should not try to keep one.

Two separate numbers, and only one belongs here:

| | lifetime | where it lives |
| --- | --- | --- |
| the figure shown beside Goose's | the connection | an in-process accumulator |
| monthly spend | the billing month | LangSmith, and the provider's billing page |

**Why not monthly in the server.** The displayed figure exists to be added to Goose's by
eye, and Goose's resets with its session — a monthly total summed with a session total is
not a number of anything. Beyond that, an in-memory monthly counter cannot survive the
restarts this server gets during development, so it would silently under-report; making it
survive means persisting to Postgres, which duplicates what LangSmith already stores with
real time-range queries behind it.

**Label it `since connect`, not `this session`.** yada can only observe its own MCP
connection. If Goose holds one connection across several conversations, yada's total keeps
climbing while Goose's resets, and the two quietly stop being addable. Naming the actual
measurement keeps that honest, and reporting the increment next to it makes any divergence
visible rather than silent:

```
yada backend: $0.0043 this call, $0.0871 since connect
```

Worth one probe when this is picked up: whether Goose opens a fresh MCP connection per
conversation. If it does, `since connect` and the session coincide and nothing is lost.

---

## 5. Discovery must write to a database, not to files

**Raised 2026-11-01.** Every catalogue in this project reaches its database the same way:
a discovery pass writes YAML, and a loader reads the YAML back. The file in the middle
earns nothing and loses things. Discovery should write to the owning app's database
directly, and the app that owns the database should be its only writer.

### What the file hand-off actually cost

Measured on the FRED export while building `fred_series`:

| fact | value |
| --- | --- |
| YAML on disk | `yada/clients/fred/{series,categories}/`, 13 files each, **207 MB** |
| tracked by git | **0 files** — `.gitignore:10` ignores `clients/fred/` |
| last written | **2026-01-04** — ten months stale, with no symptom |
| what regenerates it | **nothing in the repo**; `clients/bin/fred.py` only *consumes* it |
| silently absent from Chroma | `fred_international_countries_32264.yaml`, **80 MB**, 39% of the corpus, ~61,800 series |

The 80 MB miss is the whole argument. A file hand-off has no transaction, no row count and
no `built_at`, so a load that skips its largest input looks exactly like a load that
succeeded. The vocabulary then answered "no such value" for 61,800 series that exist. A
direct write either commits or raises.

### This is already built, in the right place, in meida

`meida/CLAUDE.md` states it owns "the vendor data clients (`clients/`)" and "builds the
metadata catalogs (FRED, Tiingo, BLS, BIS)". It has the schema and the tools:

- **`series_catalog`** (`alembic/versions/8f31c0a4e7d2`) — `source`, `series_id`,
  `dataset_id`, **`concept`**, `title`, `description`, `units`, `frequency`, `is_active`,
  **`facets`** JSONB, **`retrieval`** JSONB, `observation_start/end`, unique on
  `(source, series_id)`.
- **`db_import/load_catalog.py`** — upsert preserving `catalog_id`/`created_at`, prunes
  orphans, and guards description loss with `DescriptionLossError`.
- **Three MCP tools** — `series_catalog_search`, `series_catalog_entry`,
  `series_catalog_concepts`.

`source` defaults to `"cdc"` because CDC is the only source loaded. FRED belongs in the
same table as `source='fred'`.

**It also converged on the same conclusions this session reached independently for FRED.**
`series_catalog_concepts` is described as "the coarse map to pick a concept before
searching within it" — the two-level topic browse measured in
`yada-fred-etf-postgres-design.md`. And `series_catalog_search` already warns:
*"Descriptions are shared across series that differ only by facet value, so filter on
facets rather than trying to pick a series out by its prose."* Measured on FRED: **80.7%
of series share their `notes` with another series**, 19,332 of them sharing one identical
sentence. Same finding, reached twice, from two directions.

### Consequence: the FRED catalogue is in the wrong repo

`b9f7ff6` built `fred_series`, `fred_category`, `fred_series_category` and
`fred_frequency_class` in **yada's** database, with yada as the writer. That duplicates
`series_catalog` and makes yada a writer of data meida owns. The schema work holds up —
`frequency_class`, the per-class currency cutoffs, the period-overlap predicate — but it
should land as columns and facets on `series_catalog`, reached over MCP, not as four
yada-local tables.

Nothing is lost by leaving it in place meanwhile: it is behind no tool yet, and the Chroma
`fred` store still serves `FredDataInfoAgent`.

### What is still missing even in meida

1. **`load_catalog.py` reads YAML.** The same file hand-off, one repo over. Discovery
   writing to Postgres directly is the actual change, and it is meida's change to make.
2. **No full-text search.** `series_catalog_search` says "Filters are exact, not fuzzy."
   The measured FRED work — FTS over topic name plus generated concepts, which took three
   of four conceptual queries to first place — has no home yet.
3. **`is_active` is NULL on every row**, because no exporter writes it. The code comment
   says the filter was removed rather than left to silently empty every result. The FRED
   equivalent (`currently_relevant`, with per-frequency cutoffs) is computed and could
   populate it.

### Open questions

- **Does yada keep any writable store?** The document stores (`github`,
  `research_library`) are yada's own content and have no other owner, so probably yes —
  the rule is one writer per database, not one database.
- **How does discovery run?** A notebook writing to Postgres is still a person running a
  cell by hand. Whether this wants a scheduled job, a CLI, or an MCP tool is undecided.
- **Which app owns the topic layer?** Clustering plus LLM naming (~$0.36 one-time,
  measured) produces derived data about meida's catalogue. It reads like meida's, but it
  is the first thing here that is neither a vendor fetch nor a mirror of one.
