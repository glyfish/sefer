# FBI Reference — the Crime Data Explorer API and the catalog

Reference for the FBI **Crime Data Explorer (CDE)** integration: monthly
offences and clearances at three geographic grains, annual police employment at
one, and the metadata catalog built out of those same calls. Built and in use —
`FbiClient` and its models in `clients/`, the export in
`notebooks/fbi/utils/catalog.py`, two notebooks, and 38 tests.

**Not yet built, and worth knowing before reading further:** there are no FBI
MCP tools. `mcp_server/server.py` defines 29 tools and none of them is
`fbi_offenses` or `fbi_employment`, which is what every catalog entry's
`retrieval` block names. Nor is the catalog loaded: `series_catalog` holds
13,967 rows under `clio`, `cdc`, `clio_historical` and `voteview`, and none
under `fbi`. The catalog files describe series that nothing in the server can
fetch yet.

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

## Access

- **Base URL:** `https://api.usa.gov/crime/fbi/cde` (`get_fbi_base_url()`;
  override with `FBI_BASE_URL`).
- **The older `crime/fbi/sapi` service is dead.** It returns 404, and the
  published Swagger still documents it, as do most tutorials. Anything written
  against `/api/estimates/...` is gone. Everything on this page was established
  by probing the live service.
- **The key is the shared api.data.gov key** (`DATA_GOV_KEY`,
  `get_data_gov_key()`) — one key for every service behind that gateway, not an
  FBI key. Self-service and instant from <https://api.data.gov/signup/>.
- **It goes in the query string as `API_KEY`, capitalised.** The CDE routes
  ignore the lowercase `api_key` other api.data.gov services accept.
- **1,000 requests an hour** with a real key. The shared `DEMO_KEY` allows about
  thirty and then returns `OVER_RATE_LIMIT` — enough to probe an endpoint, not
  enough to build a series. `FbiClient` translates HTTP 429 into an
  `FbiAPIError` that says the allowance was reached.
- **A 503 is not a rate limit.** The gateway answers
  `upstream connect error or disconnect/reset before headers` when the CDE
  backend behind it is down; three consecutive calls failed that way while this
  page was written, on two different date ranges. It is indistinguishable from
  a transient outage and unrelated to the hourly allowance.
- **The 404 page is HTML.** `FbiClient._get` refuses a body that does not start
  with `{` or `[` rather than handing a parse error to the caller.

## The endpoint surface

| Route | Grain | Cadence | Serves |
| --- | --- | --- | --- |
| `summarized/national/{offense}` | the nation | monthly, 1985– | offences and clearances, counts and rates, population, coverage |
| `summarized/state/{ST}/{offense}` | 51 states incl. DC | monthly, 1985– | the same, plus the national comparison |
| `summarized/agency/{ORI}/{offense}` | one agency | monthly, 1985– | the same, plus the state **and** national comparisons |
| `pe/agency/{ORI}` | one agency **only** | annual, 1985– | officers and civilians, each split male/female, plus population |
| `agency/byStateAbbr/{ST}` | one state's agencies | — | 19,636 agencies nationally: ORI, name, type, county, NIBRS status and start date |
| `lookup/states` | — | — | the 50 states and DC, no territories |

`FbiClient.route(scope)` turns one string into the right fragment —
`national`, a two-letter code, or anything longer read as an ORI — so a catalog
entry's `scope` facet maps to a call with nothing to translate.

**Ten offence slugs**, hard-coded in `clients.fbi.OFFENSES` because
`lookup/offenses` answers `{"crimeGroups": null}` for every type tried:
`violent-crime`, `homicide`, `rape`, `robbery`, `aggravated-assault`,
`property-crime`, `burglary`, `larceny`, `motor-vehicle-theft`, `arson`. They
overlap: `violent-crime` totals homicide, rape, robbery and aggravated assault,
`property-crime` totals burglary, larceny and motor vehicle theft, and **arson
is excluded from that total** and reported alone. Summing all ten
double-counts everything but arson. `lookup/states` is the one lookup that
answers; `regions` and `agency-types` return "Invalid Lookup".

