# meida — todo

Items found while planning the yada MCP migration. Verified against the installed SDKs and the
repos on the date given.

§1 is **project-wide**, not meida-only — it is tracked here because meida is one of three repos
that must change, and its pin is the one most often cited.

---

## 1. Align the whole project on one `mcp` version

**Verified 2026-10-04.** Four environments, four different versions, and no single declared
target:

| repo | declared | resolved | installed | imports `mcp` | blocker for 2.x |
| --- | --- | --- | --- | --- | --- |
| **navi** | `mcp>=1.0,<2` (`pyproject.toml:33`, optional extra) | — | 1.29.1 | 2 files | `Tool.inputSchema` → `input_schema` |
| **meida** | `mcp<2` (`requirements.in:10`) | 1.28.1 | 1.28.1 | 15 files | `FastMCP` → `MCPServer` |
| **yada** | `mcp` (bare, `requirements.in:35`) | 1.29.0 | 1.29.0 | **0 files** | **langchain-mcp-adapters** (see below) |
| **alef** | transitive only | 1.29.1 | 1.29.1 | 0 files | none |

Nothing coordinates these. yada's bare `mcp` resolves to whatever pip picks on the day.

### The SSE comment is wrong, in two repos

`meida/requirements.in:10` and `navi/pyproject.toml:31-32` both say 2.0 "drops the SSE
transport". **It does not.** mcp 2.3.0 still declares, at
`mcp/server/mcpserver/server.py:406`:

```python
transport: Literal["stdio", "sse", "streamable-http"] = "stdio",
```

and ships `mcp/server/sse.py` and `mcp/client/sse.py`. What 2.0 actually did was **rename
classes**. `mcp/server/fastmcp.py` is now a stub that raises on import:

> *"Removed in mcp 2: `FastMCP` is now `mcp.server.mcpserver.MCPServer`. […] see the migration
> guide at https://py.sdk.modelcontextprotocol.io/v2/migration/#fastmcp-renamed-to-mcpserver"*

Correct both comments first — the wrong reason is steering decisions in two repos.

### The real blocker is in yada, and it is third-party

yada imports `mcp` in **zero** files. It reaches meida through
`langchain_mcp_adapters.client.MultiServerMCPClient`
(`apps/agentic/core/mcp_tool_registry.py:4`), and that package pins:

```
langchain-mcp-adapters 0.3.2  requires:  mcp<2.0.0,>=1.24.0
```

**0.3.2 is the latest published version** — there is no newer release that allows 2.x. So yada
cannot move to mcp 2.x while it depends on langchain-mcp-adapters.

This matters because yada's **new MCP server needs `mcp>=2`** for `mcp.server.apps.Apps`
(MCP Apps, for the report UI in the migration plan §5.5). That is a conflict *inside yada*: the
client side is capped below 2, the server side requires 2.

**The conflict is transitional.** langchain-mcp-adapters exists so yada's *agents* can call
meida's tools. After the migration the client agent lives in Goose, which calls meida directly —
yada becomes a server and stops needing an MCP client at all. Options, in rough order of
preference:

1. **Drop langchain-mcp-adapters.** `MultiServerMCPClient` is used in one file; replacing it with
   the SDK client directly removes the cap and is work the migration would do eventually anyway.
2. **Separate venv for the new server.** Ugly but immediate: the agentic app keeps
   `mcp<2` + adapters, the new MCP server runs `mcp>=2` in its own environment. Reasonable while
   the server is a single-tool prototype.
3. **Wait for upstream.** No timeline, and nothing to act on.

### Actions

1. Correct the SSE comments in `meida/requirements.in:10` and `navi/pyproject.toml:31-32`.
2. Decide the target version and declare it explicitly in all four repos — no bare `mcp`.
3. navi: `lib/mcp_client.py` reads `Tool.inputSchema`; 2.0 renamed it to `input_schema`.
4. meida: `mcp_server/server.py:6,45` — `FastMCP` → `MCPServer`, **keeping SSE** at `:980`.
5. yada: pick one of the three options above before the first MCP server lands.

Check before bumping: yada is also an MCP **client** of meida over SSE
(`TimeSeriesDataFetcherAgent`), so whichever path is taken must keep that working until Goose
takes over the client role.

---

## 2. Move off SSE to Streamable HTTP

