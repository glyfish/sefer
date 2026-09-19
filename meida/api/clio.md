# Clio-Infra Reference — long-run economic and well-being indicators

Reference for **Clio-Infra** (`clio-infra.eu`, IISH / Utrecht), the cliometrics
collection of country-level indicators reaching back to 1500. Status:
**built and loaded** — 11,042 stored series in `time_series_source` and 11,042
rows in `series_catalog`, served by the generic stored-series tools with no
Clio-specific server code.

## What is there

| | |
| --- | --- |
| Indicators | 86, in 11 categories |
| Country series | 11,044 — sixty times what meida stores today |
| Observations | 902,291 |
| Span | 1500–2018 |
| US data | 85 of 86 indicators, but usually starting late (see below) |
| Published | one release, every file `Last-Modified` 2024-09-02 13:46:35 GMT |
| Licence | **CC0-1.0** — checked on DataverseNL for three indicators |

`notebooks/clio/inventory.ipynb` shows it: a category table, a coverage heatmap
of every indicator by decade, and US coverage per indicator.

## Access

Plain static files — no auth, no token, no bot filter. The index at
`https://clio-infra.eu/` lists each indicator in one row:

```html
<p class="list-group-item"><a href="../Indicators/LabourersRealWage.html">
  Labourers Real Wage</a><span class="badge"><a href="../data/
  LabourersRealWage_Compact.xlsx">1820 [5053] 2008</a></span></p>
```

under a category header. **Take file names from the index, never derive them**
— the page `LifeExpectancyatBirthTotal.html` has the file
`LifeExpectancyatBirth(Total)_Compact.xlsx`. The badge is the published span and
observation count.

Each workbook has three sheets, looked up by name:

| Sheet | What it holds |
| --- | --- |
| `Data Long Format` | `ccode, country.name, year, value` — already one series per country |
| `Data Clio Infra Format` | the same data, wide by year |
| `Metadata` | the source URL and a DOI citation — **no units, no definition** |

Units and definitions come from the indicator page, whose labelled panels
(`Variable(s)`, `Time period`, `Production date`, methodology...) are fetched
alongside the workbook. Where the definition does not state a unit, it will
have to be curated per indicator, as WONDER's ICD-10 code sets were.

meida's environment has pandas but not openpyxl, so the workbooks are read with
the standard library (`utils/xlsx.py`) — the same zip-of-XML approach NVSR uses.

### DataverseNL

Every indicator is also deposited on DataverseNL as **version 1.1, released
2026-01-08** — newer than the main-site files — as `<name>-historical.xlsx`
plus a `.docx` of documentation. But DataverseNL sits behind **Anubis**, a
JavaScript proof-of-work bot check, so it cannot be scripted, and its version
history renders only in a browser. Whether 1.1 changed the data or only
metadata is **not yet known**; every dataset getting 1.1 on the same day looks
like a platform-wide re-release. The main-site files are what is built from.

**Since examined, for one indicator** — see
[clio_historical.md](clio_historical.md). The DataverseNL file is not a newer
copy but a different geography: one row per historical border period, with the
main site's series as a subset. It adds the unit, a data-quality grading, 191
values, and historical states under their own names; its pre-1948 Canada rows
are mislabelled US data. It is a separate source, filed by hand.

The main site also offers `DataAtHistoricalBorders.xlsx` — 320 rows keyed by
country, border period and indicator. Downloaded, not yet examined.

## Three kinds of row

The coverage heatmap counts countries with any row, and three different things
produce rows. Treating them alike overstates how much was measured.

1. **Measured series** — real wages, height, GDP, life expectancy, inequality.
   Sparse; the coverage is the coverage there is.
2. **Panels filled for every country.** Armed Conflicts and the Gold Standard
   are 0/1 for every country every year — Internal Conflicts is 96.9% zeros.
   The twelve mineral-production indicators are 58–90% zeros, since most
   countries mine none of the metal. The Polity components are coded on scales
   of six to twenty-one values. 25 indicators in all, recorded in the inventory
   as `zero_share` and `distinct_values`.
3. **Model reconstructions at benchmark years.** The Agriculture block and
   Biodiversity are Kees Klein Goldewijk's HYDE land-use reconstructions —
   every country at exactly 1500, 1600 and 1700, then every decade. Population
   and urbanisation are estimated every fifty years before 1800.

The apparent depth before 1700 is almost entirely the third kind.

## Series and catalog

One stored series per indicator per country:
`clio/<indicator>/<country>`, e.g. `clio/gdp_per_capita/united_kingdom`. Both
slugs come from display names — the page slugs split badly
(`GDPperCapita` → `gdpper_capita`) — and all 86 indicator and 202 country slugs
are unique. **11,042 series, 902,287 observations.**

| | |
| --- | --- |
| Values | kept as the workbook wrote them (`16.62734117`, `9.307143E-5`) — a string in the storage contract |
| Frequency | the indicator's usual step: `Annual` (50), `Decadal` (33), `Every 20/50 years` (3) |
| TTL | 365 days, shared — one publication feeds every series, and it is scriptable |
| Units | from `data/units.yaml`, built from the DataverseNL deposits; see below |
| Catalog | one file per category, `clio_series_<category>.yaml` — eleven |
| Facets | `indicator`, `country`, `category`, `kind`, and `ccode` where there is one |
| Description | Clio's own definition from the indicator page — 80 distinct |

