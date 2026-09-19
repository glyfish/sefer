# Clio-Infra at Historical Borders Reference — DataverseNL deposits

Reference for the **DataverseNL** deposits of the Clio-Infra indicators — the
same indicators as [clio.md](clio.md), with a different geography. Status: **one
dataset filed and examined** (Labourers Real Wage, `doi:10.34894/UFVNXT`,
version 1.1); nothing stored or served.

A separate source from `clio` because it differs in the two ways that matter
for managing it: its unit of geography (border periods, not modern states), and
how it is obtained (by hand, not by script).

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

## Open before building series

- **Which border scheme a stored series follows.** The CShapes rows duplicate
  the main site; the GeaCron periods are the new information but fragment one
  country into several series.
- **What to do with wrong rows**, starting with pre-1948 Canada.

## Files

Under `notebooks/clio_historical/`; `data/` is gitignored.

| Path | What |
| --- | --- |
| `utils/accept.py` | files a hand-downloaded folder, records DOI and version |
| `utils/workbook.py` | reads the `Data` sheet into polity-periods |
| `utils/documentation.py` | reads the `.docx` into its numbered sections |
| `utils/xlsx.py` | stdlib reader, copied from `notebooks/clio` |
| `explore.ipynb` | the look: layout, the comparison, Germany by border period |
| `data/raw/<doi>/` | one deposit per DOI |
| `data/manifest.json` | DOI, version, release and download dates, sha256 |