The agency registry is the only route that enumerates anything, and the only
way to discover an ORI. Of its 19,636 agencies, 11,784 are city departments,
3,029 county, 1,382 other state agencies, 1,296 other, 971 state police, 956
university or college and 218 tribal. **16,420 are flagged `is_nibrs`, and
every one of those carries its own `nibrs_start_date`** — the transition dated
locally rather than inferred from the national dip. 2,684 of them start in
2021 and 5,652 in 2021 or later.

## The request contract

**One request yields four series.** The API is parameterised by *scope, offence
and date range only*; offences and clearances, as counts and as rates, all
arrive together, alongside the population denominator and the coverage
percentage. So the two halves of the vocabulary are not the same thing:

| | parameters |
| --- | --- |
| **the API request** | `scope` (in the path), `offense` (in the path), `from`, `to` |
| **`fbi_offenses`** | those, plus `measure` and `unit`, which **select from the response** |
| **the `pe` request** | `ori` (in the path), `from`, `to` |
| **`fbi_employment`** | those, plus `measure` — officers or civilians, again a selection |

`measure` and `unit` never reach the FBI. They belong in the entry's
`retrieval` block because that block's job is to identify *which* of a
payload's series an entry refers to, and without them the four entries a scope
produces are indistinguishable to a consumer holding one of them. But a cache
in front of this client must key on the **request** — scope, offence, range —
and not on the tool's arguments. Keyed on the payload, four series cost one
call; keyed on measure and unit they cost four, against an allowance of a
thousand an hour.

The same holds across offences for the two carried blocks: population and
coverage are properties of the scope and the window, not of the offence. In
the exported catalog **no scope's coverage figures differ between its ten
offence files** — 0 of 57 scopes vary — so ten offence requests for one state
fetch the same coverage series ten times.

## The traps

Four, each with what establishes it.

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
ASPEP.

**3. The `pe` `rates` block divides by an unreliable participated population.**
One Texas agency reports 35 employees per 1,000 in 1985 and 274 in 2018, and
the base is sometimes zero. `FbiEmploymentResponse.officers` is built from
`actuals` and never from `rates`; bring your own denominator.

**4. An agency entry's coverage figures are its state's.** Verified in the
exported catalog: for all five city ORIs, across all ten offences and both
measures, `coverage_mean_percent` and `coverage_min_percent` are identical to
the state's, digit for digit — **100 of 100 pairs, none differing**. Los
Angeles PD reads 97.91 / 20.56, exactly California; Chicago PD 73.02 / 27.18,
exactly Illinois. Washington PD's 100.0 / 100.0 looks like an agency figure and
is DC's. The mechanism is that `entries_from` takes the first coverage series
that is not the nation's, and the agency payload's non-national coverage is the
state's. Nothing in an entry says so. The test fixture assumes a lone
agency-labelled tooltip, so it is not evidence either way; one live agency call
would settle which label the payload actually carries, and the API was 503-ing
while this was written.

And one artefact rather than a trap: **`observation_end` is the requested
window, not the end of the data.** All 1,140 offence entries end 2024-12-01 and
all 10 employment entries 2024-01-01 because `get_offenses` defaults to
`end="12-2024"` and `get_employment` to `end=2024`, while the same payloads
report a UCR vintage of `09/2026`. The spans are honest about what was asked
for and silent about what was available.

## Coverage, and the two-part 2021 break

Both offence and employment payloads carry a **Percent of Population Coverage**
series: the share of the population living where agencies reported, monthly,
alongside the data. It is what makes a value interpretable, so the client keeps
it and the catalog summarises it into `coverage_mean_percent` and
`coverage_min_percent`.

Nationally, from `notebooks/fbi/api.ipynb` (violent crime, annual means of the
monthly series):