Separate from §1, and optional. The MCP spec deprecated the two-endpoint **HTTP+SSE** transport
(`GET /sse` for the stream, `POST /messages` for requests) in favour of **Streamable HTTP**: one
endpoint, where a POST returns either plain JSON or an SSE stream, plus an optional GET for
server-initiated messages. SSE remains supported in the SDK for back-compat, so this is not
urgent.

Reasons to do it anyway:

- it is the transport the spec treats as current;
- a single endpoint passes through proxies more cleanly;
- it supports `stateless_http=True`, which came up when looking at reaching meida **from a
  browser** — that work needed CORS and a stateless server rather than a transport migration,
  but stateless mode is only available on this path;
- Goose supports it directly — its extension config carries a `StreamableHttp` variant
  alongside the SSE form.

**Keep this as its own change.** §1 is forced and mechanical; this one is behavioural. Doing both
at once makes a failure ambiguous.

---

## 3. Stale tool count in the architecture docs

`sefer/meida/architecture.md:32` states meida "Exposes 29 tools over SSE" — inside a Mermaid node
that also hardcodes `FastMCP · SSE :8080`, so §1 touches the same line.
`sefer/planning/mcp-integration.md:3` says **32 MCP tools over eight sources**, verified
2026-09-27. `sefer/yada/architecture.md:36` repeats the 29 figure, and its §2 diagram at `:61`
says "6 providers over SSE".

The architecture docs are a generation behind the integration plan. Not confirmed against a
running server — worth checking `tools/list` and correcting all three in one pass.

---

## 4. Split the database into dev and prod

**Verified 2026-10-25.** meida runs one database and has no concept of an environment:

| | meida | yada |
| --- | --- | --- |
| databases | `meida` | `yada`, `yada_dev` |
| selector | none | `YADA_ENV`, default `dev` (`apps/core/environment.py:38`) |
| URL | `DEFAULT_MEIDA_DB_URL` (`environment.py:34`), one constant | `ENVIRONMENTS` map (`:31`) |
| wrong-database guard | none | rejects a URL pointing at the other env (`:90-92`) |
| startup check | none | `verify_database` refuses to start off-head (`:108`) |

The data is what makes this worth doing. `series_catalog` holds 13,967 rows and
`time_series_source` 11,621, all fetched from FRED, BLS, BIS and Tiingo — so a mistake costs
API quota and keys to repair, not just time. Today there is nowhere to try a destructive
migration or a loader rewrite except against the only copy.

Copy yada's shape rather than inventing one: a `MEIDA_ENV` of `dev` | `prod` defaulting to
**dev**, an `ENVIRONMENTS` map, the cross-environment guard, and a `verify_database` on the
alembic head. The default matters more than the mechanism — it is the difference between
forgetting the variable and losing the catalog.

### The topology this has to fit

A dedicated always-on server is on order, expected around 2026-12. Prod moves there, the
database most likely with it, and dev stays on the laptop. So the connection shape inverts from
the usual one:

| | runs on | reaches the database by |
| --- | --- | --- |
| **prod** | the new server | `localhost` — app and database co-located |
| **dev** | the laptop | over the network, to that same server |

Both repos today hardcode `localhost` (`meida/environment.py:33`,
`yada/apps/core/environment.py:34-35`). That constant stays **correct for prod** and becomes
wrong for dev — the reverse of what a remote-prod move would normally do, and worth noting
because it makes prod the simple case. What dev gains is a host, credentials and TLS.

It also makes the cross-environment guard load-bearing rather than tidy. Both databases will
be reachable from one connection, distinguished only by a name suffix, so pointing dev at
`meida` instead of `meida_dev` becomes a one-character mistake against live vendor data.

**No staging environment**, and the new hardware argues for this rather than against it. Dev
and prod will already differ in machine, filesystem and network path — that separation is what
staging exists to simulate, and it will exist for free. A third name adds a database on the
prod host and tests nothing that dev does not already cover.

When a migration genuinely needs rehearsing against real volume, restore a prod dump into dev:
strictly more faithful than a long-lived third environment, and it cannot drift between
rehearsals. Revisit only if something outside these four repos becomes a consumer.

The cost is not neutral either. Every environment multiplies the work of each schema change,
and the catalog has to be seeded or copied per environment.

**The failure mode to design against is drift, not inadequate rehearsal.** Checked the same
day: yada's prod sat at revision `0001` while dev was at `0003`, two migrations behind, and the
only reason it surfaced was `verify_database` refusing to start. A third environment makes that
more likely, not less. Whatever is built here, make the off-head check loud and make `dev` the
default.
