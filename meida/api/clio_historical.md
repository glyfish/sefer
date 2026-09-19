# Clio-Infra at Historical Borders Reference — DataverseNL deposits

Reference for the **DataverseNL** deposits of the Clio-Infra indicators — the
same indicators as [clio.md](clio.md), with a different geography. Status:
**built and loaded** — 395 stored series, served by the stored-series tools like
every other stored source.

A separate source from `clio` because it differs in the two ways that matter
for managing it: its unit of geography (border periods, not modern states), and
how it is obtained (by hand, not by script).

**Mostly, it is the main site's data relabelled.** Every deposit's workbook
lists the same ~1,412 GeaCron border periods, but in all except five indicators
those rows are empty; the deposit's data is its CShapes rows, which *are* the
main site's series, already stored as `clio`. What is stored here is the rest —
one polity within one border period, from exchange rates to the pound (179),
days lost in labour disputes (117), real wages (98) and one GDP row. Compared
value by value with the main site:

| relation | series | |
| --- | --- | --- |
| `same` | 352 | the same country carries every value |
| `successor` | 38 | filed there under a modern state — Ottoman under Turkey, Prussia under Germany |
| `differs` | 1 | the Netherlands 1820–39, which includes Belgium: exactly ⅔ + ⅓ |
| `new` | 4 | Hong Kong (two), the Falklands, Yugoslavia |

So its real value is the **border label** — that the 1850 value is the German
Confederation's — and, more than the data, the **working papers**, whose units
and documentation now feed `clio`. The comparison needs a relative tolerance:
the main site keeps seven significant figures (`14.44252`), DataverseNL full
precision (`14.4425187753`); an absolute 1e-6 once called 70 series "new".

## Access — by hand only