| 2015 | 2016 | 2017 | 2018 | 2019 | 2020 | **2021** | 2022 | 2023 | 2024 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 97.6 | 97.7 | 96.5 | 97.5 | 96.2 | 95.9 | **77.0** | 94.8 | 95.9 | 96.4 |

Over the full 1985–2024 window the national mean is **93.68%** and the lowest
single month **74.12%** — the figures every national entry in the catalog
carries.

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
   as spliced, not continuous.**

State coverage is far worse than the national figure and the minimum is not a
2021 marker on its own. Of the 51 state scopes, **46 dip below 95% in some
month and 18 below 50%** — Kentucky to 0.31%, Iowa 0.45%, Montana 0.75%. By
mean, Mississippi is lowest at 60.82% and Illinois next at 73.02%; only five
states never fall below 95% in any month (DC, OK, RI, SC, TX), against 51.
`coverage_min_percent` is a screening field: use it to decide whether a series
can be modelled at all, and `nibrs_start_date` to date the break for a
particular agency.

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

Counted from the `series_count` field of each file as it stood on 2026-09-20
(they are being regenerated as this is written):

| File | Entries |
| --- | --- |
| `fbi_series_{violent_crime, homicide, rape, robbery, aggravated_assault}.yaml` | 114 each |
| `fbi_series_{property_crime, burglary, larceny, motor_vehicle_theft, arson}.yaml` | 114 each |
| `fbi_series_employment.yaml` | 10 |
| **total** | **1,150 across 11 files** (≈891 KB) |

114 is **57 scopes × 2 measures**: the nation, 51 states, and five city
departments — Washington `DCMPD0000`, New York City `NY0303000`, Chicago
`ILCPD0000`, Los Angeles `CA0194200`, Philadelphia `PAPEP0000`. That splits
1,040 national-and-state entries, 100 city entries and 10 employment entries.
Every entry is `unit: count`; the rate series are fetched, not catalogued, since
a rate is recomputable from the count and the population. 1,140 are Monthly and
10 Annual, all starting 1985-01-01, all carrying vintage `09/2026` and refresh
`09/15/2026`.

### Where each field comes from

| Source | Fields |
| --- | --- |
| **the payload** | `observation_start`/`_end`, `coverage_mean_percent`, `coverage_min_percent`, `sources[].vintage` and `.refreshed`, and `facets.geography` — an ORI resolves to the department's own name |
| **the request** | `series_id`, `concept`, `title`, `unit`, `frequency`, `facets.scope`/`offense`/`measure`, `retrieval` |
| **the agency registry** | `facets.agency_type`, `facets.state`, `facets.county`, and `nibrs_start_date` — present on the 110 agency-scoped entries only |
| **written by hand** | `definition`, from `OFFENSE_NOTES` and `MEASURE_NOTES`. The API has no dictionary, and what a clearance means (arrest *or exceptional means*), which rape definition applies, what `property-crime` excludes, are the caveats people miss |
| **generated later** | `description`, by `db_import.descriptions` — **21 buckets** here, against CDC's two and a half thousand series. Not yet generated: there is no `descriptions.yaml` under `notebooks/fbi/data/` |

`series_id` is `fbi/{offense}/{scope}/{measure}` for crime and
`fbi/employment/{ori}/{measure}` for staffing. The 21 description buckets are
`(group, concept, facet-shape, unit)`: two per offence, because agency entries
carry three facets the national and state ones do not, plus one for employment.

### The cost of a rebuild

One request per (scope, offence). 52 scopes × 10 offences = **520 calls** for
the national and state catalog, plus 10 per city and one per city for
employment — **575 calls** for the catalog as it stands. `PAUSE = 1.0`
second puts that at about ten minutes and keeps it inside the hourly
allowance; sustained traffic over 1,000 calls an hour needs 3.6. Failures are
collected rather than raised and written to `data/harvest_failures.json`, so
one bad scope does not lose the run.

