# mcp 2.x upgrade — execution plan

Moves all four repos from the `mcp` 1.x line to 2.x, and replaces the deprecated
`langchain-mcp-adapters`. Supersedes the "Actions" list in `meida-todo.md` §1.

**Verified 2026-10-11** against the installed packages and the repos. Every API named here was
read from source, not from documentation.

---

## 0. Current state — read this first

**yada's environment is already half-upgraded and broken.** `mcp 2.3.0` was installed on
2026-10-04 18:32 without the rest of the change:

| env | mcp | langchain | langchain-mcp-adapters |
| --- | --- | --- | --- |
| navi | 1.29.1 | — | — |
| meida | 1.28.1 | — | — |
| **yada** | **2.3.0** | 1.3.16 | **0.3.2** ← incompatible with 2.x |
| alef | 1.29.1 | — | — |

Consequences, all confirmed:

- `yada/requirements.txt:439` still says `mcp==1.29.0` — the env has **drifted from its lock**.
- `from mcp.server.fastmcp import FastMCP` raises, so `yada/mcp_server/server.py` cannot start.
- yada's test collection is **already red**: 82 collected, **2 collection errors**, both
  `ImportError: cannot import name 'RequestContext' from 'mcp.shared.context'`, via
  `tests/unit/test_assemble_delegate_output.py`. Those two files are yada's only automated MCP
  guard, so "pytest passes" is not an available success criterion until this is fixed.
- A **stale server is running**: PID 98526 (VS Code debugpy) listening on 127.0.0.1:8081, alive
  only because it loaded the old module before the upgrade. Goose is wired to it and will fail
  to add the extension once it stops.

So this plan is not optional work — it finishes a change that is already underway.

---

## 1. Step 0 — stabilise (do before any edit)

1. **Stop the stale server** deliberately: end the VS Code *yada MCP server (http)* session
   (PID 98526). Goose will not connect until it is back.
2. **Commit or stash uncommitted work**, because a git-level rollback would otherwise destroy
   it. Both repos have modifications to files this plan edits:
   - yada: `mcp_server/server.py`, `.vscode/launch.json`
   - meida: `notebooks/fbi/utils/catalog.py`, `tests/test_fbi_arrest_catalogue.py`
     (the plan edits this same test file)
3. **Push** navi's and meida's unpushed commits, so there is a remote copy.
4. **Capture the rollback record** — `pip freeze` per environment. This is the **only** record
   of navi's state, which has no lockfile at all (`pyproject.toml` only), and the only truthful
   record of yada's, which has drifted:
   ```
   for e in navi meida yada alef; do
     ~/.pyenv/versions/$e-3.14.7/bin/pip freeze > ~/Develop/scratch/freeze-$e-pre-mcp2.txt
   done
   ```
   Note meida also has a second lockfile pair (`requirements-dev`).
5. **Record the baselines** as numbers, since one is red:
   - yada: 82 collected / **2 collection errors**
   - meida: 224 passed across the three MCP test files
   - navi: no tests at all; alef: no mcp tests

---

## 2. yada — the blocked repo, do first

### 2.1 Dependencies

`requirements.in`, three edits (line numbers exact):

| line | from | to |
| --- | --- | --- |
| 13 | `langchain` | `langchain[mcp]>=1.4.0` |
| 35 | `mcp` | `mcp>=2,<3` |
| 36 | `langchain-mcp-adapters` | **delete** |

Leave line 37 (`pip-tools`) alone. Then `pip-compile`, **review the diff**, `pip-sync`.

Expect roughly 16 new distributions: `langchain[mcp]` → `fastmcp>=4.0.11,<5` → `mcp`
unpinned. A dry run resolved to langchain 1.4.4 / fastmcp 4.1.0 / mcp 2.3.0, with
`langchain-mcp-adapters` absent.

### 2.2 `apps/agentic/core/mcp_tool_registry.py` — a two-line swap

langchain 1.4.4 ships the bridge in-tree, so no hand-written conversion is needed:

```python
from langchain.mcp import MCPAdapter          # replaces langchain_mcp_adapters.client

discovered = {t.name: t for t in await MCPAdapter(servers).list_tools()}
```

Why this is a drop-in, all verified:

- `MCPAdapter.list_tools()` returns `list[BaseTool]` — specifically `StructuredTool` with
  `args_schema` and an async coroutine, the same construction the old adapter used
  (`langchain/mcp/tools.py:296-301`). `MCPToolRegistry`'s `dict[str, BaseTool]` typing and every
  downstream consumer are unaffected.