DataverseNL sits behind **BotStopper** (Techaro's commercial Anubis). It does
not challenge automated clients, it refuses them: headless Brave, identifying
itself honestly as `HeadlessChrome`, got an immediate *Access Denied* on the
dataset page. The Dataverse API paths are behind it too. Getting through would
mean disguising automation as a person, which is not something to build on.

So datasets are downloaded in a browser and filed with
`utils.accept.accept(folder, doi=..., version=...)`. It copies the folder to
`data/raw/<doi>/` — the download is left in place — and records in
`data/manifest.json` what the files do not carry: the DOI, the **deposit
version**, the release date, the download date (the folder's own mtime, so
filing late does not misdate it), and a sha256 per file.

**Knowing what to download needs no access at all.** Every main-site workbook
cites its indicator by Handle (`10622/…`, IISH's prefix), and the Handle
resolver redirects to the DataverseNL DOI. The resolver is not behind the bot
check and only its `Location` header is read, so `utils.datasets.build()` lists
all 86 datasets — 86 distinct DOIs, all `10.34894/…` — in about 75 seconds
without a single request reaching DataverseNL. Three of the mappings were
checked against DataverseNL's own page titles. `notebooks/downloads.ipynb`
turns that into a checklist with a link per dataset, ticking off what is filed,
in three groups:

| group | datasets | why |
| --- | --- | --- |
| first | 44 | measured, with data before 1946 — where historical borders change the story |
| later | 38 | zero-filled panels and model reconstructions — the unit and paper, little else |
| last | 4 | start after 1946 — CShapes reproduces the main site; unit and paper only |

`accept()` then needs only `version=`: it reads the DOI from the workbook's
title row, collapsing whitespace and case (15 of 86 names carry doubled
spaces), and refuses a `doi=` that contradicts the title rather than filing the
wrong folder. Title matching is verified for one deposit; a title that matches
nothing raises and asks for the DOI.

If programmatic access is ever wanted, DANS (who run DataverseNL) issue API
tokens to registered users; asking for access to CC0 data is an ordinary
request.

**Refresh is manual and per dataset**, which suits data that is almost entirely
historical. The version is the staleness signal — a date says when you looked,
the version says what you got. When stored, a long refresh interval should
encode "not on a schedule" rather than a nullable `expires_at`, so the stale
tool does not report these series forever.

## A deposit

`Labourers_wage-historical.xlsx`, `Labourers_wage.docx`, Dataverse's
`MANIFEST.TXT`.

**The workbook** has one sheet, `Data`, wide by year:

| row | holds |
| --- | --- |
| 1 | the indicator — `Labourers Real Wage` |
| 2 | **the unit** — *Number of daily subsistence baskets that a daily wage buys*, stated nowhere on the main site |
| 3 | header — `Webmapper code`, `Webmapper numeric code`, `ccode`, `country name`, `start year`, `end year`, then a column per year |
| 4+ | one row per polity per border period |

Two border schemes share it and mean different things:

- **`geacron/<n>`** — a historical border period; its values lie inside its own
  start and end years; never a modern `ccode`.
- **`cshapes/<n>`** — a post-1946 state; its row holds the **whole** modern
  series, back before 1946. These rows *are* the main site's `_Compact.xlsx`.

So a pre-1946 year for a continuing state appears twice. The indicator page's
7,542 observations is this file counted naively; 1,978 country-years repeat.
`workbook.long_records` flags each value `in_border_period`.

**The working paper** is a sixteen-section template. Two sections exist
nowhere else: `7. Unit of analysis` and `13. Data quality`, which grades
sources on four tiers — central statistical agencies, historical
reconstructions, estimates, conjectures — and says real wages are estimates
before the 1920s and reconstructions after.

## The working papers — `data/documentation.yaml`

Each zip download carries a `.docx` working paper in a fixed template, and it
is the best metadata any Clio source has: title, authors, dates, the unit, an
abstract, keywords, methodology with per-country caveats, data quality, sources,
and often the full paper. `utils.documentation.build()` extracts every paper
under `data/raw/` into one YAML file, keyed by the Clio series' indicator ids.
**Every filed indicator has an entry — 76 —** 52 with a paper and 24 from a
single-file download, which have no paper but still carry the workbook's
identity and its row-2 unit (`workbook_unit`), unless row 2 merely repeats the
indicator's name. `notebooks/clio`'s unit harvest reads this file and nothing
else.

It lives in `data/`, gitignored and regenerable from the papers — but those were
downloaded by hand, so losing `data/raw/` means downloading them again.

What reading all of them turned up:

- **The paper's "Version" is not DataverseNL's.** Section 4 reads `1st version`,
  `1`, `Version 1.0`, `2nd version`, `2` — the authors' revision of the dataset.
  DataverseNL's deposit version (1.1) is in none of the files. Kept as
  `paper_version`, normalised to `version_number`; it is what changes when the
  data itself is revised.
- **"Unit of analysis" means two things.** 19 papers write *Country* — what is
  observed — and the rest write the unit (*deaths per 100,000 inhabitants*,
  *number of years*, *percentage*). Four split section 7 into 7a (analysis,
  always *Country*) and 7b (measurement). The derived `unit` takes 7b, else a
  unit of analysis that is not *Country*, and says which in `unit_source`: 34
  papers state a unit, 18 do not.
- **"Data quality" is often just the template's menu** — the four grades listed
  with no sentence saying which applies. Where a sentence follows, it is the
  assessment.
- **Section 17, "Text", is the full paper** — 37 have one, up to 64,000
  characters — and its own chapters are numbered. So a numbered paragraph is a
  section only when its name is a template heading; otherwise it is body text.
- **One deposit carries two editions.** GDP per capita has the 2013 Maddison
  update and the 2020 "long view", version 2, which runs to 2016 as the main site
  does. The latest edition is the entry, the older kept under `superseded`.
- **Six workbooks mistitle their indicator.** Three checked against the paper
  beside them — `Unifid Democracy Scores`, `Composite Wellbeing Index`,
  `Social Transfers` — and three with no paper whose abbreviations are exact:
  `…Cost of Basic Needs` (CBN), `…Dollar a Day` (DAD), `Wealth Top 10 percent
  share`. All in `WORKBOOK_ALIASES`.

### Three workbook layouts

Found by the header row, `Webmapper code`, and whatever sits above it: title and
unit (68 workbooks), title only on a sheet called `Sheet1` (10), or nothing (1).
Where there is no title, the paper's own names the indicator.

## What it adds over the main site — Labourers Real Wage

Every one of the 7,542 values compared against the main site's copy:

| | values |
| --- | --- |
| identical | 6,993 |
| same value, the main site files it under a modern successor | 292 |
| new | 191 — Falklands, Tanzania, Hong Kong mostly |
| differing | 64 — Canada, the Netherlands, Israel |

1. **The difference is mainly geography.** The main site files historical
   states under today's country — Ottoman wages under *Turkey*, the German
   Confederation's under *Germany*, Ceylon's under *Sri Lanka*. Here they keep
   their own names and borders.
2. **The Netherlands before 1840 includes Belgium.** The 1820–1839 row is
   exactly ⅔ the main site's Netherlands plus ⅓ its Belgium in every year —
   the United Kingdom of the Netherlands. The one difference that is the
   borders doing their job.
3. **The historical Canada rows are the United States.** Every value in the
   GeaCron Canada rows and in `cshapes/1420` (1925–1947) equals the US series to
   the digit, none equals Canada's; the modern Canada row `cshapes/1593` matches
   the main site 58 for 58. A labelling error, not a revision — and the main
   site's two uncoded "Canada" values for 1946–47 are the same US numbers.
4. **Israel's first row is unexplained** — `cshapes/1477` holds four values
   that look shifted by a decade.

An earlier reading reported (3) as "version 1.1 revised Canada by up to +78%".
It compared by name, and the historical Canada rows hold another country.

## Series and catalog

`clio_historical/<indicator>/<polity>_<start>_<end>`, e.g.
`clio_historical/labourers_real_wage/german_confederation_1820_1839`: only the
values inside the border period, since outside it a row repeats the CShapes
row. Facets add `polity`, `border_start`, `border_end`, `relation` and — where
the main site carries the numbers — `modern_country`. Units from the
documentation (row 2, else the paper); TTL ten years, since refresh is by hand.

**Excluded:** Canada's real-wage rows for 1925–1945 (`geacron/236`–`239`),
which hold the United States' numbers digit for digit — `EXCLUDED` in
`historical_series.py`, with the reason. Every other cross-country match is a
predecessor and its successor.

## Files

Under `notebooks/clio_historical/`; `data/` is gitignored.

| Path | What |
| --- | --- |
| `utils/accept.py` | files a hand-downloaded folder, finds its DOI from the title, records version |
| `utils/datasets.py` | every indicator's DataverseNL DOI, from the Handle redirect |
| `utils/workbook.py` | reads the `Data` sheet into polity-periods |
| `utils/documentation.py` | the `.docx` into named fields; `build()` → `data/documentation.yaml` |
| `utils/xlsx.py` | stdlib reader, copied from `notebooks/clio` |
| `utils/historical_series.py` | one series per polity per border period; `relate()`, `EXCLUDED` |
| `utils/catalog.py` | `export()` → `timeseries/clio_historical.jsonl` and the catalog |
| `notebooks/downloads.ipynb` | the checklist: 86 datasets, links, what is filed |
| `notebooks/client.ipynb` | the two database clients, no server; the Netherlands kingdom |
| `notebooks/mcp.ipynb` | over SSE: new series, a polity through its borders, successors |
| `notebooks/explore.ipynb` | the look: layout, the comparison, Germany by border period |
| `data/raw/<doi>/` | one deposit per DOI |
| `data/datasets.json` | indicator → handle → DOI → dataset page |
| `data/manifest.json` | DOI, title, version, release and download dates, sha256 — for folders filed by `accept()` |
| `data/documentation.yaml` | every working paper as named fields, keyed by indicator |
