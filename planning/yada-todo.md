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
vocabulary"** — identical in dev and prod, whether the change came from a load or a copy, which
is what should be wired into the loaders regardless (`rebuild` and `is_stale` still have no
callers). Prod then needs no copy procedure of its own, only the same rule.

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
