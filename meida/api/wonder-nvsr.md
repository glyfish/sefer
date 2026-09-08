# CDC WONDER & NVSS/NVSR Reference — mortality by cause and life tables

Reference for the two **non-Socrata** CDC mortality sources: **CDC WONDER**
(queryable deaths-by-cause) and the **NVSR life-table files** (life expectancy).
Companion to [cdc.md](cdc.md), which covers the Socrata API. Status: `WonderClient`
is **built** (navi `clients/wonder.py`, tests in `meida/tests`); NVSR is a
**planned file-based source** (manual annual downloads for now, per roadmap).

Inventory compiled 2026-08-31 from the authoritative CDC pages (WONDER data
summaries and API docs, NVSS/NVSR/VSRR product pages, the FTP tree, and the
Vital Statistics Online portal), each claim verified against the source text.

## The system: one dataset, three channels

**NVSS** (National Vital Statistics System) is the NCHS collection system for US
death certificates — every death, coded to ICD-10 by the 57 vital-registration
jurisdictions. Everything below is a *distribution channel over the same data*:

| Channel | Product | Life expectancy | Machine-readable |
| --- | --- | --- | --- |
| **CDC WONDER** | Queryable counts + crude/age-adjusted **rates by cause** × demographics × time | **No** — zero LE anywhere (verified) | XML-POST API (national-only for NVSS data) |
| **NVSR reports** | Curated publications, incl. the annual **life tables** | **Only channel** for NCHS LE | Life tables: **Excel on FTP**. Everything else: PDF |
| **Microdata files** | One record per death, 1968–2024 | No (compute-your-own) | Per-year fixed-width zips, no auth |

The channels are **complementary, not alternatives** — the project supports
WONDER (cause-specific series) *and* NVSR files (life expectancy); neither can
substitute for the other.

## CDC WONDER

### Access

- **API:** POST form field `request_xml` (plus `accept_datause_restrictions=true`)
  to `https://wonder.cdc.gov/controller/datarequest/{database-id}`. Response is
  XML with a `data-table`. Exports from the UI are tab-separated ASCII.
- **Bot filter:** plain httpx/requests get an Akamai 403 — `curl_cffi` with
  `impersonate="chrome"` passes (same trick as BLS). `WonderClient` does this.
- **Rate limit:** one robot, sequential queries, **~1 query per 2 minutes**
  (client self-throttles at 120 s). Cache every result.
- **National-only (NVSS rule):** API queries on vital-statistics databases
  cannot group *or* filter by any location or urbanization field (for D76:
  `V9`, `V10`, `V27` location; `V11`, `V19` urbanization). Sub-state data is
  web-UI-only. Everything else (year, month, MMWR week, cause lists, age, race,
  sex, ethnicity, autopsy, place of death) is API-usable.
- **Data-use terms:** never republish counts of 1–9 (or rates from them); keep
  citations and caveat footnotes with republished data; preserve suppression
  when re-assembling tables.