Enumerating all 19,636 agencies is cheap — 51 calls — but **pulling them is
not**: 19,636 employment calls alone is about twenty hours at the allowance,
before a single offence. Choose the cities you intend to model.

## Tests

38, all passing, none touching the network: 25 in `tests/test_fbi_client.py`
over `httpx.MockTransport` with hand-built payloads, and 13 in
`tests/test_fbi_models.py`. What they assert is not parsing but **filtering** —
`test_a_state_request_drops_the_national_comparison`,
`test_an_agency_request_returns_the_agency_and_not_its_state`,
`test_a_national_request_keeps_its_own_united_states_series` — plus the
refusals that happen before a request is spent (an unknown offence, two
geographies at once, employment before 1985) and the nulls that must survive
the pivot. The client factory is local to the module rather than in
`conftest.py` so nothing there can read a real key or reach the network.

## Files

Under `notebooks/fbi/` unless stated; `data/` is gitignored and regenerable —
except `data/raw/agencies.json`, which is 51 calls to rebuild.

| Path | What |
| --- | --- |
| `clients/fbi.py` | `FbiClient`: `get_offenses`, `get_employment`, `get_agencies`, `get_states`, the static `route()`, and the label filter. The module docstring is the record of what was probed |
| `clients/models/fbi.py` | `FbiSeries` / `FbiObservation` / `FbiOffenseResponse` / `FbiEmploymentResponse` / `FbiAgency`. Pivots the CDE's chart-shaped `{block: {label: {period: value}}}` into flat series; `officers` sums male and female from the counts |
| `environment.py` | `get_data_gov_key()` (`DATA_GOV_KEY`) and `get_fbi_base_url()` |
| `utils/catalog.py` | `harvest()`, `harvest_employment()`, `entries_from()`, `employment_entries()`, `export()`; `OFFENSE_NOTES`, `MEASURE_NOTES`, `PAUSE`, the `STATES` fallback |
| `utils/fetch.py` | the earlier stdlib-urllib probe module: `summarized`, `agencies`, `police_employment`, `officers`, `probe`. Superseded by the client; see the correction above |
| `api.ipynb` | what one call returns, the coverage series by year, the three traps demonstrated live, the agency registry |
| `catalog.ipynb` | the request vocabulary, the five cities, the harvest, the export, coverage as a catalog field |
| `data/fbi_series_<group>.yaml` | 11 files, 1,150 entries — ten offences plus employment |
| `data/raw/agencies.json` | the registry, 19,636 agencies with ORI, type, county and `nibrs_start_date` (5.5 MB) |
| `data/raw/probe.json` | which offence slugs and scopes the API actually serves |
| `tests/test_fbi_client.py`, `tests/test_fbi_models.py` | 38 tests, no network |

## Known gaps

- **No MCP tools.** `fbi_offenses` and `fbi_employment` are named by every
  `retrieval` block and defined nowhere; `mcp_server/server.py` has 29 tools and
  none is one of them.
- **Not loaded.** `db_import.load_catalog.load(DATA_DIR, "fbi")` would work —
  the loader is source-generic and reads `fbi_series_*.yaml` — but
  `series_catalog` has no `fbi` rows today.
- **No descriptions.** The 21 buckets exist; `descriptions.yaml` does not.
- **Agency coverage is the state's** (trap 4), unlabelled as such.
- **`FbiSeries.measure` is `"value"` for population and coverage.** The field's
  own description lists `'population'` and `'coverage'` among its values, but
  `_measure()` matches only offences, clearances, officers and civilians and
  falls through to `"value"` for the other two. Live output confirms it:
  `District of Columbia   value   people` and `… value   percent`. Select those
  two series on `unit` — `"people"` and `"percent"` — which is what both
  `catalog.py` and the tests do.
- **Spans stop at 2024** by request default while the vintage is 09/2026.
- **Rates are fetched and not catalogued**, by choice: recomputable from the
  count and the population, which the payload carries.
