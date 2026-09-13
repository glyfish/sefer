# Voteview Reference — congressional roll-call ideology

Reference for **Voteview** (`voteview.com`, UCLA), the DW-NOMINATE scaling of
every congressional roll-call vote since 1789. Status: **built** — 8 series
loaded into `time_series_source`, served by the generic stored-series tools.

Voteview is the first source in meida that is neither an API nor a CDC product,
and the one that tested whether the stored-series path generalizes. It needed
**no server code**: no client module, no tool, no `source`-specific branch. See
[../time-series-source.md](../time-series-source.md).

## What Voteview publishes

Four CSVs, rebuilt as each Congress votes. Only the first two are downloaded.

| File | Size | Downloaded | Contents |
| --- | --- | --- | --- |
| `HSall_parties.csv` | 0.1 MB | yes | Party codes → names |
| `HSall_members.csv` | 6.2 MB | yes | One row per member per Congress, with `nominate_dim1`/`dim2` |
| `HSall_rollcalls.csv` | 29.8 MB | no | One row per vote |
| `HSall_votes.csv` | 701.6 MB | no | One row per member per vote |

`fetch.py` gates anything over `SIZE_GATE_MB = 100`, so the votes file cannot be
pulled by accident.

### DW-NOMINATE, and what the two dimensions mean

Each member gets coordinates in [-1, 1] fitted so that the spatial model
reproduces their votes.

- **`dim1`** is the stable economic left–right axis. Comparable across eras.
- **`dim2`** is **not** a fixed axis. It absorbs whatever cross-cutting conflict
  dominated a given era — slavery, then currency, then civil rights. Comparing
  `dim2` across eras compares different questions, which is why every series
  here reduces `dim1` only.

## The 8 series

Four measures × two chambers, `Biennial`, one observation per Congress dated to
the year it convenes.

| Measure | Units | Span | What it is |
| --- | --- | --- | --- |
| `party_predicts_position` | ratio | 1789–2025 | Distance between party medians ÷ mean within-party spread. Names no party, so it reaches back to 1789. |
| `effective_parties` | parties | 1789–2025 | Laakso–Taagepera effective number of parties. Names no party. |
| `median_gap` | dim1 | 1857–2025 | Distance between the Democratic and Republican medians. Both parties must exist. |
| `moderate_bloc` | members | 1857–2025 | Members whose `dim1` falls inside the other party's range. |

Two spans, and the split is not a coverage gap: the first two measures are
party-agnostic, the second two compare Democrats to Republicans, who do not
coexist before the 34th Congress (`TWO_PARTY_FROM = 34`).

### The representation gate

`party_predicts_position` and `effective_parties` are withheld for a Congress
where the second party holds under `BALANCED = 0.25` of the chamber. A median
computed over a 20-member remnant is not comparable to one over 200, and the
Era of Good Feelings would otherwise read as an era of consensus rather than of
one-party rule.

The gate was first set at 0.40, which discarded 53 of 119 Congresses including
the Gilded Age peak — an overcorrection for a confound worth 7.5%. At 0.25 the
gaps are the genuinely one-party Congresses and the series is otherwise whole.

## Retrieval

No live API. The CSVs are downloaded, reduced offline, and loaded:

```
utils/fetch.py  →  data/HSall_members.csv
utils/voteview_series.py  →  build_all()          # the 8 reductions
utils/catalog.py  →  export()                     # data/timeseries/voteview.jsonl
db_import/load_timeseries.py  →  time_series_source
db_import/load_catalog.py  →  series_catalog
```

Served by `timeseries_source_list` / `timeseries_source_data` with
`source="voteview"`, and discoverable through `series_catalog_search`; each
catalog row's `retrieval` block names the tool and native id.

### TTL

`TTL_DAYS = 30`, shared by all eight. They reduce from **one** download, so a
per-series TTL would schedule eight fetches of the same 6 MB file at eight
different times. The resolution is biennial and the data is historical, so a
month stale changes nothing — the same reasoning that gives the CDC volumes a
volume-level TTL rather than a per-file one.

## Notebooks

The standard trio, plus the downloader:

| Notebook | What it shows |
| --- | --- |
| `downloads.ipynb` | The two CSVs, and the size gate on the other two |
| `mcp.ipynb` | The tools over SSE — schemas, calls, the catalog |
| `walkthrough.ipynb` | Discovery → fetch → plot, no id known up front |
| `client.ipynb` | `TimeSeriesSourceClient` directly, no server |

`client.ipynb` differs from every other source's: elsewhere it drives the vendor
client, but Voteview has no per-request API, so the client beneath the tool *is*
the generic stored-series client. It ends by swapping `source` to `cdc_wonder`
through the identical call, which is the point.

## Gotchas

- **Party codes arrive as `"200.0"`**, not `"200"` — `party_code()` normalizes.
- **Presidents are in the member file** (129 rows) with a `chamber` of
  `President`. `load_panel` drops them; leaving them in shifts every median.
- **`nominate_dim1` is empty for 224 of 51,064 member-rows**, mostly very
  short tenures. Skipped rather than imputed.
- **A Congress is dated to the year it convenes** (odd years), not to the
  election. The 119th is 2025.

## Citation

Lewis, Jeffrey B., Keith Poole, Howard Rosenthal, Adam Boche, Aaron Rudkin, and
Luke Sonnet (2026). *Voteview: Congressional Roll-Call Votes Database.*
https://voteview.com/
