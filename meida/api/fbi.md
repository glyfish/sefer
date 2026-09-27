# FBI Reference — the Crime Data Explorer API and the catalog

Reference for the FBI **Crime Data Explorer (CDE)** integration: monthly
offences and clearances at three geographic grains, monthly arrests for all
offences together or for any one of 47 arrest codes, annual police employment at
one grain, and the metadata catalog built out of those same calls. Built and in
use — `FbiClient` and its models in `clients/`, three MCP tools, the export in
`notebooks/fbi/utils/catalog.py`, seven notebooks, and a suite of 866 tests.

**Every figure below names what established it** — a live probe and its date, a
saved payload, the exported catalog, a test, or a module docstring. Anything not
established that way is marked **unverified**. Figures that move — counts,
coverage, catalog sizes — carry the date they were checked.

**Where this stands, as of 26 September 2026.** `fbi_offenses`, `fbi_arrests`
and `fbi_employment` are defined in `mcp_server/server.py` and served, and every
catalog entry's `retrieval` block names one of them. The work is committed — nine
commits, meida `87f0dc3` (2026-09-21) through `c53e272` (2026-09-26): the client,
catalog and first five notebooks on the 21st, then the arrest route
(`317cf56`), one filing rule plus the NIBRS reader (`25281d6`),
`enforcement.ipynb` (`4875ff9`), the eighth scope (`34adf90`) and
`withdrawal.ipynb` (`c53e272`) on the 26th. The catalog is **not**
loaded into `series_catalog` and is not meant to be: a live API source keeps its
catalog as files for the document store, and Postgres holds only the sources
whose observations are stored. The catalog's 1,150 entries are state-grain
offences and employment only — it predates the arrest route and holds no arrest
series.

The FBI fills the **enforcement** leg: crime and the police staffing that
responds to it, for the same department, from one source. That pairing is why
agency grain matters — a city panel of offences against officers per head is
buildable here and nowhere else in the repo.

## Why it is live, not stored

Like FRED, BLS and BIS, and unlike WONDER and NVSR, the CDE answers per request,
so nothing lands in Postgres. Every entry's `retrieval` block points at an MCP
tool rather than at `timeseries_source_data` — the same split CDC draws between
its Socrata series and its WONDER ones. The catalog is a discovery index over a
live API; the observations are fetched when asked for and cached downstream.