- WONDER shows a **modernization banner** ("changes are coming… in the coming
  months") — keep request/parse code defensive; database IDs change when a new
  vintage is released.

### The mortality databases

| ID | Database | Years | Race regime | Notes |
| --- | --- | --- | --- | --- |
| **D76** | Underlying Cause of Death | 1999–2020 | Bridged (4 groups) | Final; the long ICD-10 arc |
| **D77** | Multiple Cause of Death | 1999–2020 | Bridged | Final; up to 20 causes/certificate |
| **D158** | Underlying Cause, Single Race | 2018–2024 | Single race (6/15/31 lists) | Current final UCD |
| **D157** | Multiple Cause, Single Race | 2018–2024 | Single race | Current final MCD |
| **D176** | Provisional Mortality (MCD) | 2018–last week | Single race | Monthly updates; MMWR week; PR 2020+; final years spliced in (2018–2024 final embedded); injury/drug UCDs masked for trailing ~24 weeks; strictest suppression |
| — | Compressed Mortality | 1968–2016 | 3→4 groups | Closed; ICD-8/9/10 eras |

`WonderClient` has captured request skeletons for **D76 and D158 only**; D176
awaits capture. Stitch rule (verified): D76 for ≤2020, D158 for 2021+ — their
2018–2020 overlap agrees exactly.

### Query surface

**Measures** (D76 ids): deaths `M1`, population `M2`, crude rate `M3`,
age-adjusted rate `M4` (2000 US standard default), SE `M41`, 95% CI `M42`,
percent-of-total. Group by up to 5 variables.

**Cause classifications** — each usable as *filter and as group-by*:

- Full **ICD-10 codes** — chapter / sub-chapter / 3- and 4-digit (nothing finer
  than 4 characters); default selection is *all causes*.
- **ICD-10 113 Selected Causes** — NCHS's standard all-ages tabulation list.
- **130 Selected Causes of Infant Death**.
- **Drug/Alcohol-Induced** recode — a full partition (Drug / Alcohol / All other).
- **Injury Intent × Injury Mechanism** matrix (**UCD-only**).
- **15 Leading Causes** group-by (no cross-tab, no zero/suppressed rows).

**The "all available causes" pull:** group by the **113 Selected Causes recode**
— the help docs explicitly instruct grouping *by* it ("Group results by
'ICD-10 113 Groups' and also by 'Cause of Death' to see the individual ICD codes
included in each category"), so one query per database returns the complete
national cause × year table with precomputed age-adjusted rates. Two caveats
before building it: (1) the 113-list variable id is **not named in any doc**
(conventionally `D76.V4`) — harvest it from the request form / "API Options"
button; (2) `WonderClient` currently gets an HTTP 500 when adding the
drug/alcohol recode as a *second* by-variable (`B_2=D76.V25`), so the 113
group-by needs **one live test** for parameter ordering, and the response
parser must handle the extra cause column.

**MCD semantics:** multiple-cause group-bys count *any mention* — a certificate
contributes to up to 20 cause rows, so mention totals exceed persons. S/T-chapter
and symptom codes are valid as MCD but never UCD. Boolean AND joins two MCD
code-set boxes (codes within one box are OR).

### Quirks that bite ingest

- **Suppression:** sub-national counts of 1–9 suppressed everywhere; D176
  suppresses 1–9 even nationally (2018+). Totals suppressed if they'd disclose a
  suppressed cell.
- **"Unreliable" rates are hidden, not flagged:** D76 hides rates on <20 deaths;
  the single-race DBs (since the Feb-2026 release) hide rates whose 95% CI
  relative width exceeds 160% (Fay–Feuer). Compute rates from counts+population
  when the served rate is withheld.
- **Rates "Not Applicable"** (no denominator): month, MMWR week, weekday, place
  of death, autopsy, occurrence geography, subsets of 85+, not-stated
  age/ethnicity. Age-adjusted rates need 10-year age groups and are unavailable
  for infant groups.
- **3- vs 4-digit pitfall:** some deaths are coded to the 3-character code only —
  filtering on `A09.0` misses deaths coded `A09`. Enumerate both levels or use
  the recode lists.
- **Code validity varies by year:** ICD-10 additions in 2003/2006/2007/2009/2011,
  `U07.0` vaping (2019), `U07.1` COVID-19 (2020), `U09.9` post-COVID (2023,
  contributing-cause only). Known anomalies: GA 2008–09 and NJ 2009 `R99`
  inflation.

### Beyond mortality (same WONDER API)

NVSS-derived (national-only rule applies): **Natality** (births), **Fetal
Deaths**, **Linked Birth/Infant Deaths**. Other-program databases (location
allowed): **USCS cancer**, **STD morbidity**, **TB/OTIS**, **VAERS**, **NNDSS**,
six frozen NASA environmental sets, and the **population estimates** —
**Bridged-Race (ends 2020)** and **Single-Race (2010+)**, which are exactly the
denominators needed to compute rates from microdata. The many `/wonder/outside/`
entries (BRFSS, WISQARS, SEER, FARS, PRAMS, YRBSS…) are pointer pages to
external systems, **not** queryable via the WONDER API.

## NVSR / VSRR — the publication line

Two report families from NVSS:

- **NVSR** (National Vital Statistics Reports): annual finals — **US Life
  Tables** (data years 1997–2024), **State Life Tables** (2018–2022; lags US by
  ~2 years), Births/Deaths Final Data, linked-file infant mortality — plus
  special topics and decennial life tables. Finals publish ~1.5–2 years after
  the data year; **US Life Tables 2024 = NVSR 75-05, published 2026-08-25**
  (76.4 → 77.5 → 78.4 → **79.0** for 2021–2024 — above pre-COVID).
- **VSRR** (Vital Statistics Rapid Release): 44 numbered provisional reports
  since 2016 — annual provisional births/mortality/fetal/infant reports,
  topical analyses (specific drugs, xylazine, suicide), **all PDF-only**
  (supplemental tables included). **Provisional Life Expectancy was discontinued
  after data year 2022** (No. 31). Quarterly provisional estimates live in web
  dashboards; the drug-overdose and COVID surveillance data flow through
  data.cdc.gov Socrata datasets (`xkb8-kh2a`, `489q-934x` — already in the
  [CDC catalog](cdc.md)) and WONDER D176, not report files.

**Machine-readable rule of thumb: life tables are Excel; everything else is
PDF** (with the data behind PDFs reachable via WONDER, Socrata, or microdata).
The NVSR index page renders via a DataTables widget fed by a CSV
(`/nchs/js/report-table-filter-nvsr.js` names the URL) — scrape the CSV, not
the page.

### Life-table Excel files on FTP

Each life-table report has a companion directory of Excel workbooks at
[ftp.cdc.gov/pub/Health_Statistics/NCHS/Publications/NVSR/](https://ftp.cdc.gov/pub/Health_Statistics/NCHS/Publications/NVSR/)`{vol-no}/`.
Verified live: `75-05/` = Table01–18.xlsx (2024 national — 6 origin-race groups ×
total/male/female, mapping **one-to-one onto the dead Socrata `w9j2-ggv5`
race×sex schema**); `74-12/` = 204 per-state xlsx (2022). A ~20 KB Table01.xlsx
parses with **stdlib only** (zipfile + XML regex; `openpyxl` is not in the meida
env), yielding e0 = 78.971 → the published 79.0 — the xlsx carries ~3 more
significant digits than the report text.

Year → directory mapping (directory names are volume-number, **not** data year;
underscore + zero-padded through 2019, hyphen after):

| Data year | US dir | | Data year | US dir |
| --- | --- | --- | --- | --- |
| 2001 | `52_14` | | 2013 | `66_03` |
| 2002 | `53_06` | | 2014 | `66_04` |
| 2003 | `54_14` | | 2015 | `67_07` |
| 2004 | `56_09` | | 2016 | `68_04` |
| 2005 | `58_10` | | 2017 | `68_07` |
| 2006 | `58_21` | | 2018 | `69-12` |
| 2007 | `59_09` | | 2019 | `70-19` |
| 2008 | `61_03` | | 2020 | `71-01` |
| 2009 | `62_07` | | 2021 | `72-12` |
| 2010 | `63_07` | | 2022 | `74-02` |
| 2011 | `64_11` | | 2023 | `74-06` |
| 2012 | `65_08` | | 2024 | `75-05` |

State editions: 2018 `70-01`, 2019 `70-18`, 2020 `71-02`, 2021 `73-07`,
2022 `74-12`. Unmapped dirs to inspect before assuming: `54_13`, `56_10`,
`57_14`, `62_09`, `64_06`, `65_09`, `68_12`, `75-1`.

Ingest notes: the CDC life-expectancy page's FTP link list **stops at 2022** —
enumerate the FTP directory, don't trust the page; the products page mislabels
75-05 as "State" (the PDF's own title is *United States Life Tables, 2024*);
`ftp.cdc.gov` sits behind the same bot filter — `curl_cffi` + gentle pacing
(aggressive pulls trip a multi-day block).

## Microdata files — the bulk channel

The [Vital Statistics Online portal](https://www.cdc.gov/nchs/data_access/vitalstatsonline.htm)
serves **public-use record-level files**, no auth: **Mortality Multiple Cause,
1968–2024** — one zip per year (~146–161 MB recent, ~4.6 GB total), fixed-width
flat text + user-guide layouts (NBER hosts ready-made dictionaries and CSV
conversions). Each record: underlying cause, up to 20 record-axis ICD-10 codes,
cause recodes, demographics, month, place/manner of death. Also natality
1968–2024, fetal deaths 1982–2024, linked birth/infant-death files.

- **Reproduces WONDER exactly** for *national* tabulations of the same vintage —
  this is the no-throttle route to arbitrary cause × demographic tables.
- **No sub-national geography in public files from 2005 on** (restricted-use via
  RDC application); territories are separate files (1994+).
- **No denominators**: rates need the WONDER/NCHS population-estimate series
  (bridged-race ≤2020, single-race after) as a second ingest.
- **Files are silently replaced in place** when corrected (2021 file re-issued
  Dec 2023) — checksum on re-fetch. The 1972 file is a 50% sample (weight × 2).
- Cadence: final year *N* posts ~December of *N*+1.

## Deaths-by-cause: three routes compared

| Route | Coverage | Cost | Best for |
| --- | --- | --- | --- |
| WONDER, 113-recode group-by | All 113 causes × years, AAR precomputed | ~1 query/database (after the live test above) | **The full cause catalog** — recommended first move |
| WONDER, per-cause finder query | One cause set per query | 2 min each; despair set ≈ 16 queries ≈ 32 min | Custom ICD-10 groupings (despair series) |
| Microdata local tabulation | Anything, any grouping | ~4.6 GB + parsing + denominators | Long-run bulk / custom analyses beyond WONDER's dims |

Custom code sets for the despair series are documented verbatim in
[NVSR 70-08](https://www.cdc.gov/nchs/data/nvsr/nvsr70/nvsr70-08-508.pdf)
Technical Notes pp. 74–75: **alcohol-induced** (14 codes — matches
`ALCOHOL_INDUCED_ICD10` in `notebooks/cdc/wonder.ipynb` exactly),
**drug-induced** (~50 codes; 4-char F-code subselections that must be
enumerated — `.0`/`.6` members excluded), **drug overdose** (X40–X44, X60–X64,
X85, Y10–Y14 — formally a *subcategory* of drug-induced), **firearm**, and the
standard groupings for suicide (*U03, X60–X84, Y87.0) and chronic liver disease
(K70, K73–K74). A **deaths-of-despair composite must be one set-union query,
never a sum of series** — the sets overlap (X60–X64 is in both drug-induced and
suicide; X65 in both alcohol-induced and suicide).

## Known gaps / open items

- **113-recode group-by**: variable id unharvested; one throttled live query
  settles both the id and the `B_` ordering (the drug/alcohol recode as a second
  by-variable 500s — the reason `WonderClient` uses the codeset finder).
- **Finder acceptance** of asterisk codes (`*U01`–`*U03`) and sequelae codes
  (`Y87.0`/`Y87.1`) unverified — needed by the suicide/homicide/firearm sets;
  fallback is dropping them (<10 deaths/yr) and documenting the deviation.
- **D176 skeleton** uncaptured — blocks provisional-year cause series (2025+).
- **Per-state xlsx schema** (the 4 files per jurisdiction in `74-12/`) not yet
  examined — one download settles it.
- **Data-year → FTP-directory discovery** is manual: nothing programmatic links
  next year's volume-number; enumerate the FTP dir annually (fits the
  manual-download roadmap).
- National LE by **race** after 2020 exists *only* in these NVSR files — no API
  anywhere (FRED/World Bank/OECD/WHO/HMD all lack it; World Bank's 2024 total
  even contradicts the NCHS final: 78.89 vs 79.0). Keep FRED `SPDYNLE00INUSA`
  as a labeled cross-check only.