- It opens and closes the client itself (`adapter.py:240-242`), so the caller needs no
  `async with`.
- Returned tools **stay callable after the adapter exits** — each closure reopens the reentrant
  client per call (`tools.py:240-242`). This is what keeps yada's connect-once singleton valid.
- The existing `servers` dict needs **no reshaping**: fastmcp's `MCPConfig` wraps root-level
  server configs automatically (`mcp_config.py:317-330`), and `transport: "sse"` with `url` is
  accepted (`:278-285`).

Two things to decide explicitly:

- `langchain.mcp` is **beta** and warns once per process on import. Suppress at the import site
  or accept the warning.
- **With two or more servers fastmcp prefixes every tool `{server_name}_{tool_name}`**; the old
  adapter never did. yada has one server today so `required=["fred_series_observations"]` keeps
  matching — but adding a second server later silently renames everything. Worth a comment in
  the file.

### 2.3 `mcp_server/server.py` — mostly mechanical, one real trap

```python
from mcp.server.mcpserver import MCPServer    # was mcp.server.fastmcp.FastMCP
server = MCPServer("yada")                    # no host/port/json_response here any more
```

`@server.tool(name=..., description=...)` is **byte-identical** in 2.x, and
`list[TextContent | ImageContent]` still works — `TextContent`/`ImageContent` remain in
`mcp.types`.

**The trap:** every transport knob moved off the constructor onto `run()` and the app
factories, and the factories do **not** read constructor settings. `streamable_http_app()`
defaults to `json_response=False, host="127.0.0.1"`. Calling it bare on the
`YADA_MCP_DEBUG_HTTP` path would silently serve SSE-framed responses again — reintroducing the
exact 406 that `json_response` exists to prevent — with no error. Both call sites need the
keywords passed explicitly:

```python
app = server.streamable_http_app(json_response=JSON_RESPONSE, host=HOST)
server.run(transport=TRANSPORT, host=HOST, port=PORT, json_response=JSON_RESPONSE)
```

`run()`'s 2.x overloads are keyed on a literal transport and each takes its own keywords, so the
dispatch needs branching rather than one call.

### 2.4 Notebook reads

`notebooks/mcp/utils.py` reads `.inputSchema` / `.mimeType`; `notebooks/data/fred_time_series.ipynb`
and `tiingo_time_series.ipynb` read `.structuredContent` in live cells. These are **reads**, which
break; constructor kwargs like `ImageContent(mimeType=...)` still validate via a Pydantic alias.

fastmcp installs warn-once camelCase→snake_case shims covering exactly these fields — but only
**on `import fastmcp`** (`fastmcp/_compat.py`, run from `fastmcp/__init__.py:27-33`). Nothing in
`mcp` imports fastmcp. yada gets it via langchain, but only if something imports it. Prefer
renaming the reads.

---

## 3. navi — version-tolerant, not a cutover

`lib/mcp_client.py:65-66` reads `tool.inputSchema`, renamed to `input_schema` in 2.x. This is
**not** a hard cutover: the read sits inside `get_tool_schema`, whose only caller across all four
repos is `meida/notebooks/bls/utils.py:96`, reachable only from a notebook against a live server.

Use a straddle so navi works on both lines while the other repos move:

```python
schema = getattr(tool, "input_schema", None) or getattr(tool, "inputSchema", None)
```

`pyproject.toml:33` — `mcp = ["mcp>=1.0,<2"]` → `mcp>=2,<3`, and **fix the comment at :31-32**,
which wrongly says 2.0 drops SSE. It does not: `transport="sse"`, `sse_client`, `sse_app` and
`run_sse_async` all still ship.

Note navi's extra feeds **alef only** — meida and yada pin `mcp` directly in their own
`requirements.in`, so there is no pip-compile ordering constraint between them.

---

## 4. meida — DONE (2026-10-11)

`49122cc "Move to mcp 2.x"`: mcp 1.28.1 → **2.3.0**, compiled with
`--upgrade-package mcp` so nothing else moved. Both predicted traps were real —
`Settings` carries no HTTP field, and omitting `host`/`port` from `run()` binds
127.0.0.1 silently — and both are handled by `HOST, PORT` constants passed to
`run()` explicitly. **182 renames**, not the ~187 estimated: 48 in nine util
modules, 134 in notebook code cells, 8 in tests. Saved notebook outputs were
left as the record of what ran.

