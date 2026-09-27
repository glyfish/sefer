# FBI Historical — the agency files before 1985, and the printed tables before 1960

The [FBI reference](fbi.md) covers the Crime Data Explorer API, and that API
begins in **1985**. The FBI's own series do not. Return A — offences known and
clearances by arrest, agency by agency, month by month — runs from **1960**, and
the printed city tables run back to the first federal bulletin of **August
1930**. This page is the inventory of what exists before the API starts, which
of it is open, and what breaks inside it.

**Nothing here is built.** No client, no loader, no catalog entries, no rows in
Postgres, no notebook. What exists is an inventory: two research passes on
2026-09-21 and an independent verification pass the same day, which reparsed
**every** Return A year from 1960 to 1984 with a second parser written from the
FBI record layout rather than reusing the first. None of the three called
`api.usa.gov/crime/fbi/cde`, created an account, or edited the repo.

> **The working files are gone.** The three reports and their output — the
> independent parse (`reta_check.jsonl`), the assault-definition test
> (`assault_check.jsonl`), the downloaded masters, the archive.org metadata, the
> Wayback captures — lived in a session scratch directory that has since been
> wiped. Every figure below is transcribed out of them. **This page is now the
> only record**, and re-deriving any one number means re-downloading the master
> and parsing it again.

## How to read the claims

Three states, and they are meant to be distinguishable on sight. The default is
the strongest one, so anything weaker is marked in the line that makes it.

- **Unmarked** — *checked*: someone opened the source, parsed the file, or read
  the layout in one of the three passes. Where two passes agree independently,
  the text says so.
