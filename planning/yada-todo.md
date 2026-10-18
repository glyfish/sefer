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