The "no test coverage" warning below was the one that mattered. The suite covers
the server and holds at **915**, but nothing exercises a notebook util's
`call_tool`, so all nine were run against a live 2.3.0 server on a spare port:
every one returns its structured content and navi's straddle reads the new name.

*Original plan, kept for the reasoning:*

- `mcp_server/server.py:6` — `from mcp.server.mcpserver import MCPServer`
- `:45-54` — drop `host`/`port` from the constructor
- `:977-980` — **`server.settings.port` raises AttributeError in 2.x**; `Settings` carries no
  HTTP fields. Pass host/port to `run()` explicitly. Keep `transport="sse"` — still supported.
- `requirements.in:10` — `mcp<2` → `mcp>=2,<3`, and correct the wrong SSE comment.
- Tests: `tests/test_fbi_arrests.py:1329` imports `mcp.server.fastmcp.exceptions.ToolError` →
  `mcp.server.mcpserver.exceptions.ToolError`; 7 `.inputSchema` reads across
  `test_server.py:687`, `test_fbi_arrest_catalogue.py:139,142`, `test_fbi_arrests.py` ×4.
- Notebooks: ~42 camelCase reads across 9 util modules, ~138 in `.ipynb`. **No test coverage** —
  the one test that loads `fbi/utils/mcp.py` never calls `call_tool`. Either rename them or add
  `fastmcp` *and* an explicit `import fastmcp` in each module.

---

## 5. alef — DONE (2026-10-11)

Dropped rather than upgraded. `f133dba "Stop taking navi's [mcp] extra"`: `requirements.in:7` is
now `-e ../navi`, `mcp` is gone from the lock and uninstalled from `alef-3.14.7`. **alef is out
of this migration** — three repos remain.

A consequence to carry forward: **navi's `[mcp]` extra now feeds no lockfile at all.** It exists
only so meida's and yada's notebooks can reach `lib.mcp_client`, which makes §3's bump
lower-risk than it first looked — nothing resolves against it.

*Original analysis, kept for the reasoning:*

`alef/requirements.in:7` declares `-e ../navi[mcp]`, which is the sole reason
`mcp==1.29.1 # via navi` appears in its lock (`requirements.txt:215-216`). Nothing in alef
imports `mcp`, `mcp_client` or `MCPClient` — in any `.py` or `.ipynb`. It arrived in
`3dabc38 "Take navi's declared dependencies, upgrade statsmodels, silence the warnings"`, a
dependency-tidying pass that took navi's extras wholesale; it was never a decision that alef
needed MCP.

The change: delete line 7, keep `-e ../navi` on line 6, recompile. Safe because navi's
`lib/__init__.py:19-23` imports `mcp_client` inside a `try/except` and sets it to `None` when
unavailable, so the extra is genuinely optional.

Consequences for the rest of this plan:

- **alef drops out entirely** — no mcp pin to bump, nothing to coordinate, one fewer environment
  to re-verify.
- **navi's `[mcp]` extra then feeds nothing.** It exists only so meida's and yada's notebooks can
  reach `lib.mcp_client`. §3's bump still matters for anyone who installs the extra, but it has
  no downstream consumer in the lockfiles.

---

## 6. Order and rollback

**Order:** yada first — it is the broken one and the only live consumer. Then navi (straddled, so
safe at any point), then meida, then alef. The one real coupling is that yada's registry points
at **meida's** server (`MCP_URL=http://localhost:8080/sse`), so meida's server must keep working
throughout; the straddle in navi and SSE's survival in 2.x both make that fine.

**Rollback:** `pip freeze` files from step 0, plus `git checkout` of the `requirements.in`/
`requirements.txt` pairs. For navi there is no lockfile — the freeze file is the only record.

**Success criteria**, stated as deltas from the recorded baselines rather than "green":

- yada: the 2 collection errors clear; 82 tests collect; no new failures
- meida: 224 still pass — **met**, and the whole suite holds at 915. The 224 are the
  three MCP test files only; the gap between the two numbers is where the renames
  actually landed, which is why the nine util modules were probed by hand (§4).
- `mcp_server/server.py` starts on stdio and on streamable-http, with Goose able to add the
  extension again
- `notebooks/mcp/mcp.ipynb` executes end to end under `nbconvert --execute`