- **SAYS** — a source states it and nobody tested it against data. Usually
  [ucrbook.com](https://ucrbook.com/), Maltz, the 1967 Commission, or a
  depositor's release note.
- **UNSUPPORTED** — the citation does not show it, or the citation could not be
  reached. Collected in [§10](#10-unsupported-and-unchecked) so an unsupported
  claim cannot be mistaken for a checked one by being read out of context. Do
  not promote one of these without doing the work it names.

Everything time-varying carries the date it was checked. Sizes, file listings,
access terms and URL behaviour are all **as of 21 September 2026** unless a line
gives its own date; this page was written on 26 September 2026.

## 1. The inventory

| Dataset | First year | Grain | Best open source | Size, open route | API / master downloads start |
| --- | --- | --- | --- | --- | --- |
| **Return A** — offences known, clearances, officers killed and assaulted | **1960** (clearances 1964; simple assault 1964; officers 1974; unfounded 1983) | agency × month | archive.org [`fbi_ucr_cd`](https://archive.org/details/fbi_ucr_cd), 1960–92 and 2000–06, **no login**; a byte-identical 1960–2017 copy in the Trace item [`fbi-raw-data-files-nibrs-shr-return-a`](https://archive.org/details/fbi-raw-data-files-nibrs-shr-return-a) | **85.2 MB zipped** for 1960–84; 57–126 MB per year unzipped (2.25 GB unzipped in the Trace copy) | API 1985; masters 1985 |
| **ASR** — arrests by age, sex and race, Part I and II | **1974** monthly; 1960–73 annual, **MSA agencies only** | agency × month (1974+); agency × year (1960–73) | 1974–84 in `fbi_ucr_cd`, **no login**. 1960–73 only via [ICPSR 2538](https://www.icpsr.umich.edu/web/NACJD/studies/2538) | **211.5 MB zipped** for 1974–84; 467–645 MB per year unzipped | API 1985; masters 1985 |
| **Police employees** — sworn and civilian | **1960** | agency × year | **No open raw master.** Kaplan [openICPSR 102180](https://doi.org/10.3886/E102180V15) (sign-in), or his open five-city CSVs in [crimedatatool_helper](https://github.com/jacobkap/crimedatatool_helper) | 28.8 MB yearly CSV zip | masters **1991** (`pe`); see the note below |
| **LEOKA** — officers killed and assaulted | 1960; most breakdowns 1971 | agency × month | same as police employees; also Return A card 4 from 1974 | 218.7 MB monthly CSV zip | masters **1991** |
| **SHR** — homicide incidents | **1976** (a 1962–75 FBI layout exists; no data found anywhere) | victim / incident | 1980+ raw in the Trace item, **no login**. 1976–79 via ICPSR 9028 or Kaplan [100699](https://doi.org/10.3886/E100699V16) | 26.6 MB for 1980–84 raw | API 1985; masters 1985 |
| **Supplement to Return A** — property stolen and recovered | 1960 (few agencies until about 1966) | agency × month | Kaplan 105403 (sign-in); five-city CSVs open | not verified | API 1985; masters 1985 |
| **County offences and arrests** | 1977 (ICPSR aggregation); 1960 (Kaplan-built) | county × year | [ICPSR 8703 codebook](https://www.ojp.gov/pdffiles1/Digitization/115284NCJRS.pdf) 1977–83; Kaplan [108164](https://www.openicpsr.org/openicpsr/project/108164/version/V3/view) offences 1960–2017, arrests 1974–2016 | 28.5 MB offences DTA zip | — |
| **State and national estimates** | 1960 | state × year, nation × year | 1960–78: the annual *Crime in the United States* scans, [`pub_crime-in-the-united-states`](https://archive.org/details/pub_crime-in-the-united-states) — printed, to be keyed | about 25 MB PDF per edition | CDE estimates **1979** |
| **CIUS city tables** | 1958 | city × year | the same scans | as above | — |
| **UCR bulletins** | **Aug 1930** | city × month (1930–31); city × year (1934–57); **nothing in 1932–33** | 182 items on archive.org; [HathiTrust record 007406857](https://catalog.hathitrust.org/Record/007406857), 242 volumes, all Full view | 9–14 MB per issue | — |
| ICPSR 7715 — cities of 75,000+ | 1958 | city × year | [data.gov listing](https://catalog.data.gov/dataset/uniform-crime-reports-1958-1969-and-county-and-city-data-books-1962-1967-1972-merged-data) (sign-in) | unknown | — |

**The master-file downloads are a second route into 1985+, and they are not
metered.** The CDE webapp's static asset
[`masters.json`](https://cde.ucr.cjis.gov/LATEST/webapp/assets/JSON/downloads/masters.json)
gives `minYear` 1985 for `reta`, `asr`, `shr`, `supp` and `arson`, and **1991**
for `pe`; the webapp builds keys as `master_files/{id}/{id}-{year}.zip` and signs
them through `/LATEST/s3/signedurl`. Nothing earlier than 1985 is offered — the
FBI distributed the pre-1985 masters on CD, on request (**SAYS**, the
[January 2010 dissemination SOP](https://ucr.fbi.gov/additional-ucr-publications/ucr_dissemination_sops.pdf),
which lists Return A, the Supplement and Police Employee as 1960–current, Arrest
as 1974–current, SHR and Arson as 1980–current). A loader reading the masters
would get 1985 onward without spending any of the 1,000-per-hour API allowance,
which matters because the same fixed-width parser serves 1960–84 and 1985+: the
layout is titled "RETURN A UNPACKED MASTER 1960-Current".

**`pe` is dated differently in the two places.** The download list says 1991; the
API's `pe/agency/{ORI}` route answers from 1985, and `FbiClient` refuses
employment requests before 1985 ([FBI reference](fbi.md)). Both statements are
checked, in different artefacts, and the discrepancy is not resolved here.
Whichever is used, **neither reaches 1960**, and no open raw pre-1991 employee
master was found.

## 2. Return A: the file

From the FBI layout `retarecdesc.wpd` in the archive.org item ("RETURN A UNPACKED
MASTER 1960-Current", LRECL 7385):

- **One record per agency per year**: a header, then twelve month blocks of 590
  bytes.
- Each month block carries a **card type** (0 = not updated, 2 = adjustment,
  4 = not available, 5 = normal return) and then four cards of 28 five-digit
  fields: card 0 = unfounded, card 1 = actual offences, card 2 = total cleared,
  card 3 = cleared where all offenders were under 18. Then officers killed
  (felonious, accidental) and officers assaulted.
- **Negative values are IBM overpunch**: `}` = 0, `J` = −1 … `R` = −9,
  `1}` = −10 … `1N` = −15 (the FBI's `RetANegativeEntries.pdf`, in the Trace
  item). A parser that reads these as ASCII silently produces garbage, not an
  error.
- `Covered By` holds the ORI of an agency that files this one's return;
  `Month Included In` flags a month folded into a later month's return.
- The population field is the **sum of up to three county parts** — the layout
  says adding the three gives the city's total.

The 7-character ORIs in the masters are the CDE's 9-character ones minus the
trailing `00`: NYPD `NY03030`, DC MPD `DCMPD00`, LAPD `CA01942`, SFPD `CA03801`,
Nashville `TN01901`, each found under that ORI in every year 1960–84.

### Which fields exist in which years

Agencies with at least one non-zero value in each field group, out of agencies
with last month reported > 0. Parsed from the archive.org masters; the national
figures in this table were reproduced independently by the second parser.

| Year | Agencies reporting | of which "12 months" | Clearances | Under-18 clearances | Simple assault | Unfounded | Robbery knife/other | Larceny <$50 field | Officers killed/assaulted |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1960 | 7,046 | 5,933 | 0 | 0 | 0 | 0 | 0 | 5,927 | 0 |
| 1961 | 7,241 | 6,594 | 0 | 0 | 0 | 0 | 0 | 6,425 | 0 |
| 1962 | 6,553 | 5,888 | 0 | 0 | 0 | 0 | 0 | 5,812 | 0 |
| 1963 | 7,576 | 6,555 | **11** | 0 | 0 | 0 | 0 | 6,654 | 0 |
| 1964 | 7,249 | 6,373 | **6,767** | 5,850 | **4,376** | 0 | 0 | 6,466 | 0 |
| 1970 | 7,393 | 6,691 | 6,783 | 5,857 | 4,923 | 0 | 0 | 6,755 | 0 |
| 1973 | 9,781 | 8,642 | 8,898 | 7,493 | 6,488 | 0 | 0 | 8,659 | 0 |
| 1974 | 10,011 | 9,257 | 9,488 | 8,241 | 7,141 | 0 | **3,169** | **0** | **3,810** |
| 1979 | 14,039 | 13,233 | 12,457 | 10,507 | 9,929 | **0** | 4,508 | 0 | 5,737 |
| 1982 | 13,840 | 12,675 | 12,393 | 10,103 | 10,085 | 0 | 4,522 | 0 | 5,599 |
| 1983 | 13,769 | 12,967 | 12,337 | 9,917 | 10,083 | **8,009** | 4,353 | 0 | 5,357 |
| 1984 | 13,910 | 13,113 | 12,473 | 9,973 | 10,368 | 8,181 | 4,324 | 0 | 5,342 |

1965–69, 1977 and 1981 are missing from this table because the first pass skipped
them. The verification pass **did** download and parse all seven (25 MB of zips)
and found the five cities complete in every one, but it recorded only the
five-city results, not per-year national counts for those years. Those numbers
were never written down and the working files are gone.

- **1960–63 have totals only** — murder, negligent manslaughter, rape, robbery,
  aggravated assault, burglary, larceny, motor-vehicle theft, plus larceny under
  $50. No sub-types, no clearances.
- **1964 is where the file becomes rich**: rape split into force and attempt,
  burglary into forcible / no-force / attempted, aggravated assault by weapon
  (gun, knife, other, hands), simple assault, and clearances.
- Motor-vehicle theft splits into truck-or-bus and other vehicles from 1974;
  zero before.
- Unfounded counts are zero in **every** agency through 1982 and appear in 1983,
  which agrees with the layout ("all fields will be zeros for records prior to
  1983") and disagrees with ucrbook, which says 1979 with most agencies in 1983
  (**SAYS**). The 1979, 1980 and 1982 masters show none.
- Return A's officer fields are populated from 1974, 1979 included. Kaplan's V5
  note says 1979 has no officers-killed or officers-assaulted data (**SAYS**);
  that note predates his switch to FBI files and does not hold for the FBI 1979
  master, where 5,737 agencies have values.

## 3. The traps that make a loader lie

These are the difference between a loader that works and one that quietly
produces a plausible wrong series. Each is checked unless marked.

1. **"Number of Months Reported" is the *last* month reported, not a count.**
   The layout says so outright, and the data confirm it: in 1960, **812 of the
   5,933 agencies coded "12"** had fewer than twelve months of card-1 data and
   **167 reported December only**. In 1984, 685 and 5. Treating the field as a
   count admits December-only agencies as full-year reporters.
2. **The "assault total" field adds simple assault from 1974 and excludes it in
   1964–73.** Nationally, in at least **97%** of agencies holding both kinds of
   data in 1964–73, the total equals gun + knife + other + hands; in at least
   **98.9%** in 1974–84 it equals those four *plus* simple assault. The visible
   effect is a doubling that is not crime: NYPD 38,148 → 92,219, LAPD
   13,888 → 25,925, SFPD 2,650 → 6,953 across 1973/74, while the weapon-field
   sums run continuously (NYPD 38,148 → 41,068). **Aggravated assault must be
   built as the sum of the four weapon fields**, not read from the total.
   Kaplan's derived CSVs already correct this; the raw FBI files do not.
3. **1962 is missing nine states.** The master holds **zero records** for UT, VT,
   VA, WA, WV, WI, WY, AK and HI, against 69 Utah, 172 Virginia and 116
   Washington records in 1961. Maltz: the 1962 data for state numbers 43–51
   "were inadvertently erased during an electronic update" of the master files
   (**SAYS**). None of the five cities is affected, but any 1962 national or
   state aggregate is.
4. **The reporting population doubles: 7,046 agencies in 1960 to 14,169 in
   1980.** Summing agencies is therefore *not* a trend — the sum measures the
   program's growth as much as the country's crime. A long series needs either a
   fixed agency panel or the FBI's own state and national estimates
   ([§6](#6-state-and-national-estimates-196084)).
5. **The "robbery with a gun" field means all armed robbery in 1964–73.** In
   1970, for 4,186 of the 4,205 agencies with a breakdown, gun + strong-arm
   equals the robbery total; the separate knife and other-weapon fields start in
   1974. A robbery-by-gun series breaks at 1974. Use the robbery total before
   then.
6. **Larceny under $50 is a separate field only through 1973.** The master's
   larceny total always includes all values (LAPD 1960: total 57,738, of which
   under $50 = 36,321), but the published Crime Index counted only larceny of
   $50 and over until 1972/73. To rebuild a published-comparable pre-1973 index,
   subtract the under-$50 field.
7. **Negligent manslaughter includes traffic deaths until about 1978.** LAPD
   147 → 1, SFPD 27 → 0 and Nashville 49 → 0 across 1977/78; LAPD ran 197 in
   1960 and 120 in 1975. Exclude negligent manslaughter from any homicide series
   that spans the 1970s.
8. **Zero and did-not-report are not distinguishable** in the offence fields
   (**SAYS**, ucrbook §1.4.3). Card types 4 ("not available") and 0 ("not
   updated") help and are imperfect.
9. **Negative counts are real**: late unfoundings and adjustments. Nine agencies
   had a negative annual murder or burglary total in 1979, three in 1976. Maltz
   treats −1 to −3 as corrections and ≤ −4 as coding error, and notes 999/9999
   used as missing codes (**SAYS**).
10. **Clearances include exceptional clearances with no split** (**SAYS**,
    ucrbook §3.4.2). Only NIBRS separates them. Clearances are counted in the
    month they happen, not the month of the offence, so a city can clear more
    murders than it recorded — DC in 1970: 225 cleared against 221 recorded.
11. **Covered-by agencies file inside someone else's return** — Belle Meade and
    Oak Hill are covered by Nashville `TN01901` in 1975–84. Covered-by status is
    recorded annually and can be wrong within a year (**SAYS**, Maltz).
12. **There is no agency-level imputation** (**SAYS**, Maltz: the FBI imputes
    only to state, regional or national level). The NACJD county files *are*
    imputed, with a new algorithm from 1994.
13. **All pre-1985 rape data use the legacy, female-victims-only definition**
    (**SAYS**, ucrbook §3.5.1); the revision is 2013.
14. **Arson is not in Return A.** It became the eighth Index offence in 1979 and
    has its own return (**SAYS**).
15. **ICPSR's 1981, 1982 and 1983 Return A parts were once wrong** — corrected
    in 2016, and the 1983 parts had held "the wrong year of data" until 2014
    (**SAYS**, ICPSR 9028 version history). An old download of those parts is
    bad. This is an argument for the archive.org FBI masters over a
    redistribution.

## 4. The five walkthrough cities, 1960–1984

The walkthrough notebooks use `NY0303000`, `DCMPD0000`, `CA0194200` (LAPD),
`CA0380100` (SFPD) and `TN0190100` (Nashville) — checked in the notebooks on
26 September 2026 — and all five are present in Return A with **last month
reported = 12 and twelve months of card-1 data in every one of the 25 years**,
verified year by year, not sampled. Murders as parsed:

| Agency | 1960 | 1964 | 1970 | 1975 | 1980 | 1984 |
| --- | --- | --- | --- | --- | --- | --- |
| NYPD | 390 | 636 | 1,117 | 1,645 | 1,812 | 1,450 |
| DC MPD | 81 | 132 | 221 | 235 | 200 | 175 |
| LAPD | 154 | 177 | 395 | 554 | 1,010 | 759 |
| SFPD | 36 | 50 | 108 | 138 | 110 | 73 |
| Nashville | 36 | 59 | 64 | 93 | 87 | 72 |

The NYPD figures match the widely published NYPD annual murder totals, but those
were not looked up in a primary source (**UNSUPPORTED** as an external check).

Note that the **catalog's** five agency scopes are a different set — DC, NYC,
Chicago `ILCPD0000`, LA and Philadelphia `PAPEP0000` ([FBI reference](fbi.md)).
**Chicago's and Philadelphia's pre-1985 agency records were never opened in any
of the three passes.** Both appear in the printed record with known recording
breaks ([§7](#7-the-printed-record-193057-and-the-1958-wall)), which is a reason
to expect trouble, not a substitute for parsing them.

Breaks inside the five city series, all from the independent parse:

| City | Break | Evidence |
| --- | --- | --- |
| NYPD | **Recording change from March 1966** | Robbery 8,904 (1965) → 23,539 (1966) → 35,934 (1967); burglary 51,072 → 120,903. Monthly robbery 796 (Feb 1966) → 1,263 (Mar) → 1,750 (Apr). Matches the 1967 Commission's "New York 1966 robbery total estimated to be 23,000 … burglary … 120,000" |
| NYPD | Larceny and burglary fall in 1972 | Larceny 187,232 → 134,664; burglary 181,331 → 148,046. **Unexplained — flag it, do not model through it** |
| NYPD | Simple assault usable **1964–76 only** | 1977 has Jan–Mar only (5,807); 1979 has Feb and Mar only (6,658 together); zero in 1978 and 1980–84 |
| All five | Assault total jumps in 1974 | Trap 2 above — a definition change, not crime |
| LAPD | **No clearances 1964–68** | First clearances appear in 1969 (46,733), five years after most agencies |
| LAPD, SFPD, Nashville | Traffic deaths leave negligent manslaughter in 1978 | 147 → 1, 27 → 0, 49 → 0 |
| SFPD | Larceny spike 1962–64 | 16,838 (1961) → 36,077 (1963) → 21,638 (1965). **Unexplained** |
| Nashville | **Metro consolidation 1963** | Population 253,386 (1960–62) → 433,554 (1963) → 443,240 (1964), under the same ORI with no new code. Metro government began 1963-04-01 (**SAYS**, nashville.gov). Every rate spanning 1963 needs care |
| Nashville | Assault reclassification 1965–71 | Aggravated 311 (1964) → 1,529 (1967) while simple falls to 168 (1971). Likely coding, not crime |
| Nashville | Clearances missing **1980–81** | Total clearances 304 and 205, against about 3,700 in the neighbouring years; cleared murders 0 in 1980 and 4 in 1981 |

## 5. The other pre-1985 files

**ASR arrests.** Monthly from 1974 and open (211.5 MB zipped for 1974–84), with
layouts in the same archive.org item: `asrmthrec7479.wpd` (LRECL 503) and
`asrmthrecdes.wpd` ("ASR UNPACKED MASTER 1980-Current", LRECL 471). What it
costs:

- **Nashville is effectively absent before 1985**: three monthly headers in 1974
  (Jun, Sep, Nov), one in 1975 (May), none in 1976 or 1977, one in 1979 (May),
  none in 1984. Kaplan's derived per-agency CSV has **no Nashville rows before
  1992**. DC's derived rows are empty in 1979 and 1982.
- **Nothing agency-level is open before 1974.** 1960–73 exists only as annual
  counts for MSA agencies in ICPSR 2538, behind a sign-in. All five cities are
  MSA core cities; none could be checked. ICPSR 2538 received its 1960–72 data
  in 1976, and 1973, 1977 and 1979 later (**SAYS**).
- **The layout breaks at 1980**: ages go from Under 11 / 11–12 / 13–14 to
  Under 10 / 10–12 / 13–14, race goes from White, Negro, Indian, Chinese,
  Japanese, Other to White, Black, Indian, Asian, and ethnicity exists only in
  the 1980+ layout. **One parser cannot span 1979/1980.** The 1984 file's agency
  header also puts the name and population at different positions from the
  1974–79 files.
- **The drug sale-versus-possession split first has data in 1976**, though the
  1974–79 layout already lists the codes. 1974–75 give drug type only.
- Ethnicity was reported by about 60% of agencies in the early 1980s, peaked in
  1986 and then by essentially none from 1987 to 2016 (**SAYS**, ucrbook §5.3.3).
- **Build arrest totals yourself.** Kaplan's `all_arrests_total_total_arrests`
  reads 532,806 for NYPD 1974, roughly double the sum of his own offence totals
  (about 257,000 after removing the drug-sale and gambling sub-types). The fault
  is in the aggregate column. The first pass's independent sum, 259,987, is about
  1% from that, and the difference was not reconciled.
- Series to distrust on sight: NYPD "all other offences" 41,099 (1975) →
  252,284 (1976) → 414,034 (1984); NYPD drunkenness 0 from 1976; NYPD suspicion
  0 in every year; DC DUI 1,246 in 1974 and about 0 after; LAPD drunkenness
  14,928 (1981) → 1,591 (1982); marijuana possession 0 for both LAPD and SFPD in
  1976, the first year of the split.
- ASR counts **arrests, not people**, and the hierarchy rule applies (**SAYS**,
  ucrbook §5.2.1).

**Police employees and LEOKA** — the enforcement half of the pairing the FBI
work exists for, and the part with **no open raw source before 1991**.

- The reference date moves: **April 30** through 1959 and **December 31** for
  1960, both read off CIUS, then October 31 later (**SAYS**, ucrbook §7.2.1).
  Comparing a 1959 count to a 1960 count compares different months.
- **1960–70 have no male/female split**: the totals sit in the *male* fields and
  the female fields are zero, which reads as "no female officers" rather than
  "not collected". Sex breakdowns start in 1971. Patrol and shift staffing is
  zero for 1960–70 too.
- **"Record Indicator 2 = contains Police Employee data from previous year"** —
  counts can be **carried forward**. A repeated value is not evidence of a stable
  force until that flag is read.
- Zeros that mean missing, in the five cities: SFPD 1964–65 and 1967–69, DC 1966.
  NYPD 1963 = 29,423 sits between 24,835 (1962) and 25,897 (1964) and is a
  likely error; NYPD civilians swing 2,643 (1967) → 3,696 (1968) → 2,017 (1969).
  Sworn officers for orientation: NYPD 23,519 (1960) → 31,671 (1970) → 22,590
  (1980); DC 2,540 → 5,055 → 3,652; LAPD 4,661 → 6,806 → 6,587; SFPD
  1,698 → 1,820 → 1,738; Nashville 318 (1960, city only) → 467 (1963,
  Metro) → 1,006 (1980). About 7% of all agencies report more officers or
  civilians than population (**SAYS**, Kaplan).
- LEOKA: officers killed feloniously from 1960, but **accidental deaths are
  folded into the felonious field before 1972** per the FBI layout (Kaplan says
  1971, **SAYS**). Assaults by call type, by time of day, and assaults cleared
  all start in 1971. Whole years are blank for the five cities while employee
  counts are present: NYPD 1974, 1977, 1982; DC 1966, 1972; LAPD 1972–74, 1979;
  SFPD 1964–65, 1967, 1969, 1972–74; Nashville 1972, 1976, 1979. SFPD shows **18
  officers feloniously killed in 1982**, which is an error. Agencies reporting
  drop from about 8,400 in 1960 to a trough near 4,800 during the 1960s
  (**SAYS**, ucrbook §7.1), so LEOKA's own denominator moves.

**SHR.** Raw FBI masters are open for 1980–2017 in the Trace item;
`SHR1980.DAT` holds 22,215 records of 268 bytes, of which NYPD 1,741, DC 180,
LAPD 1,019, SFPD 119 and Nashville 93 — against Return A 1980 murders of 1,812,
200, 1,010, 110 and 87. The two never match: SHR is a voluntary separate return
carrying no clearance outcome (**SAYS**, ucrbook §6). **1962–75 appears to be
lost**: an FBI layout for it exists (`Shr1962To1975.pdf`, dated 12/06/1990, LRECL
101, one victim per record, offender *sex* only, and a **single-digit year** so
that 1962 and 1972 are distinguishable only by tape order), but the data are on
no portal — not CDE, archive.org, ICPSR or openICPSR — and the FBI's own 2010 SOP
lists SHR only from 1980.

**Supplement to Return A.** Value stolen is **0 in 1960 for all five cities** and
non-zero from 1961; LAPD is 0 in 1983 and 1984 and Nashville 0 in 1963. It adds
nothing to enforcement intensity.

**County files are derived, not FBI tables.** ICPSR 8703's codebook is explicit:
agencies reporting 6–11 months are **weighted up to twelve**, those under six
months are **dropped**, and statewide-only agencies are **allocated to counties by
population**. Treat the output as a model, not a count.

## 6. State and national estimates, 1960–84

Needed precisely because trap 4 makes summed agencies uninterpretable as a trend.

- **1979 onward** comes as a CDE estimates file, from the downloads page rather
  than the API. Not verified.
- **1960–78 has to be keyed** from the *Crime in the United States* state tables
  on archive.org. Every edition is present; the 1960 edition carries "Table 2.
  Index of Crime by Geographic Division and State". The job is about **19 years ×
  51 areas × 8 columns**.
- **The retired UCR Data Tool is not a shortcut.** It served state and national
  estimates for 1960–2014 — the Wayback capture of
  [its state page](https://web.archive.org/web/20201031163816/https://www.ucrdatatool.gov/Search/Crime/State/StatebyState.cfm)
  offers 55 year options — but **its result pages were never archived**, so only
  unofficial copies of its output survive (for example
  [CrimeStatebyState.csv](https://github.com/futuraprime/homicides/blob/master/CrimeStatebyState.csv),
  violent crime only, header checked). Use one to *check* the keying; do not make
  it the source.
- **The FBI revised its own history.** Prior years were re-estimated back to a
  1937–40 average base period for cities that changed reporting systems in
  1959–65, assuming a changed city followed its size-and-state peers. A figure
  printed in a 1960–78 edition can differ from the later re-estimate of the same
  year, so a keyed series must record which edition it came from.

## 7. The printed record, 1930–57, and the 1958 wall

The FBI published city-by-city counts from the first federal bulletin, August
1930. It exists **only as printed tables**, and the whole run is open with no
login: 182 items on archive.org, 242 Full-view volumes on HathiTrust. **No keyed
version of the pre-1958 city tables was found** — searches turned up only the
scans, which means none surfaced, not that none exists. The first machine-readable
city panel is ICPSR 7715, 1958–69, which adds only 1958–59 over Return A.

What was actually read off the page images:

- **Four of the five cities can be read monthly from August 1930** — Los Angeles
  (2,183 Part I offences, 3 murders), San Francisco (1,503 total), Washington
  (784 total, 5 murders), Nashville (156 total, 4 murders).
- **New York City is absent from the August 1930 table** (the New York list runs
  New Rochelle, then Niagara Falls) and from all of 1932, which the bulletin
  states. Its first readable year here is the **1934 annual** (359 murders /
  1,250 robberies). It is absent again in 1949 — "Complete data not received" —
  and the 1967 Commission says 1949–51.
- **NYC counts before 1950 are not credible as levels.** In 1934 NYC recorded
  1,250 robberies against Chicago's 14,444, and the Commission reports Chicago at
  about eight times NYC's robberies in 1935 and says the FBI stopped publishing
  NYC in 1949 because it no longer believed the figures. Before 1950, anchor NYC
  on death-certificate homicide, not on police records.
- **There are no individual-city tables in 1932–33.** The Q4 1933 bulletin says
  individual-city publication resumes in Q1 1934, and its Table 4 sums 70 cities
  rather than listing them — so a 1933 NYC city figure cannot exist. 1931 is
  still unchecked.
- Los Angeles did not report in Q1 1932.
- **Police employees by city are in the printed record too**: August 1930 Table
  IV gives LA 2,679 (2.2 per 1,000), DC 1,394 (2.9) and Nashville 200 (1.3), with
  NYC and SF not listed; later bulletins carry the same table as of April 30
  (1946 and 1959 contents pages checked).
- **The OCR is unusable for tables.** City names come through; numeric columns
  scramble — San Francisco's 1940 row reads "26 574 339 2, 675 HM 6, 494 2, 625".
  The page images are clean. Getting the five cities out means **keying or
  re-OCRing specific pages**: roughly 30 annual tables × 5 cities × 7–9 columns,
  about **1,200 numbers**, plus 17 monthly issues if 1930–31 monthly detail is
  wanted.
- Publication frequency, from the issue dates rather than the ICPSR abstract
  (which is wrong): monthly Aug 1930 – Dec 1931, quarterly 1932 through the
  January 1942 issue, semiannual 1942–57, one annual report from 1958.

**1958 is a hard break, and the FBI says so in its own words.** The 1958 annual
created the Crime Index, dropped negligent manslaughter, larceny under $50 and
statutory rape from the headline offences, made the estimating procedures
"entirely new", and switched rate denominators from the latest decennial census
to annual population estimates. It states that no valid comparison can be drawn
with the totals in previous issues, excepting rates for 1930, 1940 and 1950. The
1967 Commission's verdict: figures before 1958, "and particularly those prior to
1940, must be viewed as neither fully comparable with nor nearly so reliable as
later figures."

So: **do not chain national totals across 1957/58.** Treat pre-1958 UCR as
indices from fixed city panels — which is how the FBI itself published trends
("74 cities over 100,000, 1931–35") — and splice only murder and non-negligent
manslaughter at city level, remembering that pre-1958 "criminal homicide" tables
carry negligent manslaughter in a column that must be excluded. Flag every
city-level recording change: **NYC 1950** (robberies rose 400% and burglaries
1,300% after a central complaint system) **and 1966**, **Chicago 1959** (central
complaint bureau; robberies rose several-fold), **Philadelphia 1953** (a new
administration found years of under-recording and reported crime rose over 70%
against 1951), and Washington, criticised for not recording every offence
reported to it.

## 8. The long-run complements

Police records measure recording as much as crime, so a long series needs at
least one measure that does not come from a police department.

- **Homicide from death certificates.** National from 1933; 1900–32 covers the
  death-registration area only, which is biased low because low-homicide states
  registered first and early homicides were often coded as accidents. Klebba
  (1975) anchors it: 9.7 per 100,000 in 1933, 4.7 in 1960, 9.8 in 1973. Eckberg
  (1995) estimates corrected national rates for 1900–32, reprinted in HSUS Table
  Ec190-198 — **behind a Cambridge subscription**, with the data rows not in the
  public page. ICD revisions move the codes at 1939, 1949/50 and 1968, and the
  ICDA-8 range includes legal intervention, which Klebba reports separately.
  CDC's HIST290 tables for 1900–39 contain **no homicide** at all (all 154 pages
  parsed). County-level history exists in the NCHS multiple-cause microdata for
  **1959–2004** only — geography is restricted from 2005 — and CDC WONDER's
  [Compressed Mortality 1968–78](https://wonder.cdc.gov/cmf-icd8.html) carries
  county with ICD-8 behind click-through terms. **The anchor works for DC, SF,
  the five NYC counties and Davidson County, and fails for LAPD**, because Los
  Angeles City is not Los Angeles County.
- **Victimization.** NCS from 1973, national only, except the 1972–75 city
  surveys: NYC and LA in 1973 and 1975, SF and DC in 1974, **no Nashville**. The
  1992–93 redesign is a break. Direct state estimates exist only from 2017, for
  22 states.
- **Prison counts.** National Prisoner Statistics gives year-end sentenced
  prisoners by state from **1925** in one open BJS table. Two traps: "yearend" is
  the 1 January count of the *following* year, and 1925–70 include some
  misdemeanants while 1971–86 are felons only. The collecting agency changed four
  times (Census Bureau, Bureau of Prisons, LEAA, BJS).

**meida already holds a long-run homicide series, and its last value is wrong.**
`clio/homicide_rates/united_states` in `notebooks/clio/data/timeseries/clio.jsonl`
runs **1900–2010, 111 observations, no gaps**, `live: false`, from Clio Infra's
Homicide Rates workbook (Fink-Jensen 2015, revising Bierman & van Zanden 2014).
Checked against independent sources:

| Year | Clio | Independent | Verdict |
| --- | --- | --- | --- |
| 1900 | 1.2 | registration-area rate; Eckberg argues it is too low for the nation | 1900–32 are **registration-area rates, not national** |
| 1933 | 9.7 | Klebba 9.7 | match |
| 1960 | 4.7 | Klebba 4.7 | match |
| 1973 | 9.7 | Klebba 9.8 | off by 0.1 |
| 2010 | **4.2** | **5.3** — 16,259 deaths, [NVSR 61(4)](https://www.cdc.gov/nchs/data/nvsr/nvsr61/nvsr61_04.pdf) p. 40 | **wrong by about 20%; do not use it** |

The workbook documents no source per year, and the series carries two decimals
for 1979–85 and 2003–05 and one elsewhere, which suggests several sources
stitched together without a recorded join. It is usable as a shape, not as a
level, and the 2010 value should not be served to anything.

## 9. What to build, what it costs, what it buys

**Take one thing first: the Return A masters for 1960–1984 from archive.org.**

- **85.2 MB zipped, open, no login, no agreement, no key.** That is the whole
  acquisition cost. Parse from the zips — unzipped they are 57–126 MB a year.
- **One fixed-width parser** against LRECL 7385, with overpunch decoding for
  negatives and the card-type codes retained. The evidence that this is small:
  two independent parsers were written from the same layout in one session, and
  the second reparsed all 25 years and reproduced, figure for figure, every
  national count the first had produced for the years it covered.
- **Load rules, not optional**: aggravated assault = the sum of the four weapon
  fields; pre-1974 larceny ≥ $50 = total minus the under-$50 field; murder and
  robbery *totals* rather than the weapon fields before 1974; negligent
  manslaughter excluded from homicide; "months reported" read as the last month
  and the card-1 months counted separately; and **a flag per city and year for
  every break in [§4](#4-the-five-walkthrough-cities-19601984)**. A break the
  loader does not record is a break the consumer will model through.
- **What it buys: all five walkthrough cities, agency × month, for the 25 years
  before the CDE API starts** — 300 months per city, complete, verified year by
  year rather than sampled. And it is the *same FBI series* the API serves, so
  one loader spans 1960 to the present; the Trace copy of 1985–2017 can test the
  join at the 1985 boundary independently of the API.
- **What it does not buy**: a national or state trend (trap 4), any arrest
  series before 1974, and any employment series at all.

**Then the estimates** ([§6](#6-state-and-national-estimates-196084)) — 1979+ as
a file, 1960–78 as a keying job of about 7,800 numbers — because without them
there is no legitimate denominator-free national trend to put the city panels
against.

**Then enforcement intensity, which is where a login becomes unavoidable.**
Per-agency police employment for 1960–84 exists in no open raw form. The routes:

| Route | What it needs | What it gives |
| --- | --- | --- |
| Kaplan [openICPSR 102180](https://doi.org/10.3886/E102180V15) | a **free openICPSR account the user would have to create**, plus a terms-of-use acceptance (**SAYS** — ICPSR returned 403 to every automated fetch in all three passes, so even the sign-in requirement is unverified) | employment and LEOKA, 1960–2024, all agencies; 28.8 MB yearly, 218.7 MB monthly |
| Kaplan's [crimedatatool_helper](https://github.com/jacobkap/crimedatatool_helper) CSVs | nothing — open on GitHub | the five cities only, 1960–2024, **derived**; adequate as a stopgap and as a cross-check, not as a store |
| ICPSR 2538 | the same account | the only pre-1974 agency arrest data anyone found, annual, MSA agencies |
| FBI CJIS on CD | a request to the FBI (`cjis_comm@leo.gov` in 2010); current availability unknown | the raw pre-1985 masters the archive.org items do not carry |

An account is a decision for the user to make, not something to be worked
around: the derived CSVs are Kaplan's processing of the same files, and trap 2
plus the arrest-total error in [§5](#5-the-other-pre-1985-files) are both
evidence that a derivation can be right about one thing and wrong about another.

**Deliberately last**: county-level death-certificate homicide as an independent
check on the police counts; the 1930–57 printed tables, about 1,200 hand-keyed
numbers that break at 1958 anyway; SHR and the Supplement, which add nothing to
enforcement intensity.

## 10. Unsupported and unchecked

Listed so nothing here can be mistaken for verified. **UNSUPPORTED** means the
citation does not establish it; *unchecked* means nobody looked.

- **That ICPSR and openICPSR need only a free sign-in.** Search-snippet only.
  ICPSR returned HTTP 403 to every automated fetch, its pages are
  JavaScript-rendered, and no account was created, so the actual terms behind the
  login are unread. openICPSR is also mid-migration between platforms (DOIs
  persist).
- **ICPSR 6792's "12 cities including Los Angeles and New York City"** — search
  snippet; the page was never opened.
- **Kaplan 102263 covering 1974–2024.** The V15 capture says 1974–2021; V16 was
  not visible.
- **Kaplan 105403's 100.6 MB size** — not checked. The Supplement's zipped size
  is not verified at all.
- **Whether the FBI still holds SHR 1962–75**, and whether a 1975 SHR part exists
  in ICPSR 9028 — unchecked.
- **Whether a non-member can download a whole HathiTrust volume as one PDF** —
  unchecked.
- **Chicago and Philadelphia before 1985** — never parsed, though they are two of
  the catalog's five agency scopes.
- **The 1976–79 SHR layout** exists as a scanned PDF in the Trace item and was
  never transcribed.
- **Arson before 1985** rests entirely on what the sources say.
- **The 1959–65 Commission "Figures Not Comparable With Prior Years" table** did
  not survive text extraction; the list of affected cities beyond NYC, Chicago
  and Philadelphia is unread.
- **Per-year national field counts for 1965–69, 1977 and 1981.** Parsed in the
  verification pass, never written down, and the output file is gone.
- **The `pe` start year**, 1991 in `masters.json` against 1985 in the API — both
  checked, the conflict unresolved.
- **1931 city tables** — unchecked, so NYC's true first readable year may be 1931
  rather than 1934.