One exception, and it is a different channel rather than a different store: the
**NIBRS incident files** are downloads, cached on disk under a gitignored
directory, and nothing about them goes through the API client or the tools. See
[The NIBRS incident files](#the-nibrs-incident-files-the-second-channel).

## Access

- **Base URL:** `https://api.usa.gov/crime/fbi/cde` (`get_fbi_base_url()`;
  override with `FBI_BASE_URL`).
- **The older `crime/fbi/sapi` service is dead.** It returns 404, and the
  published Swagger still documents it, as do most tutorials. Anything written
  against `/api/estimates/...` is gone. Everything on this page was established
  by probing the live service, except the arrest vocabulary, which came from the
  CDE's own compiled OpenAPI spec (see [The arrest route](#the-arrest-route)).
- **The key is the shared api.data.gov key** (`DATA_GOV_KEY`,
  `get_data_gov_key()`) — one key for every service behind that gateway, not an
  FBI key. Self-service and instant from <https://api.data.gov/signup/>.
- **It goes in the query string as `API_KEY`, capitalised.** The CDE routes
  ignore the lowercase `api_key` other api.data.gov services accept.
- **1,000 requests an hour** with a real key. The shared `DEMO_KEY` allows about
  thirty and then returns `OVER_RATE_LIMIT` — enough to probe an endpoint, not
  enough to build a series.
- **429 and 503 are retried, not raised.** `FbiClient._get` makes up to four
  attempts, sleeping 5s, 10s then 20s, because both arrive mid-run and a
  catalogue build that does not back off loses scattered scopes rather than
  failing outright — 58 of 520 in one run, recorded in the `_get` docstring. A
  429 that survives all four becomes an `FbiAPIError` naming the allowance.
- **A 503 has two unrelated causes and the body is the only thing that tells
  them apart.** `upstream connect error or disconnect/reset before headers` is
  the CDE backend behind the gateway being down — three consecutive calls failed
  that way while the first version of this page was written, on two different
  date ranges, and three runs of `walkthrough.ipynb` died mid-way on it.
  `Client Failure Limit Exceeded` is the *other* one: too many failed requests
  against the key, which locks out every job sharing it. That is why an unknown
  arrest code is refused in `arrest_offense()` before a request is spent, and why
  a bare year is refused in `_month()` before one is.
- **The 404 page is HTML.** `FbiClient._get` refuses a body that does not start
  with `{` or `[` rather than handing a parse error to the caller.
- **Pacing, as the notebooks set it.** `catalog.PAUSE` is 3.6 seconds — the
  sustainable rate against a 1,000-per-hour allowance. `walkthrough.ipynb` uses
  `PACE = 4.0` and, on a refusal, waits a minute and retries rather than losing
  the run; `withdrawal.ipynb` records the gateway refusing "roughly one request
  in four when they arrive in a burst".

## The endpoint surface

| Route | Grain | Cadence | Serves |
| --- | --- | --- | --- |
| `summarized/national/{offense}` | the nation | monthly, 1985– | offences and clearances, counts and rates, both populations, coverage |
| `summarized/state/{ST}/{offense}` | 51 states incl. DC | monthly, 1985– | the same, plus the national comparison |
| `summarized/agency/{ORI}/{offense}` | one agency | monthly, 1985– | the same, plus the state **and** national comparisons |
| `arrest/{scope}/{offense}?type=counts` | all three | monthly, 01-2018 verified | arrests as count and rate, both populations, coverage |
| `arrest/{scope}/{offense}?type=totals` | all three | **no time dimension** | one figure per window, by offence, sex, race and age by sex |
| `pe/agency/{ORI}` | one agency **only** | annual, 1985– | officers and civilians, each split male/female, plus population |
| `agency/byStateAbbr/{ST}` | one state's agencies | — | 19,636 agencies nationally: ORI, name, type, county, NIBRS status and start date |
| `lookup/states` | — | — | the 50 states and DC, no territories |

`FbiClient.route(scope)` turns one string into the right fragment —
`national`, a two-letter code, or anything longer read as an ORI — so a catalog
entry's `scope` facet maps to a call with nothing to translate. The same routing
serves the arrest path, so nothing about scoping changes between the two.

**Ten offence slugs**, hard-coded in `clients.fbi.OFFENSES` because
`lookup/offenses` answers `{"crimeGroups": null}` for every type tried:
`violent-crime`, `homicide`, `rape`, `robbery`, `aggravated-assault`,
`property-crime`, `burglary`, `larceny`, `motor-vehicle-theft`, `arson`. They
overlap: `violent-crime` totals homicide, rape, robbery and aggravated assault,
`property-crime` totals burglary, larceny and motor vehicle theft, and **arson
is excluded from that total** and reported alone. Summing all ten
double-counts everything but arson. `lookup/states` is the one lookup that
answers; `regions` and `agency-types` return "Invalid Lookup".

**Two lookups outside the gateway answer where the gateway's do not.** The CDE
web app's own backend serves the arrest vocabulary at
`https://cde.ucr.cjis.gov/LATEST/lookup/offenses?type=arrest` and signs S3 links
at `https://cde.ucr.cjis.gov/LATEST/s3/signedurl`. Neither takes a key, neither
is on `api.usa.gov`, and neither is documented as an API.

The agency registry is the only route that enumerates anything, and the only
way to discover an ORI. Counted from `data/raw/agencies.json`, pulled
2026-09-20: of its 19,636 agencies, 11,784 are city departments, 3,029 county,
1,382 other state agencies, 1,296 other, 971 state police, 956 university or
college and 218 tribal. **16,420 are flagged `is_nibrs`, and every one of those
carries its own `nibrs_start_date`** — the transition dated locally rather than
inferred from the national dip. 2,684 of them start in 2021 and 5,652 in 2021 or
later.

## The arrest route

A second data route, added 2026-09-26 (`317cf56`), and the only one whose
request narrows by offence.

**The shape is `arrest/{scope}/{offense}?from=MM-YYYY&to=MM-YYYY&type=counts`.**
The offence is a **path segment**, not a query parameter, and it is a numeric
UCR arrest code — `11` murder and nonnegligent homicide, `260` driving under the
influence — or `all`. The `OFFENSES` slugs do **not** transfer: `violent-crime`,
`offense`, `age`, `sex`, `race`, `ethnicity` and `counts` were each refused with
400 "An invalid offense was requested". `arrest_offense()` refuses an unknown
value locally, because a key that collects enough 400s is locked out with 503
"Client Failure Limit Exceeded".

**`type` is required and takes two values.** `counts` is the monthly payload the
client reads, and it carries rates as well as counts whatever its name says.
`totals` is one figure for the whole window with no months — see
[Demographics](#demographics-and-the-route-that-does-not-exist). `rates`, `age`,
`race`, `sex` and omitting `type` all answer 400 `Invalid 'type'.` in plain text.

**The vocabulary is 48 values: 47 offences plus `all`.** `ARREST_OFFENSES` maps
code to the FBI's own name for it, taken from the `arrest_offense` schema of the
OpenAPI 3.0.1 spec behind
[the CDE's API page](https://cde.ucr.cjis.gov/LATEST/webapp/#/pages/docApi) and
cross-checked against the site's own arrest dropdown, which loads the same 48.
The spec is not fetched from anywhere: it is compiled into one of the site's
JavaScript bundles, whose hashed filename changes on every redeploy. The names
are the site's because they are also the keys of the `totals` payload's
`Offense Breakdown`, so a code joins to a total by name. `arrest_offense()`
accepts a code, an int, or a name.

**The codes partition the total.** National, 01-2023 to 12-2023: `all`'s monthly
counts sum to 7,184,021; the `totals` breakdown sums to the same figure at each
of its three granularities; and each code fetched monthly sums exactly to its own
breakdown entry — `11` 11,451, `70` 634,062, `150` 55,325, `260` 755,014, `290`
248,864. The 47 codes together fall **905 short (0.013%)**: the breakdown's
"Suspicion" (905) and "Runaway" (0) have no code. So in that window every arrest
sits under exactly one code and per-offence series add up to `all` bar Suspicion.
**Only that window was checked**; other years and scopes are **unverified**.
Whether earlier years' `all` holds runaway arrests is also unverified — the FBI's
SRS manual says runaway stopped being a required Part II offence in 2009, that
agencies may still report it, and that the FBI no longer publishes it.

**Arrests are a separate count, not the other half of a clearance.** An arrest
counts one person arrested, cited or summoned on one occasion; a clearance counts
one offence closed. One arrest can clear several offences and several arrests can
clear one, and **only 1,259,216 of 7,184,021 national 2023 arrests (17.5%) were
for the eight offences that have a clearance series** (`clients/fbi.py`
docstring). The rest were drug possession, DUI, simple assault, disorderly
conduct, "all other offenses". So the pair cannot be differenced — not in total
and not for the same offence — and in particular the difference is *not* the
clearances made by exceptional means. `enforcement.ipynb` §1 shows the pair
failing in the direction that settles it: nationally, **murder arrests exceed
homicide clearances in 39 of 40 years** (20,470 against 14,963 in 1990; 2024 is
the one year they do not, 10,312 against 10,411). `_ARREST_NOT_A_CLEARANCE` is
on every arrest response unconditionally.

**Six codes are not what their names say**, and `_ARREST_CODE_NOTES` puts a
sentence on the response for each. Figures national 2023, from the live `totals`
breakdown.

| Code | Name | What it actually is |
| --- | --- | --- |
| `50` | Assault - Not Specified | **Aggravated** assault — `totals` files its 330,173 arrests as "Aggravated Assault". Simple assault is `55` |
| `20` | Rape - Not Specified (Legacy) | Called legacy and holds *every* rape arrest that year, 18,769 |
| `23` | Rape - Not Specified | The current definition, and empty nationally in 2023. Take 20 and 23 together |
| `140` | Prostitution … (Unspecified) | Only the remainder; 141–143 hold the rest |
| `150` | Drug Abuse Violations (Unspecified) | Only the remainder — 55,325 of the 918,020 drug arrests in 150–160 |
| `170` | Gambling (Unspecified) | Only the remainder; 171–173 hold the rest |

**There is no violent-crime or property-crime code.** `ARREST_CODES_FOR` maps
each `OFFENSES` slug to the codes that make it up — violent crime is
`11 + 20 + 23 + 30 + 50`, 425,725 nationally in 2023; property crime
`60 + 70 + 90`; rape needs both of its codes. It is not a vocabulary the route
accepts, and `arrest_offense()` uses it to write the error message for the
mistake the refusal is most often for.

**History is verified back to `01-2018`** (36 unbroken months of Texas from
January 2018), recorded as `ARREST_VERIFIED_FROM`. The earliest month the route
serves is **unverified** — the full-span probe was never answered — so an early
`start` is a request for whatever the API has, not a claim that it has it.
`_month()` refuses anything that is not `MM-YYYY`, because `from=2023` is a 400
rather than a January.

**The offence is never in the label.** Every code comes back as "United States
Arrests" or "New York Arrests", murder and DUI alike, so `FbiArrestResponse`
carries `offense` from the request. Nothing in the payload records it.

## The request contract

**One request yields nine series, or seven, or five.** The API is parameterised
by *scope, offence and date range only*; every other distinction a tool offers
is a selection from a payload that already holds all of it. Counted off live
payloads in September 2026:

| request | series in the response |
| --- | --- |
| `summarized/agency/{ORI}/{offense}` | **9** — offences and clearances as counts and as rates (4), population for the agency *and* for its state (2), participated population for both (2), the state's coverage percentage (1) |
| `summarized/national/{offense}`, `summarized/state/{ST}/{offense}` | **7** — the same four data series, one population, one participated population, one coverage |
| `arrest/{scope}/{offense}` | **5** at agency scope — arrests as count and as rate, the two populations, coverage |
| `pe/agency/{ORI}` | male and female officers and civilians, each its own series, plus the participated population |

So the two halves of the vocabulary are not the same thing:

| | parameters |
| --- | --- |
| **the `summarized` request** | `scope` (in the path), `offense` (in the path), `from`, `to` |
| **`fbi_offenses`** | those, plus `measure` and `unit`, which **select from the response** |
| **the `arrest` request** | `scope` (in the path), `offense` (in the path — one of 48 arrest codes), `from`, `to`, `type` |
| **`fbi_arrests`** | those, plus `unit`, again a selection |
| **the `pe` request** | `ori` (in the path), `from`, `to` |
| **`fbi_employment`** | those, plus `measure` — officers or civilians, again a selection |

`measure` and `unit` never reach the FBI; `offense` does, on both routes, and on
the arrest route it is the only way to narrow a request. They belong in the
entry's `retrieval` block because that block's job is to identify *which* of a
payload's series an entry refers to, and without them the entries a scope
produces are indistinguishable to a consumer holding one of them. But a cache
in front of this client must key on the **request** — scope, offence, range —
and not on the tool's arguments. Keyed on the payload, four offence series cost
one call; keyed on measure and unit they cost four, against an allowance of a
thousand an hour.

**Nothing caches this today.** `_call_fbi` in `mcp_server/server.py` opens a
fresh `FbiClient` per tool call and the client holds nothing between calls, so
`measure="offenses"` and `measure="clearances"` for one scope and window are two
identical HTTP requests, as are `unit="count"` and `unit="rate"`. The walkthrough
notebook's sixteen offence calls are eight requests' worth of data fetched twice,
and that is against a gateway observed refusing a quarter of requests with 503s.

**For the series cache in yada.** A cache keyed per series — the
`(source, native_id, frequency)` shape `time_series_cache` uses — will re-fetch
one payload up to four times on the offence route and twice on the arrest route,
because four or two of its rows are the same fetch. Either the fetch beneath the
cache keys on the request and hands out the series it already holds, or the
cache accepts that the duplication is the API allowance being spent four times
over. The same argument reaches further than the measures: population, coverage
and participated population are properties of the *scope and window*, not of
the offence, so ten offence requests for one state fetch the same three context
series ten times.

The same holds across offences for the two carried blocks: population and
coverage are properties of the scope and the window, not of the offence. In
the exported catalog **no scope's coverage figures differ between its ten
offence files** — 0 of 57 scopes vary, re-checked 2026-09-26 — so ten offence
requests for one state fetch the same coverage series ten times.
`enforcement.ipynb` §1 measures the stronger form of this across *routes*: at
every scope, the arrest total, each of six codes and the offence route all carry
**identical** population, participated-population and coverage blocks in all 480
months. So the two routes agreeing on coverage is not corroboration — it is one
block attached twice.

## The three tools

Defined in `mcp_server/server.py`, mapped by `mcp_server/responses/fbi.py`,
returning the response models as FastMCP output schemas.

```text
fbi_offenses(offense, scope='national', measure='offenses', unit='count',
             start='01-1985', end=None)                      -> FbiOffenseSeries
fbi_arrests(scope='national', unit='count', start='01-1985', end=None,
            offense='all')                                   -> FbiArrestSeries
fbi_employment(ori, measure='officers', start=1985, end=None) -> FbiEmploymentSeries
```

- **`end=None` means now**, not a fixed date: `_fbi_this_month()` returns the
  current `MM-YYYY` (and `date.today().year` for employment), so a tool does not
  quietly stop returning its last two years. The API serves to its own vintage,
  which the response reports as `max_data_date`.
- **`offense` is last on `fbi_arrests` deliberately**, so a positional call
  written before the argument existed — `(scope, unit, start, end)` — still binds
  as it did.
- **The vocabularies are published as JSON Schema enums**, built from the
  client's own tables rather than restated: `Offense` from `OFFENSES`,
  `ArrestOffense` from `ARREST_OFFENSES` (codes, not names — the names are listed
  in the argument description), `Measure`, `Unit`, `EmploymentMeasure`. An
  unknown code is therefore refused at the tool boundary, before it can become a
  failed request against the shared key.
- **One series comes back, with its context attached.** `population`,
  `participated_population` and `coverage` ride on the response as
  `FbiContextSeries` rather than as extra series, because all three arrive in the
  same payload and returning one series without them would make a second call
  necessary to learn whether the first is usable. Each carries its own `label`,
  so a state's figure standing in for an agency's is visible.
- **`notices` is the channel for everything the numbers cannot say**: the 2021
  splice, a coverage collapse, a stood-in geography, the months nobody filed, a
  recognised filing schedule, a lump, a last month still filling, a negative
  rate, and — on every arrest response — which offence this is and that an arrest
  is not a clearance.
- **The mappers are pure and total.** No I/O, and a `None` payload maps to an
  empty record with a notice rather than raising at the tool boundary.

**The server does not hot-reload.** A server started before a tool existed serves
the old list and the call fails as "unknown tool". Worse, a server started before
an *argument* existed does not fail at all: FastMCP drops an unknown argument
silently, so `fbi_arrests(offense="11")` against such a server returns the
all-offence total — ten million arrests where nine thousand murders were asked
for. `notebooks/fbi/utils/mcp.py`'s `call_tool` therefore checks every argument
against the schema the server advertises and raises `StaleServerError` naming the
restart, before the call is made.

## The rates are not per resident

**Both routes' rates divide by the participated population** — the people living
where agencies reported — and not by `population`. Nationally in January 2023,
580,792 arrests over 323,289,818 participants is the API's 179.65; over
338,357,687 residents it would be 171.65. That held in every month of every saved
payload checked (`clients/fbi.py` docstring): national `all` arrests over
1985-2024, 480 of 480; New York State `all` for 2023; national murder arrests
1985-2024; code 20 nationally 2018-2024, 84 of 84; codes 11, 50, 70, 150, 260 and
290 nationally; and homicide offences and clearances nationally for 2023 and in
California over 2018-2024. `population` reproduces none of national or New York
`all` and only 42 of the 480 national murder months.

Two traps in that.

- **At small counts `population` still lands on the published figure**, because
  two decimals hide the gap — New York murder arrests in 10 of 12 months of 2023,
  California homicide offences in 51 of 84. A match there is not evidence.
- **Coverage is exactly `100 * participated_population / population`** in every
  month checked, so the rate is per 100,000 people living where agencies
  reported. At agency scope the two populations are the same number in every
  month the agency has one, so an agency payload cannot tell them apart.

**`participated_population` is now returned**, under the unit
`clients.fbi.PARTICIPATED` (`"participated people"`), distinct from
`population`'s `"people"` so the two — which share their labels — cannot be
picked up for each other. A rate is therefore recomputable rather than trusted.

**A negative rate comes back null.** Where the participated population is 0 — in
every month at an agency with no resident population of its own, such as the
Metro Transit Police `DCMTP0000`, which carries -1 in all 48 months of 2021-2024
beside up to 35 robbery arrests a month — the arrest route publishes a rate of
-1. Left in, it sums to -48 and averages below zero. `_defined` nulls it and
says so, and **the notice asserts the -1-over-nobody account only where the
payload bears it out**: every negative value is exactly -1 *and* the scope's own
participated population is 0 in every one of those months. Otherwise it reports
the value and the denominator it actually found, because a rate of -2.5 over 330
million participants is not a transit force, and the offence route, where no -1
has been seen at all, is not one either. Counts are never touched. A month nulled
this way is **not** a blank — the scope filed it — so it is handed to the
blank-month rule as accounted for rather than reported a second time as a return
nobody sent.

The `pe` route's own per-1,000 rates divide by a participated population that is
sometimes zero and gives impossible figures — one Texas agency reports 35
employees per 1,000 in 1985 and 274 in 2018. `FbiEmploymentResponse.officers` is
built from `actuals` and never from `rates`.

## The blank-month rule

The most consequential thing on either monthly route, and the one the coverage
series cannot catch.

**The CDE writes "nobody filed" as a number, and which number is arbitrary.**
Most routes and scopes send `0`; some send `null`; a run can mix the two.
Washington and New York report zeros for the months of 2021 they did not file,
Los Angeles and San Francisco report nulls. Nothing in the payload distinguishes
either from a month in which nothing happened, so a test on `value is not None`
counts a missing return as an observation and a sum across it invents data.
Washington's Metropolitan Police filed **no arrest at all between January 1996
and July 2021 — 307 consecutive zeros — under a District of Columbia coverage of
100.0% in every one of those months**, because an agency publishes no coverage of
its own and the percentage carried is its state's. Before the rule existed the
same series advertised 501 of 501 months filled.

### The mass test

A run of blanks is a missing return when **its length times the local level
reaches `UNFILED_RUN_FLOOR` = 25**. `LEVEL_SPAN` = 25 sets the level: the median
of the filings in a **centred** 25-period window, because the months after a run
are as much evidence of its level as the months before. Where a whole
neighbourhood is blank the window offers no level and the series' own median
filing stands in.

**There is no minimum run length.** There was one — two blanks — and it made the
floor unreachable for a run of one however large the level, so a single skipped
year passed at a department of three thousand officers where two consecutive ones
were caught. The mass floor already carries that case: a run of *k* blanks where
a period normally holds *L* has probability e^(-kL) if filings arrive
independently, so `k * L >= 25` puts the run below 10^-10 at *k* = 1 exactly as
at *k* = 2. Length alone would not do either — a department clearing three
homicides a month has ordinary zeros and ordinary quiet quarters, and San
Francisco's are kept by the floor.

**The price is stated rather than hidden:** a short genuine gap in a small series
now passes as a quiet stretch, and nothing in the payload can tell the two apart.

**Detected months come back as `null`, not flagged.** The alternative — leave the
zero and mention it in prose — is the failure the rule exists to stop: a caller
that sums without reading notices gets a plausible, wrong, silent answer. Nulling
makes the same caller drop the period or raise on it, and it is the spelling
`FbiObservation.value` already documents. `observation_start` and
`observation_end` then name the **filings** rather than the request window, and
`notices` names the spans.

### Periodic returns are recognised and handed back as sent

An agency filing quarterly or annually sends the CDE the blanks *and* a month
carrying the whole period, and the payload says nothing about the pair.
Washington filed its 1993 homicides in four quarters of 113, 113, 113 and 115
against a normal 36 a month, and its 1992-1995 arrests in four Decembers of
55,607 to 67,941; New York filed homicides quarterly for the ten years to
December 2012. Nulling those blanks and keeping the lump as one month's value
leaves a monthly mean three or twelve times too high — on Washington's arrests,
53% high over the full history — where before the rule a sum over whole periods
was right.

So `_periodic` recognises them and hands the blanks back **as the CDE sent them**
(0 in every span seen), with a notice. Three tests, in order:

| test | constant | what it is |
| --- | --- | --- |
| shape | `PERIOD_LENGTHS = (3, 6, 12)` | a maximal run of `k - 1` blanks closed by a filing, `k` quarterly, semiannual or annual. A trailing run has no closing filing and is never periodic |
| would-otherwise-be-a-gap | `UNFILED_RUN_FLOOR` | the run must already reach the mass floor, i.e. the rule above would call it a missing return. A run that rule would keep anyway needs no schedule, and claiming one would be a false claim about a quiet stretch — national gambling-numbers arrests run at three a year, so two blanks closed by a filing of 1 match the shape of a quarter and mean nothing |
| mass | `PERIOD_SHARE = 0.5`, `PERIOD_CEILING = 2.0` | the closing filing carries between half and twice the period's expected filings, measured with every candidate's closing month left out |

Where the neighbourhood holds fewer than `ORDINARY_MIN` = 6 ordinary filings the
candidates' own per-month figure stands in and the shape decides — the honest
position for a series that is periodic throughout a stretch, since there is no
monthly filing nearby to compare against. Measured spans, from saved payloads:
New York's quarterly homicide months of 2005 carry 119 against a quarter's 129;
Washington's four annual arrest Decembers 0.87 to 1.06 of a year; its 1996
semiannual pair 198 and 199 against 198; its 1997 homicides 1.17. New York's
12-1993 arrests — 667,414 after eight blank months — are 2.6 times a quarter and
cover most of a year, so the ceiling refuses them: the December is a lump and the
two blanks before it are missing returns.

**Nothing is spread across the blanks.** The CDE does not publish the split, and
inventing one would be worse than either spelling. The notice says what a month
inside a span is not, and says what the payload cannot settle: **a quarterly
filer and a scope that only ever filed in March, June, September and December
arrive identical.**

### Lumps, and a last month still filling

`_lumps` reports a filing `LUMP_SHARE` = 3.0 times what an ordinary month nearby
carries, where that level is at least `LUMP_FLOOR` = 25 and no blank run explains
it. Washington's arrests for 1989 are eleven months of 579 to 902 and a December
of 62,900 against four to seven thousand a month either side. There is nothing to
null and no schedule to name, so it is **reported and never altered**. The floor
is why: at a level of two to six, a month at three times it is an ordinary bad
month, and San Francisco's homicide series holds thirteen of those over 1985-2007
without one carrying a second month's filings. The share is deliberately above
every routine December in the national series, where annual reconciliation puts
December 2.1 to 2.4 times a normal month in every year of 1985-2026.

`PARTIAL_SHARE` = 0.1 and `PARTIAL_FLOOR` = 25 flag a **last month under a tenth
of the local level** as still filling rather than low — Washington's September
2026 reports 5 arrests against 2,288 the month before — but only where the level
is worth measuring against.

### A single arrest code's nulls are read first

Nationally the CDE has no row for a month without an arrest for one offence and
spells it `null`: gambling-numbers arrests (code `172`) come back null in **21 of
the 24 months of 2023-2024**, and 3 + 1 + 1 in the other three is exactly the 5
the FBI's 2023 `totals` give that code. Code `23` is null in all 84 months of
2018-2024 and its 2023 total is 0. Read as missing returns, those months cost the
series its span and invent a "data stops" notice two years before the data does.

At agency scope that spelling has **not been seen** — a month with no arrest for
one code comes back as 0 there, not as null: San Francisco's murder
arrests are 0 in 42 months in which the department filed other arrests, the
NYPD's in 8, and the only agency nulls in the saved payloads — San Francisco's
and Los Angeles' twelve months of 2021 — are months with no participated
population at all.

So `_one_offence` reads a null as **0 where the payload says the scope reported**:
the month is not past `max_data_date`, and the scope's *own* participated
population (its coverage where the payload has none) is above zero. Only its own
— a state's participation says nothing about one of its agencies. A value the CDE
sent is kept as it came, zero included, and goes to the mass rule as it arrived.

### The trailing run is judged four different ways

This is the reference table, carried from `_unfiled`'s docstring because a caller
comparing one agency's arrests with its offences over the same window meets two
of these answers at once.

| series | a trailing blank run at the end of the window |
| --- | --- |
| offences, clearances | **the vintage decides**: padding at or past `max_data_date`, otherwise held to the mass test like any interior run. San Francisco's forty-five zero clearance months are why |
| arrests, `all` | **nulled at any length, at every scope** — a department that files anything files arrests, so a blank run is never a quiet stretch |
| arrests, one code | **nulled at any length at agency scope**, held to the mass test nationally and by state, where a rare code's quiet tail is ordinary and real |
| employment | **nulled at any length** — the annual response has its own sentence for a year with no return |

The vintage split on the offence route has three cases and `_read_filings` keeps
them apart. Past `max_data_date`, the CDE is padding a window past the data it
holds. *Reaching* it, the returns for that month are still arriving and a blank
cannot be told from a period with nothing in it. Ending *before* it, the data
carries on past the window and the CDE padded nothing — so the run is judged by
its mass, with the level from the filings to its left. That last case is why
`vintage` exists: San Francisco's homicide clearances for 12-2007, at the end of
a window ending 12-2007 under a vintage of 09/2026, are a **filed zero** at a
department clearing three a month, and were being deleted with a notice claiming
the CDE had padded past its data. The kept-tail notice says, at agency scope,
that this cannot be told from a department that stopped filing, and to widen the
window.

The arrest route's single-code exemption rests on evidence the offence route does
not have: the mapper has already cut the months past `max_data_date` and has read
a null as a zero-arrest month only where the participated population, summed over
the agencies that reported, is above zero. **An agency's participated population
is no such evidence** — San Francisco's carries on through 2024, a year it filed
no arrest — so an agency's trailing run stays open.

### The verdict is the count's, on both units

A month is filed or not, which is a fact about the return and not about the unit
it is read in, so the rule runs on the **count** series for the same label and
measure and what it nulls is nulled in the rate as well. Judged in its own units
a rate meets a floor of 25 that means *filings*: on one saved payload New York's
homicide offence counts came back with 101 months nulled and the rates for the
same months with 5 — one request answering twice, 96 months apart. On arrests the
disagreement was one month (New York's `all`, 06-2022). Offences and clearances
are still judged separately on their own counts: a department can file its
offences and not its clearances, as New York did from 2002 to 2012.

### Two implementations, and where they differ

| | rule | applies to |
| --- | --- | --- |
| `mcp_server/responses/fbi.py` | mass + periodic + lumps + partial-last-month, on the returned series, nulling | the three MCP tools |
| `notebooks/fbi/utils/filing.py` | `unreadable`: run + part-filing + catch-up, on arrays, masking | `walkthrough.ipynb`, `enforcement.ipynb`, `withdrawal.ipynb` |
| `notebooks/fbi/utils/mcp.py` | `unfiled`: the run test alone, on `{period: value}` dicts | `mcp.ipynb` only — superseded, and kept because one test is all that notebook needs |

**The tool and `filing.py` differ in exactly one place**: `unreadable` still
takes `min_run=2`, so a lone blank at a level above 25 is null in the tool and a
readable zero in the notebook. They agree on every longer run, and
`tests/test_fbi_notebook_filing.py` pins the notebook side.

`filing.py`'s three tests each carry a floor because an absence is only evidence
where something was expected: a **run** of blanks whose length times the local
level reaches `UNFILED_RUN_FLOOR`; a **part-filing** under `PARTIAL_SHARE` of a
local median that is at least `PARTIAL_FLOOR` (New York's aggravated assault for
2021 reads 1, 2, 4, 1, 6, 3, 4, 0, 3, 4, 2, 4 against a normal month of about
2,900, and no test on zeros catches that); and a **catch-up**, the filing after a
gap exceeding `CATCH_UP` = 2.0 times the local median (Washington's December 1997
holds the whole year at 301 against a normal 22). `arrest_unreadable` is those
three with three changes an all-offence arrest series needs and a homicide series
does not: a **token** filing under `TOKEN_SHARE` = 0.01 of the series median is
read as the blank run it sits in; a part-filing line at a **third** rather than a
tenth; and a **lump** measured anywhere rather than only after a gap, against the
median of the months *around* it (`surrounding`) rather than including it —
because where a window holds little but lumps, the median *is* a lump and no lump
exceeds it. `enforcement.ipynb` §3 prints the margin: the lowest month kept sits
at half its local median and the highest taken as a part-filing at a quarter,
either side of a line at a third; the largest filing kept is 2.18 times the level
around it and the smallest lump taken 7.78, either side of a line at three.

## The traps

Seven, each with what establishes it. The first three are the original probe's
and the sixth the exported catalog's; 4, 5 and 7 came with the arrest route.

**1. An agency request returns three geographies, widest first.** Ask for NYPD
homicides and the `rates` block leads with *New York Offenses* — the state, at
a plausible magnitude, with nothing to signal the substitution. The `actuals`
block holds the agency alone; the labels are the only thing that disambiguates
`rates`. Live, `notebooks/fbi/api.ipynb` shows the payload's eight offence and
clearance series in order: NYPD offences and clearances as counts, then New
York State offences and clearances as rates, then the United States, then NYPD.
`FbiClient` filters by label and returns only the scope asked for unless
`include_comparisons=True`; `test_an_agency_request_returns_the_agency_and_not_its_state`
pins it.

> **A superseded reading.** `notebooks/fbi/utils/fetch.py` — the earlier
> urllib probe module — still records this as "`summarized/agency/{ORI}/{offense}`
> **silently returns state data** … Offences are national or state only." That
> is wrong: the agency's own numbers are in the payload, in `actuals`, as the
> notebook output above shows. The label ordering is what misled it.
> `clients/fbi.py` is the corrected account.

**2. `pe/national` and `pe/state/{ST}` answer 200 with the full response shape
and nothing in it.** Probed: the payload carries all five blocks (`rates`,
`actuals`, `tooltips`, `populations`, `cde_properties`) and **two** non-null
values in the whole document. `data/raw/probe.json` records it as
`"pe/national": "ok, 0 years with values"`. Employment exists only per agency;
a national figure has to be aggregated from agencies or taken from Census
ASPEP. This is why `withdrawal.ipynb` §4 has no national line for arrests per
officer.

**3. The `pe` `rates` block divides by an unreliable participated population.**
See [The rates are not per resident](#the-rates-are-not-per-resident).

**4. The arrest blocks are not nested.** `summarized` puts the numbers under
`payload["offenses"]["actuals"]`; `arrest` puts `actuals` and `rates` at the top
level with no wrapper. Code that copies the `summarized` reader finds nothing and
returns an empty series rather than failing.

**5. The requested scope has no fixed place in the arrest `rates` block.**
`summarized` leads with the widest comparison. `arrest/agency/NY0303000/11`
returns `rates` keyed `New York`, `United States`, `New York City Police
Department` — the agency **last** — while `arrest/state/NY/11` returns `New York`
then `United States`, the state **first**. So position cannot be used, and
`get_arrests` keeps the labels that appear in `actuals`, which carries the
requested scope alone at every grain. Population and coverage are filtered
against the nation only, so an agency's state coverage survives to stand in for
a figure the agency does not publish.

**6. An agency entry's coverage figures are its state's.** Verified in the
exported catalog, re-checked 2026-09-26: for all five city ORIs, across all ten
offences and both measures, `coverage_mean_percent` and `coverage_min_percent`
are identical to the state's, digit for digit — **100 of 100 pairs, none
differing**. Los Angeles PD reads 97.91 / 20.56, exactly California; Chicago PD
73.02 / 27.18, exactly Illinois. Washington PD's 100.0 / 100.0 looks like an
agency figure and is DC's. The mechanism is that `entries_from` takes the first
coverage series that is not the nation's, and the agency payload's non-national
coverage is the state's. Nothing in an entry says so. The tools do say so:
`_qualify` compares the context's `label` against the series' geography and adds
a notice where they differ. The catalog has no such field.

**7. Nationally, for one arrest code, a month with no arrest is null rather than
0 — and at agency scope it is 0.** See
[the blank-month rule](#a-single-arrest-codes-nulls-are-read-first). The client
passes values through as it gets them; the MCP mapper is what reads them.

And one artefact rather than a trap: **`observation_end` is the requested
window, not the end of the data.** All 1,140 offence entries end 2024-12-01 and
all 10 employment entries 2024-01-01 because `get_offenses` defaults to
`end="12-2024"` and `get_employment` to `end=2024`, while the same payloads
report a UCR vintage of `09/2026`. The spans are honest about what was asked
for and silent about what was available. The **tools** do not share that default
— they end at the current month — so a tool response and a catalog entry for the
same series disagree about `observation_end` by design.

## Demographics, and the route that does not exist

Arrestee sex, race and age are served, but only by `type=totals`, which carries
**no time dimension at all**: one figure per block for the whole window asked
for. One national 2023 call returns the complete 49-code offence breakdown
summing exactly to the 7,184,021 all-offence total, the same mix grouped two
coarser ways, and then `Arrestee Sex`, `Arrestee Race`, `Male Arrests By Age` and
`Female Arrests By Age`. So the whole arrest mix *and* its demographics cost one
request per scope per window — 40 requests for a national annual series of
everything, not 40 per code. The demographic blocks do not cover every arrest:
sex sums to 7,076,786 against the 7,184,021 total, so 1.5% carry no record.
`FbiClient` sends `type=counts` and never reads this.

**There is no monthly demographic series.** The spec defines a schema
`arrest_offense_category` with the enum `["male", "female", "race", "sex"]`, and
**no path references it**; the api.data.gov gateway's own 2022 documentation
shows `arrest/{scope}/{offense}/{category}` sub-paths. They do not exist. Probed
on 26 September 2026 with a control in the same run:

| request | answer |
| --- | --- |
| `arrest/national/11` (control) | **200**, monthly `actuals` and `rates` |
| `arrest/national/11/sex` | **404**, and the body is HTML |
| `arrest/national/11/male` | **404** |
| `arrest/national/11/race` | **404** |
| `arrest/national/11/female` | **404** |

A 404 rather than a 400 is the gateway saying the route is not mapped, and the
control rules out a key, window or outage explanation. Demographics over time
therefore come from one request per period, or from the NIBRS incident files,
which carry age, sex, race and ethnicity per victim, offender and arrestee.
Do not spend requests probing these sub-paths again.

## Coverage, and the two-part 2021 break

Both offence and employment payloads carry a **Percent of Population Coverage**
series: the share of the population living where agencies reported, monthly,
alongside the data. It is what makes a value interpretable, so the client keeps
it and the catalog summarises it into `coverage_mean_percent` and
`coverage_min_percent`. The tools return the series itself plus
`coverage_mean_percent`, `coverage_min_percent` and `coverage_min_period`, and
add a notice below `COVERAGE_FLOOR` = 90%.

Nationally, from `notebooks/fbi/api.ipynb` (violent crime, annual means of the
monthly series):

| 2015 | 2016 | 2017 | 2018 | 2019 | 2020 | **2021** | 2022 | 2023 | 2024 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 97.6 | 97.7 | 96.5 | 97.5 | 96.2 | 95.9 | **77.0** | 94.8 | 95.9 | 96.4 |

Over the full 1985–2024 window the national mean is **93.68%** and the lowest
single month **74.12%** (February 2021) — the figures every national entry in the
catalog carries, and, as `enforcement.ipynb` §1 measures, the same two figures the
national *arrest* total reports, because it is the same block attached twice.

**The 2021 break is two breaks, and only one of them is measured.**

1. **Reporting.** The FBI retired the Summary Reporting System (SRS) on
   1 January 2021 in favour of the National Incident-Based Reporting System
   (NIBRS), and agencies that had not converted stopped reporting. That is the
   dip above, and the coverage series measures it exactly.
2. **Counting.** SRS applied the **hierarchy rule** — an incident contributed
   only its most serious offence. NIBRS records every offence in the incident.
   A robbery involving an assault is one offence before 2021 and two after.
   Coverage recovering to 96% does not undo that, no series in the API carries a
   flag for it, and nothing in the catalog can. **Treat any series spanning 2021
   as spliced, not continuous.** `_NIBRS_NOTICE` says so on every response whose
   filings straddle the year.

Homicide is the one offence the counting change cannot have touched, because
nothing outranks a homicide in the hierarchy. That is why `walkthrough.ipynb`
reads homicide throughout and why its cross-city comparisons survive a year in
which its eight scopes were filing to three different regimes at once.

**The reporting break has been checked from outside the police.**
`withdrawal.ipynb` §6 sets national recorded homicide against certified assault
deaths (ICD-10 X85–Y09 plus Y87.1, from the WONDER pull already on disk under
`notebooks/cdc/`, D76 for 1999–2020 spliced to D158 for 2018–2024). The ratio
runs between **0.850 and 0.919 in every year from 1999 to 2024 except 2021**,
where it is **0.689** — 17,933 recorded homicides against 26,031 death
certificates. Dividing by the year's own coverage of 77.0% gives
17,933 ÷ 0.770 ÷ 26,031 = **0.895**, inside the band of every other year. So the
coverage field is not merely self-reported bookkeeping: it reconstructs the
missing count against an object no police decision touches. Two caveats the
notebook states rather than buries. The level of the ratio carries no
information — the FBI's murder count excludes justifiable homicide and negligent
manslaughter while a certificate codes a justifiable civilian killing as assault,
and the two count by different clocks — and the **coverage-adjusted ratio drifts
from 0.951 in 1999 to 0.888 in 2024**, about six points over twenty-five years,
which four different mechanisms would produce and this pair cannot separate.

State coverage is far worse than the national figure and the minimum is not a
2021 marker on its own. Of the 51 state scopes, **46 dip below 95% in some
month and 18 below 50%** — Kentucky to 0.31%, Iowa 0.45%, Montana 0.75%. By
mean, Mississippi is lowest at 60.82% and Illinois next at 73.02%; only five
states never fall below 95% in any month (DC, OK, RI, SC, TX), against 51.
`coverage_min_percent` is a screening field: use it to decide whether a series
can be modelled at all, and `nibrs_start_date` to date the break for a
particular agency.

**Coverage cannot show one agency going dark**, which is the single most
important thing about it. An agency publishes none of its own, so the percentage
carried is its state's — Washington's 307 blank arrest months under a DC coverage
of 100.0%. That is what the blank-month rule is for, and why the kept-tail notice
refuses to claim more than the payload supports.

## The NIBRS incident files: the second channel

`notebooks/fbi/utils/nibrs.py`, added 2026-09-26 (`25281d6`). Not the API: a
download, no key, and nothing on `api.usa.gov`.

**Why it exists.** `summarized` reports one combined clearance count and never
the split between arrest and *exceptional* means (offender dead, in custody
elsewhere and not extraditable, prosecution declined, victim will not cooperate).
SRS did not record it at all. NIBRS does, as **Data Element 4**, and the FBI
publishes the incident files that carry it.

**Where the files are.** One zip per state and year. The CDE downloads page
builds the key `nibrs/incident/{year}/{ST}-{year}.zip` and asks
`https://cde.ucr.cjis.gov/LATEST/s3/signedurl?key=<key>` for a link; the answer
is `{key: url}`, a 15-minute signed URL to the S3 bucket `cde-prd-data`
(us-gov-east-1). `fetch()` caches each zip under `notebooks/fbi/data/nibrs/`,
streams to `<name>.part` and renames only after the length matches and the file
opens as a zip, so an interrupted download never looks cached. Six zips are
cached as of 2026-09-21 — New York and Tennessee, 2023-2025 — at about 307 MB.

**Layout and rules.** Each zip holds 44 CSVs plus a README, a diagram and
Postgres load scripts; the 2023 zips nest them one level deeper than 2024 and
2025, so members are found by basename and columns by header name. Five tables
are read: `agencies.csv`, `NIBRS_incident.csv`, `NIBRS_OFFENSE.csv`,
`NIBRS_ARRESTEE.csv` and `NIBRS_CLEARED_EXCEPT.csv` — whose 1–5 → A–E and 6 → N
mapping is re-checked on every read and raises if it has changed. The rules, each
against the NIBRS User Manual (2027.0 red-line): the unit is the **incident**,
not the offence, so an incident carrying several of the eight offences counts once
under each and the offence rows do not add to the incident count; the reason is
`arrest` if the incident has any arrestee record, because the first arrestee
segment clears it and an incident cleared by arrest cannot also be cleared
exceptionally; the month is the **incident** month, never the arrest's; rape is
11A + 11B + 11C, since 11B and 11C are reclassified to 11A for reporting.

**Eight traps, measured on the six cached files.** The two that matter most:

- **NYPD almost never records an exceptional clearance.** It sets an A–E code on
  9, 22 and 12 incidents in 2023, 2024 and 2025 — **28 offence-incident rows of
  762,171** across the three years (6, 15 and 7), against 259,363 cleared by
  arrest. Nashville sets one on **4,010 rows of 108,943 (3.7%)**, which the
  module records as 9.0–9.5% of *incidents* (the denominators differ: an incident
  need carry none of the eight offences). So an NYPD plot shows arrest against
  not-cleared and the A–E bands are invisible. **That is how NYPD reports, not
  missing data.** Nashville's are not spread evenly either: code D, "victim
  refused to cooperate", is 1,140 of its 1,358 exceptional rows in 2023, and code
  C is used zero times by either department in any of the three years.
- **Late months are understated.** Each file carries arrests only to a cutoff
  early in the following year, months before the file was built: NYPD's latest
  arrest dates are 2024-02-29, 2025-02-28 and 2026-02-28 while the files were
  built 2024-09-20, 2025-07-02 and 2026-05-01. What sets the cutoff is
  **unverified** — the files do not say. A December incident had about two months
  to clear and a January incident about fourteen. `enforcement.ipynb` §2 sizes it:
  cleared-by-arrest falls from 35.8% for January incidents to 31.7% for December
  ones in New York, 10.5% to 8.0% in Nashville.

The rest, in brief: New York's rape counts are unreliable from 2024-09 to
2025-07 (NYPD's 11B falls to zero and its 11A swells to 370–489 a month against
75–167 before), though the shares by reason hold through it; NIBRS 09A runs 2–11%
below NYPD's own published murder counts, and wider still against the series
`fbi_offenses` returns (345 against 404 in 2023, 325 against 361 in 2024);
`NIBRS_month.csv` has one row per submitted document rather than one per
agency-month and carries **no zero reports**, so it cannot tell a month nobody
filed from a quiet one and is not read; TN-2023 carries two build dates;
Nebraska's ORIs begin `NB` while its file is `NE-{year}.zip`, the only state
where the prefix is not the postal code; and every incident in the six files is
dated in the file's year, with a row that is not raising rather than landing
silently in the wrong year.

`clearance_by_reason(ori, years)` returns every (year, month, offence, reason)
cell including zeros, so a missing row never stands in for one, and raises
`UnknownAgency` or `NoIncidents` rather than returning a year of zeros.
`pooled(cells)` gives incidents and shares by reason per offence.

**What this makes visible and no tool does.** A department reporting 40% cleared
may be reporting 40% arrested, or 28% arrested and 12% closed because a victim
withdrew, and `fbi_offenses` returns the same number in both cases. For these two
departments over these three years the split is **34.0 / 0.0 against 10.1 / 3.7**
(arrest / exceptional, all eight offences pooled).

## The catalog

There is no metadata endpoint and none is needed: each `summarized` call
returns the observations *and* everything an entry wants — the span, the
denominator, the coverage, the vintage — so the catalog is a by-product of
reading the data rather than a second pull.

**One file per group**, the convention every other source follows (BLS by
survey, BIS by dataflow, Clio by category). Here the group is the **offence
slug**, because that is the API's own request dimension, so re-harvesting one
offence rewrites one file and the diffs stay readable. Police employment is a
separate family — annual, agency-scoped, different facets — and gets its own
file.

Counted from the files as they stood on disk on 2026-09-26 (written 2026-09-20;
unchanged since, and the arrest route has not been catalogued):

| File | Entries |
| --- | --- |
| `fbi_series_{violent_crime, homicide, rape, robbery, aggravated_assault}.yaml` | 114 each |
| `fbi_series_{property_crime, burglary, larceny, motor_vehicle_theft, arson}.yaml` | 114 each |
| `fbi_series_employment.yaml` | 10 |
| **total** | **1,150 across 11 files** (≈934 KiB) |

114 is **57 scopes × 2 measures**: the nation, 51 states, and five city
departments — Washington `DCMPD0000`, New York City `NY0303000`, Chicago
`ILCPD0000`, Los Angeles `CA0194200`, Philadelphia `PAPEP0000`. That splits
1,040 national-and-state entries, 100 city entries and 10 employment entries;
110 entries are agency-scoped and carry `nibrs_start_date`. Every entry is
`unit: count`; the rate series are fetched, not catalogued, since a rate is
recomputable from the count and the population. 1,140 are Monthly and 10 Annual,
all starting 1985-01-01, all carrying vintage `09/2026` and refresh `09/15/2026`.

**The five cities are not the notebooks' eight scopes**, and neither list is the
other's superset. The catalog has Chicago and Philadelphia, which no notebook
reads; `walkthrough.ipynb` and `withdrawal.ipynb` read San Francisco
`CA0380100`, Oakland `CA0010900`, San Jose `CA0431300` and Nashville
`TN0190100`, none of which is catalogued. A re-harvest should reconcile them.

### Where each field comes from

| Source | Fields |
| --- | --- |
| **the payload** | `observation_start`/`_end`, `coverage_mean_percent`, `coverage_min_percent`, `sources[].vintage` and `.refreshed`, and `facets.geography` — an ORI resolves to the department's own name |
| **the request** | `series_id`, `concept`, `title`, `unit`, `frequency`, `facets.scope`/`offense`/`measure`, `retrieval` |
| **the agency registry** | `facets.agency_type`, `facets.state`, `facets.county`, and `nibrs_start_date` — present on the 110 agency-scoped entries only |
| **written by hand** | `definition`, from `OFFENSE_NOTES` and `MEASURE_NOTES`. The API has no dictionary, and what a clearance means (arrest *or exceptional means*), which rape definition applies, what `property-crime` excludes, are the caveats people miss |
| **generated later** | `description`, by `db_import.descriptions` — **21 buckets** here (counted from the files 2026-09-26), against CDC's two and a half thousand series. Not yet generated: there is no `descriptions.yaml` under `notebooks/fbi/data/` |

`series_id` is `fbi/{offense}/{scope}/{measure}` for crime and
`fbi/employment/{ori}/{measure}` for staffing. The 21 description buckets are
`(group, concept, facet-shape, unit)`: two per offence, because agency entries
carry three facets the national and state ones do not, plus one for employment.
`utils/catalog.py`'s own docstring still says twenty; the files say 21.

### The cost of a rebuild

One request per (scope, offence). 52 scopes × 10 offences = **520 calls** for
the national and state catalog, plus 10 per city and one per city for
employment — **575 calls** for the catalog as it stands. `PAUSE` is **3.6**
seconds, the sustainable rate: 520 calls is about 31 minutes and 575 about 35.
One a second was tried and does not hold — a second run inside the same hour met
503 "Client Failure Limit Exceeded" on **58 of 520 calls and silently lost 116
catalogue entries**. Failures are collected rather than raised and written to
`data/harvest_failures.json`, and `repair()` re-fetches just those pairs and
merges them by `series_id`, so a partial run costs 58 calls to fix rather than
520 to repeat.

`scopes()` fetches the state list from `lookup/states` rather than from the
`STATES` constant, so a territory appearing upstream is picked up; the constant
is the fallback and matched the API exactly when checked. `harvest()`'s default
scope list is `("national", *STATES)`, so **agency scopes must be passed
explicitly** — the five cities are not in the default.

Enumerating all 19,636 agencies is cheap — 51 calls — but **pulling them is
not**: 19,636 employment calls alone is about twenty hours at the allowance,
before a single offence. Choose the cities you intend to model.

## The notebooks

Seven, under `notebooks/fbi/`. The first four are the plumbing; the last three
ask questions of the data. Call counts are each notebook's own.

| Notebook | What | Calls |
| --- | --- | --- |
| `api.ipynb` | what one call returns, the coverage series by year, the traps demonstrated live, the agency registry | a handful |
| `catalog.ipynb` | the request vocabulary, the five cities, the harvest, the export, coverage as a catalog field | the harvest |
| `client.ipynb` | `FbiClient` on one department: ORI discovery, one request's four series, the clearance rate, officers, crime against capacity — and the filing schedule under Washington's 1993-1997 clearances, which is where the rule started | 3 |
| `mcp.ipynb` | the tools as a model sees them, over `{period: value}` dicts, with `utils/mcp.py`'s first-version rule | a handful |
| `walkthrough.ipynb` | **eight scopes**: homicide per 100,000, clearance rates, arrests, officers per 100,000, and §5's test of whether each city breaks at its own conversion date | 39 |
| `enforcement.ipynb` | six arrest codes at six scopes, clearance reasons from the NIBRS files, and §3 on the filing schedule underneath the arrest series | 49 |
| `withdrawal.ipynb` | recorded crime as a report count: four instruments, the statutory trap, and the external check against death certificates | 96 |

**`walkthrough.ipynb` is now eight scopes** (`34adf90`), seven city departments
and the nation: New York `NY0303000`, Washington `DCMPD0000`, Los Angeles
`CA0194200`, San Francisco `CA0380100`, **Oakland `CA0010900`**, **San Jose
`CA0431300`** and Nashville `TN0190100`. They are not a sample of anything —
they were chosen because their conversion dates span twenty-five years, which is
the only reason §5 can be attempted (Nashville 1999-10, Washington 2021-08, New
York 2023-01, San Jose 2023-04, Los Angeles 2024-05; San Francisco and Oakland
have never converted). **Two never-converted departments rather than one is what
the eighth scope bought**: a single control cannot distinguish "no conversion, no
step" from "this department has a quiet series". The two added also break the
crime-against-staffing pairing in both directions at once — Oakland polices at
157 officers per 100,000 and San Jose at 110, the two thinnest forces of the
seven, while their 2024 homicide rates are 18.6 and 2.7, the second highest and
the lowest here.

`enforcement.ipynb` uses six of those eight; `withdrawal.ipynb` uses all eight.
All three import their filing rule from `utils/filing.py` rather than restating
it, so a threshold moved there moves in all three.

## Tests

**264 FBI tests, all passing, none touching the network** — run 2026-09-26,
inside a suite of 866 that also passes whole.

| File | Tests | What it covers |
| --- | --- | --- |
| `tests/test_fbi_arrests.py` | 132 | the arrest route and its mapper: code normalisation and refusal, the partition, the single-offence null reading, the trailing-run split by scope, judged-on-counts, the negative-rate notice |
| `tests/test_fbi_nibrs.py` | 53 | `utils/nibrs.py`: the clearance-reason rules, the incident unit, the zip layouts, the checked A–E mapping, `UnknownAgency`/`NoIncidents` |
| `tests/test_fbi_notebook_filing.py` | 27 | `utils/filing.py`: the three tests and their floors, `arrest_unreadable`'s three changes, `trailing_sum` |
| `tests/test_fbi_client.py` | 25 | `FbiClient` over `httpx.MockTransport` with hand-built payloads |
| `tests/test_fbi_filings.py` | 14 | the blank-month rule itself: mass, periodic returns, lumps, the kept tail |
| `tests/test_fbi_models.py` | 13 | the pivot, the nulls that must survive it, `officers` |

What they assert is not parsing but **filtering and reading** —
`test_a_state_request_drops_the_national_comparison`,
`test_an_agency_request_returns_the_agency_and_not_its_state`,
`test_a_national_request_keeps_its_own_united_states_series`,
`test_an_mcp_caller_can_learn_that_an_agencys_trailing_run_is_nulled` — plus the
refusals that happen before a request is spent (an unknown offence, an unknown
arrest code, a bare year, two geographies at once, employment before 1985). Every
row of the trailing-run table above is pinned by a test. The client factory is
local to the module rather than in `conftest.py` so nothing there can read a real
key or reach the network.

## Files

Under `notebooks/fbi/` unless stated. **Everything under `data/` is gitignored
and regenerable** — but not equally cheap: `data/raw/agencies.json` is 51 calls
(5.5 MB), the eleven catalog files 575 calls, and `data/nibrs/` six downloads and
~307 MB.

| Path | What |
| --- | --- |
| `clients/fbi.py` | `FbiClient`: `get_offenses`, `get_arrests`, `get_employment`, `get_agencies`, `get_states`, the static `route()`, `arrest_offense()`, the label filters, the 429/503 retry. `OFFENSES`, `ARREST_OFFENSES` (48), `ARREST_CODES_FOR`, `PARTICIPATED`, `ARREST_TYPE`, `ARREST_VERIFIED_FROM`, `EMPLOYMENT_FROM`. The module docstring is the record of what was probed |
| `clients/models/fbi.py` | `FbiSeries` / `FbiObservation` / `FbiOffenseResponse` / `FbiArrestResponse` / `FbiEmploymentResponse` / `FbiAgency`. Pivots the CDE's chart-shaped `{block: {label: {period: value}}}` into flat series; `officers` sums male and female from the counts and drops a year only one half reported |
| `mcp_server/responses/fbi.py` | the three response models and the three mappers, and the blank-month rule: `_levels`, `_runs`, `_periodic`, `_lumps`, `_unfiled`, `_read_filings`, `_one_offence`, `_defined`, `_qualify`, and the notice builders. 2,049 lines, and the largest single piece of the integration |
| `mcp_server/server.py` | `fbi_offenses`, `fbi_arrests`, `fbi_employment` and `_call_fbi` (a fresh client per call, no cache) |
| `environment.py` | `get_data_gov_key()` (`DATA_GOV_KEY`) and `get_fbi_base_url()` |
| `utils/catalog.py` | `scopes()`, `harvest()`, `harvest_employment()`, `entries_from()`, `employment_entries()`, `repair()`, `export()`; `OFFENSE_NOTES`, `MEASURE_NOTES`, `PAUSE`, the `STATES` fallback |
| `utils/filing.py` | the filing rule all three analysis notebooks share: `monthly`, `context`, `local_median`, `surrounding`, `unreadable`, `arrest_unreadable`, `trailing_sum`, `stamp_source` |
| `utils/nibrs.py` | the NIBRS incident files: `fetch`, `agency`, `clearance_by_reason`, `pooled`; `OFFENSES`, `REASONS`, `EXCEPTIONAL`; the eight traps in the docstring |
| `utils/mcp.py` | the tools over MCP: `call_tool` (which refuses an argument the server does not advertise), `StaleServerError`, `list_tools`, and the superseded `unfiled` / `rolling_12` / `clearance_rate` that only `mcp.ipynb` uses |
| `utils/fetch.py` | the earlier stdlib-urllib probe module: `summarized`, `agencies`, `police_employment`, `officers`, `probe`. Superseded by the client; see trap 1 |
| `data/fbi_series_<group>.yaml` | 11 files, 1,150 entries — ten offences plus employment |
| `data/raw/agencies.json` | the registry, 19,636 agencies with ORI, type, county and `nibrs_start_date` |
| `data/raw/probe.json` | which offence slugs and scopes the API actually serves |
| `data/harvest_failures.json` | what the last harvest lost, for `repair()` |
| `data/nibrs/{ST}-{year}.zip` | the cached incident files — NY and TN, 2023-2025 |
| `tests/test_fbi_*.py` | 264 tests across six files, no network |

## Known gaps

- **The catalog holds no arrest series.** Its 1,150 entries are state-grain
  offences and employment, written before the arrest route existed, so
  `fbi_arrests` is served but not discoverable. 47 codes × 57 scopes is 2,679
  entries at one request each — about two and three-quarter hours at `PAUSE`, and
  five times the existing catalogue in files. The honest first step is a code
  subset, since an entry has no way today to say that a code is empty at a scope,
  and at agency scope most of them are.
- **Not loaded.** `db_import.load_catalog.load(DATA_DIR, "fbi")` would work —
  the loader is source-generic and reads `fbi_series_*.yaml` — but
  `series_catalog` has no `fbi` rows today.
- **No descriptions.** The 21 buckets exist; `descriptions.yaml` does not.
- **The catalog's five cities and the notebooks' eight scopes do not
  intersect fully** — see [The catalog](#the-catalog).
- **Three documented routes are unprobed**, and one of them is the only live
  route carrying a clearance *type*:
  - `nibrs-estimation` — the spec documents it and it is the one API route that
    would give clearance by reason without downloading the incident files.
    **Unprobed.**
  - `participation` — would say whether a given agency filed in a given period,
    which is exactly the evidence the blank-month rule has to infer. **Unprobed**,
    and the single highest-value gap on this page: it would settle at agency scope
    what coverage cannot.
  - `shr` — the Supplementary Homicide Report, i.e. expanded homicide with
    victim/offender relationship and circumstance. **Unprobed.**
- **LEOKA is not in this API at all.** Officers killed and assaulted is a separate
  UCR collection with no CDE route found. Neither is anything before 1985.
  Both belong to [fbi-historical.md](fbi-historical.md), the companion page.
- **Agency coverage is the state's** (trap 6), unlabelled as such in the catalog.
  The tools do say so; the catalog has no field for it.
- **`FbiSeries.measure` is `"value"` for population and coverage.** The field's
  own description lists `'population'` and `'coverage'` among its values, but
  `_measure()` matches only offences, clearances, arrests, officers and civilians
  and falls through to `"value"` for the other two. Live output confirms it:
  `District of Columbia   value   people` and `… value   percent`. Select those
  two series on `unit` — `"people"`, `"participated people"` and `"percent"` —
  which is what `catalog.py`, the mappers and the tests all do.
- **Catalog spans stop at 2024** by request default while the vintage is 09/2026,
  and the tools end at the current month, so the two disagree by design.
- **Rates are fetched and not catalogued**, by choice: recomputable from the
  count and the participated population, which the payload carries.
- **No caching anywhere.** A fresh `FbiClient` per tool call, and a payload
  re-fetched once per selection — see
  [The request contract](#the-request-contract).
- **`mcp.ipynb` documents two tools.** Its "Two tools, and why only two" section
  and its tool listing predate `fbi_arrests`, and it still uses `utils/mcp.py`'s
  superseded one-test rule. It is the one notebook not brought level with the
  arrest route. `enforcement.ipynb`'s opening likewise still calls the
  walkthrough "five cities".
- **The tool and `utils/filing.py` disagree on a lone blank month** — see
  [Two implementations](#two-implementations-and-where-they-differ). Deliberate
  and tested, not a defect, but a caller comparing a notebook figure with a tool
  response will meet it.
- **`utils/catalog.py`'s docstring says twenty description buckets**; the files
  say 21.
- **The arrest partition is checked in one window only** — national 2023.
  Whether the codes sum to `all` in other years or at other scopes is
  **unverified**, as is whether earlier years' `all` includes runaway arrests.
- **The earliest month the arrest route serves is unverified.** `01-2018` is as
  far back as a probe was answered, not a floor the API states.
- **What sets the NIBRS files' arrest cutoff is unverified.** It is not the build
  date, and the files do not say.