**Which country a row belongs to.** By its code. A blank code takes the code
its name carries elsewhere; the eight never-coded territories are keyed by
name. Where a recovered row lands on a year its country's coded series already
has, the coded row wins and the clash is reported. Four clashes, all real
wages: Canada 1946–47, whose uncoded values are the United States' numbers, and
Morocco 1956–57, exact duplicates. That is why the build has 2 fewer series and
4 fewer observations than the survey counted.

**`kind` travels with every series** — `measured`, `panel` or `reconstruction`
— so a catalog search can leave out rows that were never measured
(`facets={"kind": "measured"}`). The rule lives in one place,
`inventory.kind()`.

**Units are never inferred.** The main-site workbooks state none, so they come
from the DataverseNL deposits filed under `notebooks/clio_historical`, whose
`documentation.build()` records each indicator's workbook row 2 and its working
paper's unit. `units.harvest()` reads that one file into `data/units.yaml` —
generated and gitignored, like the rest of the build — preferring **row 2**,
falling back to the paper. Where both exist they agree word for word on 2 of 30,
and row 2 is usually the better label ("scale from 1 (unlimited authority) to
7" where the paper says "dimensionless, multi-nominal scale"); both are kept.
69 of the 76 filed indicators have one, and **8,820 of the 11,042 series**.
Indicators not yet filed stay unit-less.

**Loading needed batching.** One INSERT binds at most 65,535 parameters; at
about fourteen per row, 11,042 series do not fit, and neither did the catalog
prune's `NOT IN`. Both loaders now write in batches of 1,000 inside one
transaction.

**And the stored-series tools stopped enumerating.** Uncapped,
`timeseries_source_list(source='clio')` returned 3.3 MB — and its description
told a model to call it with no arguments to see what existed. It now requires
`native_ids`; finding series is `series_catalog_search`'s job, with a
`timeseries_source` filter for listing one stored source. See
[time-series-source.md](../time-series-source.md#finding-a-series).

## Gotchas

- **Blank country codes are real countries.** 861 rows carry a name and no
  `ccode`: Sudan, Canada and Morocco in some files (coded elsewhere as 729, 124,
  504), and eight territories never coded anywhere — Palestine, Macau, Jersey,
  the Isle of Man, the Cayman Islands, the Netherlands Antilles, the US Virgin
  Islands, the Cook Islands. Where a code exists, name and code are exactly
  one-to-one across all 86 files (194 each), so the name is a sound identity
  when the code is missing. An early parse dropped these rows.
- **Codes and years arrive as floats** — `56.0`, `1820.0` — like Voteview's
  party codes.
- **Not strictly annual.** 50 indicators are annual at the mode, 33 decadal,
  and the annual ones have holes: real wages have 722 gaps longer than a year
  among 4,949 steps, the longest 117 years. Plots need gaps broken, not bridged.
- **The index counts are approximate.** Spans agree for 85 of 86. Counts agree
  for 59; every other file holds *more* than its badge — three by exactly their
  uncoded rows, the rest by a few percent, consistent with badges computed from
  an earlier snapshot. The file is authoritative.
- **Series are stitched from sources, and the joins show.** Real wages for the
  United Kingdom read 92 in 1994 and 133 in 1995 — a 45% rise in one year. Levels
  are comparable only within a stretch drawn from one source, so splicing Clio
  onto BLS starts with finding the joins *inside* Clio.
- **US history is short.** US real wages run 1925–2007, 68 observations. The long
  record for most indicators is Britain and Western Europe.

## Files

All under `notebooks/clio/`; `data/` is gitignored.

| Path | What |
| --- | --- |
| `utils/fetch.py` | index and page parsers, `fetch_all()` |
| `utils/xlsx.py` | stdlib worksheet reader, sheets by name |
| `utils/inventory.py` | measures every workbook → `data/inventory.json`; `kind()` |
| `utils/clio_series.py` | one series per indicator per country |
| `utils/catalog.py` | `export()` → `timeseries/clio.jsonl` and eleven catalog files |
| `utils/units.py` | `harvest()` → `data/units.yaml`, from `clio_historical`'s documentation |
| `downloads.ipynb` | fetch → inventory → units → build → load; documents outputs |
| `client.ipynb` | the two database clients, no server |
| `mcp.ipynb` | over SSE: catalog → ids → describe → data, and filtering by `kind` |
| `inventory.ipynb` | the survey |
| `data/raw/*.xlsx` | 87 workbooks, ~36 MB |
| `data/pages/*.html` | 86 indicator pages |
| `data/downloads.json` | manifest: `Last-Modified`, sha256, badge, panels |

A full fetch is 173 requests one second apart, about six minutes, and is
idempotent — files on disk are skipped unless `refresh=True`.

## Citation

Each indicator carries its own DOI citation in its `Metadata` sheet. The
collection:

Clio-Infra, *Reconstructing Global Inequality*. International Institute of
Social History / Utrecht University. https://clio-infra.eu/
