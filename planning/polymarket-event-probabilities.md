# Polymarket — Event Probabilities as a Data Source

**Status: written 26 September 2026 as a feasibility study, and revised the same
evening against the corpus it asked for.** Stage 1 below was built rather than
scheduled, and at four venues instead of one: **50,689 markets, 2,426,246
market-days, horizons out to 890 days, authoritative settled labels throughout**,
in [`meida/notebooks/prediction_markets`](#the-corpus-that-answers-this-document)
— venue readers, a metric catalogue and four notebooks. So the question this document
called decisive is answered with data, **three of its recommendations are wrong**,
and six of its factual claims needed correcting or narrowing. Figures added in
this revision are marked *measured* and were computed from that corpus, then
re-derived by an adversarial verification pass **from the raw files without
importing the analysis code**, reproducing to the printed digit. Everything
unmarked is as the original research run left it, with its original markers.

**Verdict: unchanged in shape — feasible but narrow — and now narrow for a
measured reason instead of an argued one.** Building it is still easy: three
unauthenticated hosts, no key, no quota, and collecting the whole 72,838-market
Polymarket corpus cost **4,521 requests, 898 MB and sixteen minutes, with zero
HTTP 429s, zero retries and zero errors** (*measured*). What is narrow is the
price. The clause that used to read "no published calibration evidence beyond one
month, from any source" is now a measurement rather than a gap: across the three
venues that have history, **the price sits above the outcome from a month out and
by +9.0 points at one to two years** — bias **−0.4pp** inside a day, **+3.0pp** at
7–30 days, **+8.3pp** at 180–365 days, **+9.0pp** at 1–2 years, Brier skill
falling **0.767 → 0.106** and the linear slope 1.033 → 0.726, on 168,644
independent market-bucket rows — and **it is not composition**: restrict to the
markets that lived a year, which fixes the realised rate by construction, and the
gradient survives and grows. The depth objection stands exactly as measured
(median executable depth within a cent of the touch **$199** bid and **$495** ask
across the forty highest-`liquidityNum` long-dated geopolitics markets; **zero of
thirty sides** on the flagship fifteen-rung ladder clears $10,000 within a cent,
median **$533**), so the two objections now meet from opposite ends: at the
horizon this project models, a price is both **quoted rather than traded** and
**directionally wrong by about a tenth**. At one month and in, all three venues are
calibrated to within three and a half points and two of them to within half a
point — the short-horizon panel this document recommended is the part that survives
measurement.

**Recommendation, revised.** The corpus was the right thing to build first, it is
built, and it is the asset — **keep it, extend it, and do not put a long-dated
price into a model.** Four changes to what this document originally asked for:

1. **The watchlist shortens from ≤6 months to ≤30 days.** That is the band where
   the bias is under half a point on Kalshi and IEM and 3.4 points on Polymarket.
   At 30–180 days a price is usable only with a horizon-specific bias subtracted,
   and even then carries Brier skill of 0.29–0.40; past a year, skill is 0.11 and
   subtraction is most of what is left.
2. **The quality floor is one line, and it is not the one below.** Polymarket
   `volume_num ≥ $1,000,000` (keeps 14% of markets past 30 days, standardised bias
   **+0.1pp** from +7.5pp) or Kalshi `peak_open_interest ≥ $10,000` (keeps 56%,
   +0.5pp from +2.8pp). **Delete the relative-spread gate of §1.4** — measured, it
   makes calibration worse than no filter at all.
3. **Take the label from `/v2/resolutions`, never from the last price.** 26.9% of
   stored daily paths do not end at the settled value.
4. **Build Kalshi first for macro** — unchanged, and now measured rather than
   architectural: `KXCPIYOY` settles against BLS CPI-U, and **BLS's own published
   twelve-month change reproduces 45 of 45 checkable settlements** to the decimal
   the contract is written to, against 33 of 45 for the seasonally adjusted FRED
   series. The rule names an agency and a concept; the settled history names the
   series.

Still: no Postgres, no SDT driver, no trading path in the repo, and no catalogue
of the universe.

**Spans:** meida (client, tools, catalogue), yada (any monitoring workflow and
the corpus load), alef (the calibration analysis).

| Phase | Owner | Work | State, 26 Sep 2026 |
| --- | --- | --- | --- |
| Calibration corpus | meida notebook → alef | Labelled corpus + reliability curves by horizon | **Done, and wider than scoped** — four venues, 50,689 markets, four notebooks under `notebooks/prediction_markets/` |
| Client + tools | meida | `clients/polymarket.py`, wire models, 2–4 MCP tools | Not started; the notebook readers (`utils/polymarket.py`, 2,091 lines) are the prototype |
| Catalogue | meida | File catalogue per tag, daily snapshot, `_int` mirrors | Not started; the harvest already carries a 58-tag curated registry and `_int` mirrors |
| Watchlist monitoring | yada | Depth-floor refresh, alert predicates, plots | Not started; re-scope to ≤30 days |

---

## How to read the numbers below

Everything here came out of a five-pass research run on **26 September 2026**:
four independent probe passes plus one adversarial verification pass that
re-tested ~90 of their claims against the live APIs and the cited primary
sources. All calls were **read-only and unauthenticated** — `User-Agent` only, no
wallet, no order, nothing installed — from a US residential IP through
Cloudflare's IAD/ATL edge.

The corpus was harvested and analysed **the same day, after that run** — the
Polymarket harvest is stamped `2026-09-26T19:43Z` and the cross-venue corpus was
assembled that evening. Figures from it are marked *measured* and are the
strongest evidence in this document: they come from files on disk, they were
re-derived without the analysis code, and they rest on settled outcomes rather
than on a live read that will be different tomorrow.

Unless marked, a figure was **called live on 2026-09-26 and reproduced by the
verification pass**. Markers:

- *measured* — computed from the labelled corpus (50,689 markets), and reproduced
  by an adversarial verifier reading the raw files. Reproducible offline; no
  network call re-runs it.
- *this revision, single pass* — derived from the corpus files for this revision
  only, by one pass, and **not** re-derived by anyone else. Three figures carry
  this marker; treat them as provisional in exactly the way the *single pass* rows
  below are.
- *single pass* — measured once against the live API, not re-tested. Probably
  right; not corroborated.
- *documented only* — the vendor's docs say it; nobody called it.
- *reported* — press or third-party claim, cited but not independently checked.
- ***UNSUPPORTED*** — a figure carried through from a cited paper that the
  citation as given **does not contain**. Two such figures appear below, both from
  the same paper, and both are labelled at every mention.
- *discrepancy* — two passes measured it differently and the conflict is unresolved.
- ***REFUTED*** — a claim or recommendation **this document made** that the corpus
  overturned. Struck where it stands, with the measurement that overturned it.

Per the repo's own rule that measured figures get an independent re-derivation
before they are trusted, treat the *single pass* and *this revision* rows as
provisional. **Everything about an open market is a live read and carries the date
it was checked; everything about a settled one is in the corpus and does not
move.** That distinction now does most of the work in this document: the census,
the depth measurements and the price quotes below are all 2026-09-26 snapshots of
a book that changes hourly, while every calibration number is a property of
markets that have already finished.

---

## The corpus that answers this document

Built 26 September 2026 in `meida/notebooks/prediction_markets/` — four venue
readers (`utils/polymarket.py`, `kalshi.py`, `predictit.py`, `iem.py`) plus a
corpus loader (`corpus.py`, `corpus_iem.py`), a metric catalogue
(`utils/metrics.py`, 17 measure families and a `NOT_COMPUTABLE` list of nine) and
four notebooks (`calibration.ipynb`, `polymarket.ipynb`, `kalshi.ipynb`,
`predictit_and_iem.ipynb`). The exported corpus under `data/` is **gitignored and
regenerable**, per the repo's convention for exported catalogues; nothing commits
it.

| Venue | Markets | Market-days | Median life | Base rate YES | Price basis |
| --- | --- | --- | --- | --- | --- |
| Polymarket | **46,223** | 1,646,552 | 12d | 22.4% | last trade, forward-filled |
| Kalshi | **4,367** | 743,022 | 235d | 27.5% | daily candle mid, else close |
| IEM | **99** (contract rows) | 36,672 | 286d | 27.3% | last trade |
| **PredictIt** | **0** | **0** | — | — | **no history API** |
| Total | **50,689** | **2,426,246** | — | — | longest horizon 890 days |

*All measured.* What was lost getting there is part of the finding:

- **Polymarket** 72,838 closed markets harvested → 55,233 with a stored daily path
  → **46,223** that also have a settled YES/NO and at least three prints.
- **Kalshi** 100,233 settled markets → 4,393 in the stratified candle pull →
  **4,367** settled yes/no (162 `scalar` markets — halted and paid out at a price
  rather than settled against the world — excluded rather than scored).
- **IEM** 89 resolved markets → 34 winner-take-all with terminal top-two
  separation > 0.5 → **99** contract-level binary rows. Vote-share markets are
  dropped entirely: pooling them with winner-take-all produces a reliability curve
  that is wrong in a way no diagnostic catches, because both look like prices.
- **PredictIt contributes nothing, and that is the venue's own doing.**
  `GetMarketChartData` returns **exactly seven days** — twelve request variants
  (`24h 7d 30d 90d 1y all ALL max 5y`, the parameter omitted, `days=365`,
  `showHidden=true`) came back byte-comparable at 42 rows, 7 dates, 6 contracts —
  and **only the first six contracts of a market**, silently, which on the
  eleven-rung House-seats ladder drops the entire upper tail. Every contract the
  API serves is Open; nothing settled is retrievable. **The venue most often
  called the research venue cannot contribute a single labelled observation**, and
  a deeper archive is obtainable by asking a human under an academic agreement,
  not by code.

**The independence reduction, which is why the n's here are smaller than any
market-day count.** A market contributes one price per day for its whole life, so
a 365-day market is 365 rows of approximately the same forecast. Every headline
number uses **one observation per market per horizon bucket** — the print nearest
the bucket's geometric centre — which takes 2,426,246 market-days to **168,644
market-bucket rows**, a 14.4× inflation removed. Bootstraps resample **markets**,
not rows. No p-value here is exact: rows from one market stay correlated across
buckets even after clustering.

**Cost of collection, for the plumbing estimates in §4.** The Polymarket harvest
was **4,521 requests / 898 MB / 960 s**, 3,638 of them to the CLOB host, 524 to
Data API v2 and 359 to Gamma, with **zero 429s, zero retries and zero errors** —
which confirms this document's "politeness, not quota, sets the pace" at a scale
the research run only sampled.

---

## What this revision changed

| This document said | What the corpus says | Status |
| --- | --- | --- |
| §1.4 — a relative-spread gate at ≤10% is the right liquidity filter | On Kalshi at 30 days and beyond, `median_rel_spread ≤ 0.10` moves the standardised bias from **+2.8pp to −12.1pp** — \|bias\| **9.4pp worse** — and the standardised Brier from **0.101 to 0.182**, on 23% of markets. At ≤0.05: −24.7pp, 22.0pp worse, on 8.4%. **Every threshold in the recommended direction hurts**; the direction that helps is loose (≤0.50 improves \|bias\| 2.7pp keeping 65%) | ***REFUTED*** |
| §1 — "**never** use `volume` or `liquidity` as a quality filter" | Right about the *number*, wrong as an instruction. `volume_num` is the strongest honest discriminator measured: standardised \|bias\| **15.9pp in its bottom quintile against 0.05pp in its top** at 30–180 days, ρ −1.00 across all five bins, **+0.1pp above $1M**. What it separates is markets that traded from markets that did not. Use it as a **floor**, never as a ranking, and never read its magnitude as depth | ***REFUTED as stated*** |
| §1 — "Use `openInterest` and depth you compute yourself" | Backwards for Polymarket, right for Kalshi. Polymarket's retained `event_open_interest` does **nothing** (−0.5pp at 30–180 days, +0.9pp beyond, ρ +0.5 then −0.5). Kalshi's `peak_open_interest` cuts bias **12.2pp** at range — but only because it is recovered from the candle path: the settled market row reads zero on **3,732 of 4,369** markets, so a screen reading OI off the row scores every settled market on the venue as having attracted no interest | ***HALF REFUTED*** |
| §4/§5 — a resolved market's path terminates "in a tick at the settled value" | **26.9%** of stored daily paths disagree with the settled value (14,825 of 55,158). The resolving move usually lands inside one bucket and the daily print misses it. **Take the label from `/v2/resolutions`, never from the last price** | **CORRECTED** |
| Verdict — "every market leaves a bounded `{date, value}` series" | **17,605 of 72,838** closed markets (24.2%) return no stored daily path at all — and they are not the short-lived ones. Their median life is **42 days** (p90 194) against 10 days for the markets that do have a path; their median reported volume is **$0**, 88.8% are at zero or absent, and the order book was enabled on 17,598 of them. No trade, no forward-filled series: the mechanism is absence of trading, not absence of retention *(this revision, single pass)* | **CORRECTED** |
| §5 — the structured `resolutionSource` field "carries nothing usable" | It is non-empty on **12,728 of 72,838** closed markets (17.5%), with only **117 distinct values**, 12,478 of them deep links: `x.com/elonmusk` (4,844 markets), a WTI price app (1,671), `truthsocial.com/@realDonaldTrump` (726), `x.com/khamenei_ir` (707), `tsa.gov` passenger volumes (617). It is populated where the source is a **feed** and absent where the contract needs a judgement — on the geopolitics tag it is **52 of 7,928** markets. So: a hint on a sixth of the book, near-useless on this project's sixth *(this revision, single pass)* | **CORRECTED** |
| §1.7 — correct with "a longshot haircut below ~10¢ (≈ ×0.8)" | The haircut is aimed at the wrong part of the book. The published −19.3¢/$ reproduces at **−19.6%** in the 5–10¢ band, but that is a **return on an absolute gap of 1.38¢**; below 2¢ the gap is **0.23¢** and the ratio −51.9%. The largest *absolute* mispricing is **25–50¢**, on both large venues independently: **+9.21¢** Polymarket, **+6.70¢** Kalshi. And it is a horizon interaction, not a price effect: +2.10¢ intraday → +11.86¢ at 7–30 days → **+24.40¢** at 180–365 days on Polymarket, and −8.03¢ → **+21.72¢** on Kalshi, a sign flip. **A flat haircut is the wrong instrument** | **CORRECTED** |
| §1.1 — the "X by *date*" ladders are cumulative | Five kinds, not one, across **3,787** ladders detected in the closed corpus. And a by-date ladder is a CDF **only for an absorbing event**: **63 of 1,034** settled non-monotonically, YES at one deadline and NO at a later one, because for a recurring event the re-issues are *rolling* windows rather than nested ones | **CORRECTED** |
| §1 — "discount adjustment removes 48–88% of the apparent long-horizon miscalibration gradient" (imported from arXiv:2605.31431) | Cannot be the gradient measured here, **by sign**. This corpus's long-horizon error is the **price above** the outcome; the discount correction moves the price **up**. On the live fifteen-rung ladder the correction is +0.03¢ at 36 days and **+4.21¢ at 462 days** — about one point of a nine-point gap *(this revision, single pass)*, applied in the direction that **widens** it. Either the published gradient is a different quantity (a compression slope, not a mean gap) or it does not survive out of sample; the paper's body is still unread | **CORRECTED** |
| §2 — "**Calibration beyond one month.** No evidence exists, from any source" | True of the literature as of 2026-09-26, and no longer true of this stack. See the new tables in §2 | **ANSWERED** |

**Confirmed at scale, and worth saying because each was a single-market or
single-pass result before.** The fidelity cliff (`/prices-history` on a resolved
market returns `{"history": []}` with HTTP 200 below `fidelity=720`, and the
corpus is pinned at 1440); 12-hour buckets permanent and **3-hour buckets not**,
against the docs; `liquidityNum`, `spread` and `volume` unusable as depth or as
interest; the resolution prose as the only place the contract lives, median 912
characters across 72,838 closed markets and **absent on none of them**; `slug` as
editorial rather than identifying (two events one word apart pricing the same war
**2–8¢** apart); `endDate` wrong by design and sometimes grossly — two live rungs
carrying **$281,191** of reported liquidity dated **667 days in the past**; and the
depth floor of §1.3 still annihilating its own universe.

---

## Access

**No authentication, on any read path.** Three hosts, ~25 distinct endpoints,
verified by calling each with only a `User-Agent`. The CLOB OpenAPI spec declares
`security: []` on the read routes.

- `https://gamma-api.polymarket.com` — metadata (events, markets, series, tags, search).
- `https://clob.polymarket.com` — prices, order books, midpoints, spreads.
- `https://data-api.polymarket.com/v2` — the modern price-history route and the
  authoritative resolution record. **The backlog missed this host entirely, and it
  is the one that matters.** Spec at `/v2/openapi.json`, 20 endpoints,
  `securitySchemes: null`.

**No rate limit is published for Gamma or CLOB reads**, and no `x-ratelimit-*`,
`ratelimit-*` or `retry-after` headers are exposed. The only documented numbers
anywhere are for Perps (1,000 weighted tokens/min/IP) and for authenticated
trading tiers, which say only "Standard"/"Highest". Observed, deliberately
stopping short of the ceiling: CLOB `/midpoint` **87 req/s** across 120 requests,
CLOB `/prices-history` **155 req/s** across 60, Gamma `/events/keyset` **81
req/s** across 60, 190 sequential Gamma pages at 0.35 s pacing, ~250 CLOB book
requests at ~3 req/s — **zero HTTP 429 in any of it**. The Data API v2 spec says
a `429` with `Retry-After` exists for heavy queries; one pass reported v2
`/trades` 429-ing on its second call, but **that did not reproduce** (ten
consecutive calls, all 200, no `Retry-After`). Honour `Retry-After` because the
spec says it exists; do not design a separate budget around it. Against the FBI's
1,000/hour and WONDER's one-per-two-minutes, **Polymarket is the least
constrained source in the stack** — politeness, not quota, sets the pace.

**Reads from the US are permitted; trading is not, and that separation is
clean.** The docs state "Read-only market data is not subject to these
restrictions" — *note that sentence sits on the Perps geographic-restrictions
page, so it is a scoping caveat rather than a blanket grant*. What is directly
verified: every call in this run succeeded from a US IP, and polymarket.com's own
restriction strings gate on **trading** only (`pm-us-geoblock`,
`tradingUnavailableInRegion`, "not (i) a U.S. person"). No scraping, data-mining
or automated-access prohibition appears in the served document — *though the full
Terms of Use prose sits inside a JS payload that was not fully extracted, so this
is keyword absence plus the UI attestation language, not a reading of the whole
contract.*

Collateral is no longer USDC: it is **pUSD**, an ERC-20 wrapper on Polygon backed
by USDC. Materially it is still a non-yielding claim in the holder's hands, which
matters in §1.

**The SDK question: use a thin `httpx.AsyncClient`, not the vendor SDK.** The
official `polymarket-client` 0.11.0 (uploaded 2026-09-23, `requires_python
>=3.11`) is fine on meida's 3.14.7 and its core deps are meida's own stack
(`httpx[http2]`, `pydantic>=2`), but it also pulls `eth-abi`, `eth-account`,
`eth-utils`, `msgpack`, `websockets` — all of it for signing and trading. It went
0.3.0b2 → 0.11.0 inside a year. The read surface is a dozen GETs and one POST
with no signing. **Pulling `eth-account` into meida quietly installs
transaction-signing machinery into a repo whose stated goal is to keep read-only
strictly separate from any trading path.** Read the SDK for its pagination and
`as_of` semantics; do not import it. (The backlog's "official Python, TypeScript
and Rust SDKs" is wrong on one count: the unified **Rust SDK is "in
development"**, per the docs verbatim.)

---

## 1. What the price is, and what it is not

A Polymarket price is a **risk-neutral, fee-distorted, capital-locked, oracle-
conditional quote on whether credible reporting will converge on X by a date**.
It is not a forecast and it is not a probability until it is corrected. Every
wedge below is quantified, and they do not all point the same way.

### The wedges

| Wedge | Direction | Size, measured | Applies to |
| --- | --- | --- | --- |
| **Taker fee** | price above true p | `fee = shares × rate × p × (1−p)`, rate **0.04**, taker only. Buying at 0.05 costs 0.0519 all-in (**+3.8% of stake**); at 0.50, +2.0%; at 0.95, +0.2%. No-arbitrage band `2·rate·p(1−p)` — 2 points wide at p=0.5 | Politics (`feeType: "politics_fees"`). **Geopolitics is genuinely fee-free** (`feeType: null`, `feeSchedule: null`), verified live on *Will China invade Taiwan by end of 2026?* and in the docs fee table |
| **Capital lock-up** | price **below** true p | pUSD pays the holder nothing, so a claim settling in τ years should trade near `p·exp(−rτ)`. Treasury par yields 2026-09-25: 3m **4.24%**, 1y 4.50%, 2y **4.81%**, 3y 4.94% | Everything, scaled by horizon |
| **Holding Rewards** | offsets the lock-up | Polymarket pays an annualized rate on the mid-price value of positions in a curated set. **25 of 1,500 events carry an "Earn 4%" tag and 555 markets have `holdingRewardsEnabled: true`** *(single pass)* — and they are precisely this project's markets (2028 nominees/winner, 2026 midterms, Taiwan 2026, Xi/Putin/Netanyahu/Zelenskyy exit, Russia–Ukraine ceasefire). The live tag says 4%, the help article 3.25%; the rate is variable at Polymarket's discretion | The 555 flagged markets |
| **Favourite-longshot bias** | price above true p at the low end | Published: purchases **below 10¢ lose 19.3¢ per dollar**; at/above 90¢ they earn 0.83¢. **Reproduced and re-sited** (*measured*): −19.6% in the 5–10¢ band on 10,194 rows, but the absolute gap there is **1.38¢** and below 2¢ it is **0.23¢** — the big ratio is a small gap over a small denominator. The big *gap* is at **25–50¢**: +9.21¢ | Crypto and Politics; **absent in Sports**; and **absent in Polymarket's own geopolitics subset** (+0.01¢ at 5–10¢, and *inverted* at 10–25¢ where the realised rate exceeds the price by 3.29¢) |
| **Horizon bias** — *the wedge this table was missing* | price above true p, growing with time to resolution | Pooled across three venues (*measured*): **−0.4pp** inside a day, **+3.0pp** at 7–30 days, **+5.6pp** at 30–90 days, **+4.6pp** at 90–180 days, **+8.3pp** at 180–365 days, **+9.0pp** at 1–2 years — **growing but not strictly monotone**: the 90–180 day dip is in the pooled numbers and on Polymarket (+7.0pp at 30–90 days against +6.7pp), while Kalshi rises straight through it (+0.3pp to +1.3pp). Bootstrap intervals clustered on markets exclude zero from 7–30 days on Polymarket and from 90–180 days on Kalshi. Survives holding the market set fixed | Everything, on both large venues, and **worst on Polymarket geopolitics at range: +14.0pp beyond 180 days** against −0.8pp pooled over all horizons |
| **Compression toward 50%** | both directions | Published: mean calibration slope **0.99 at 0–1h rising monotonically to 1.32 at 1 month+**; Polymarket 1.31 vs Kalshi 1.64, "a structural property of political prediction markets rather than a single-platform artefact". **Not reproduced** (*measured*): the corpus's linear slope of outcome on price runs the other way, **1.033 → 0.726** with horizon, and its logit slope — printed only for comparability, a coarse binned fit the notebook explicitly declines to stand behind — is **1.340 inside a day falling to 0.983 by a year** on Polymarket. Two different estimators; **treat this wedge as unconfirmed rather than as measured in either direction** | Politics, both venues |
| **Oracle risk** | unpriced, tail | UMA optimistic oracle: anyone proposes with a bond, 2-hour challenge window, escalating to a token-holder vote. **`umaBond` is $500 on the $42.9M Taiwan market** and $25,000 on the 2028 nominee markets — bonds are trivial relative to stakes | Everything |

**The two biases largely cancel at the low end, and that is not a reason to
ignore them.** A 5¢ conflict quote is simultaneously ~20% too high in relative
terms (longshot bias) and a few percent too low (lock-up, if the market is not
reward-eligible). The corrections must be applied **per market, conditional on
`holdingRewardsEnabled` and on `feeType`** — not as a blanket curve.

**And measured, the low end is where there is almost nothing to correct.** Both
of those wedges are sub-cent quantities at 5¢, while the corpus says the error
that matters is **+9.2¢ in the middle of the book pooled, and +24.4¢ there at six
to twelve months**. The practical ordering is the reverse of the one this section
originally implied: fix the horizon first, the mid-range second, and the longshot
haircut last if at all.
The discount correction is measured on a live ladder below and is worth
**+0.03¢ at 36 days and +4.21¢ at 462 days** — a rounding error at the front and
**four times the bid-ask spread** on the last rung, which is the one fact in this
table that a reader is most likely to have the wrong way round.

**The discount magnitude is the weakest link in the chain, and it is labelled.**
One pass cited *Gebele & Matthes, "When Certainty Is Not Worth It: Capital
Lock-Up and Settlement Discounting in Prediction Markets,"*
[arXiv:2605.31431](https://arxiv.org/abs/2605.31431) for an annualized settlement
wedge of **3.06%–6.89%** over **4,273 markets / 154,298 near-certainty
observations**. Verification found those figures ***UNSUPPORTED*** — they are not
in the abstract, and the body was not read. What **is** confirmed verbatim from
that paper is the important part: **discount adjustment removes 48–88% of the
apparent long-horizon miscalibration gradient**, leaving a residual
statistically indistinguishable from zero. So roughly half to nearly all of
Polymarket's long-horizon "miscalibration" is arithmetic rather than error, and
is correctable — but until the paper's body is read, **use today's Treasury curve
(4.24–4.94%) as the anchor for `r`, not the 4.4% constant one pass proposed.**

**That inference does not survive contact with this corpus, and the reason is the
sign.** The long-horizon error here is the **price sitting above the outcome** —
+8.3pp at 180–365 days, +9.0pp at 1–2 years (*measured*) — and the discount
correction raises the price further. Applied at the Treasury curve it is worth
about **1 point of that 9** at a mean price near 0.27, in the direction that
**widens** the gap rather than closing it *(this revision, single pass — the
arithmetic is first-order, on the corpus's own mean price and the measured rung
corrections, and nobody has re-derived it)*. So either the published "gradient" is
a different quantity from a mean gap — most likely a compression slope, which this
corpus also fails to reproduce — or it does not survive on a near-population
sample. Two things follow and both are
operational: the discount is still the right correction to apply **before
differencing a ladder** whose rungs settle at different dates, because there it
removes a real artefact; and it is **not** an explanation of the horizon bias, so
nobody should expect subtracting it to make a long-dated price usable.

An independent attempt to measure the wedge directly failed honestly and is worth
recording: on the two deepest long-dated exclusive sets, CLOB mids sum to
**0.9005 at 774 days** and **0.8795 at 848 days**, implying 4.95% and 5.53%
annualized — but 88 of those 128 outcomes are placeholders or ask-only quotes at
the 0.001 minimum tick with no bid. Valuing them at zero gives that answer;
valuing them at their ask gives 0.9885, implying **0.55%**. The honest statement
is that **the implied wedge at 774 days lies somewhere in [0.55%, 4.95%] and this
measurement cannot narrow it**, because multi-outcome sums confound discounting
with unpriced residual mass. *Nobel Peace Prize Winner 2026* makes the point
brutally: it sums to **0.606**, which would "imply" 98% annualized; the real
cause is that the winner is usually not on the list.

### What the number resolves on

**The market measures whether credible reporting will converge on X, not whether
X happens.** Current geopolitical resolution prose is genuinely rigorous — the
backlog's worry about ambiguity is wrong, and the opposite of the truth. The
NATO × Russia market defines a "military encounter" with an inclusion list, an
exclusion list and *named historical precedents* used as calibration ("the June
2021 Black Sea Confrontations… will not qualify"; the 2023 Su-27/MQ-9 collision
"will not qualify regardless of damage"). The Russia–Ukraine ceasefire market
specifies a **10-calendar-day continuity test** with four worked qualifying and
non-qualifying precedents. The mobilization market enumerates qualifying legal
acts and excludes "ordinary conscription decrees; electronic summons or
draft-register measures".

But the standard is "a consensus of credible sources", and the text explicitly
provides that **where government statements conflict with credible field
reporting, "the reporting will take precedence."** Precise criteria,
discretionary judge. For splicing into a structural model that is a definitional
caveat to write down, not a defect — but it is the caveat, and three documented
failures are all in this project's own categories (*reported*, press sources, not
independently checked):

- **Ukraine mineral deal, March 2025** ($7M+) resolved "Yes" with no agreement
  reached; one UMA whale voted 5M tokens across three accounts, 25% of votes.
  Polymarket: "because this wasn't a market failure, we are not able to issue
  refunds."
- **Zelenskyy's suit, July 2025** (**$237M**) resolved **No** after two dispute
  rounds and nine days, despite 40+ outlets describing the 24 June NATO outfit as
  a suit; UMA held there was insufficient "credible reporting consensus."
- **US–Iran permanent peace deal, June 2026** (**$177M** on the 15 June market,
  $479M across deadlines) resolved **Yes** on a 14 June MoU that itself provided
  for a 60-day negotiation period. Reported vote concentration: largest holder
  16.7%, top five 41.7%, top seven 50.3%, all voting yes.

Also: **resolution is not strictly 0/1.** A UMA "Unknown / 50-50" vote settles
each token at **$0.50**, so the outcome column is not boolean. `was_disputed` is
in the resolution record and is a quality flag worth storing.

### Volume is not an interest signal, and liquidity is worse

These two fields are the ones a catalog would naturally key on, and both are
unusable.

**`liquidityNum` = total resting-bid notional across *both* the Yes and No token
books.** Decoded against real CLOB books on five markets, ratios **0.996–1.000**.
Because the No side of a cheap outcome is bid near $1, that side dominates:

- *Oprah Winfrey* for the 2028 Democratic nomination has **zero bids** on the Yes
  token and `liquidityNum = $2,884,506` — six times the $450,370 reported for
  Gavin Newsom, the front-runner.
- Taiwan 2026: **$614,953 = $565,400 of No bids + $49,497 of Yes bids.** If you
  want the tail side, usable depth is a twelfth of the headline.
- *Will LeBron James win the 2028 Democratic presidential nomination?*
  `liquidityNum = $2,893,341`, `volume24hr = $1.00`, and the actual book has
  **zero bids** and 57 ask levels stacked at $0.001–0.005 — while Gamma still
  reports `spread = 0.001`.

**Reported volume is self-evidently not an interest signal.** Within *Democratic
Presidential Nominee 2028*, which reports **$1,285,481,603** of volume against
**$10,075,637** of open interest — **128× turnover** on a two-year-horizon
market:

| Outcome | Reported volume | Price |
| --- | --- | --- |
| **Oprah Winfrey** | **$54,420,375** | **0.0005** |
| Bernie Sanders | $52,751,863 | 0.0045 |
| LeBron James | $43,986,477 | 0.0005 |
| Kim Kardashian | $42,919,729 | 0.0005 |
| MrBeast | $41,009,545 | 0.0005 |
| *Gavin Newsom (front-runner)* | *$27,757,018* | *0.1525* |

**88.5% of that event's volume sits in outcomes priced under 2¢, 84% under 1¢**
*(single pass; verification reproduced the pattern on the sibling 2028 Winner
event at 87% and 77.7%)*. The dead outcomes cluster near-uniformly at $35–55M
volume and $2.5–2.9M "liquidity" with volume/liquidity of 14–19×, while live
outcomes show $533k–1.15M. That uniformity is the signature of programmatic
reward-farming, of wash trading, or of both, and **it cannot be apportioned from
the API**: across 3,005 political markets `volumeClob` equals `volumeNum`
*exactly* at every percentile, the old AMM is gone, and there is no cross-check.
Contemporary *reported* estimates for the 2024 presidential market put wash
trading at roughly one third of volume (Chaos Labs) and real volume near $1.75B
against a reported $2.7B (Inca Digital).

~~The conclusion that survives is sufficient: **never use `volume` or `liquidity`
as a quality filter.** Use `openInterest` and depth you compute yourself.~~
***REFUTED as stated.*** Everything above is about what the number **means**, and
all of it holds: volume is unauditable, `volumeClob` equals `volumeNum` at every
percentile, and it turns over 128× on a two-year market. But a filter can work
while the number it filters on means nothing, and these are answers to different
questions. Measured on 46,223 settled Polymarket markets with the price mix held
fixed (*measured*):

- **`volume_num` is the strongest honest discriminator in the whole catalogue** —
  standardised |bias| **15.9pp in the bottom quintile against 0.05pp in the top**
  at 30–180 days, rank correlation −1.00 across all five bins, and Δ|bias| growing
  to **−18.4pp** at 180 days–2 years. What it separates is markets that traded from
  markets that did not, which is why the bottom quintile is where the
  miscalibration lives. **Use it as a floor, never as a ranking, and never read
  its magnitude as depth.**
- **`event_open_interest`, which is the open-interest figure a closed market
  actually retains, does nothing** — −0.5pp at 30–180 days, +0.9pp beyond, ρ +0.5
  then −0.5. Kalshi's `peak_open_interest` cuts bias **12.2pp** at range, but only
  because it is recovered from the candle path: on Kalshi the settled market row's
  `open_interest` reads **zero on 3,732 of 4,369** markets (`PRES-2024-KH`: row 0,
  candle peak **84,647,638** contracts). The concept is right; the *vintage* on
  Polymarket is not, and an event-level figure read after settlement is not the
  peak a market ever carried.
- **Three of the vendor's own quality fields cannot be evaluated at any price,
  and never will be.** On the closed corpus `liquidity_num` survives on **13.5%**
  of markets and `competitive` on **13.6%**, both with a median of zero and 246
  and ten distinct values between them; `spread` survives on 100% and reads 0.001
  on books with no bid. They are not versioned upstream, so there is no way to ask
  retrospectively whether any of them predicted anything — the only route is to
  start snapshotting them daily from now on, which is the same
  irrecoverable-by-construction problem as the editable `description`.
  **Retention is itself a quality metric, and nobody lists it.**
- **Two fields look like the best discriminators in the table and are the outcome
  wearing a quality field's name.** `best_bid` moves standardised |bias| from 8.69¢
  to **75.84¢** across its quintiles at ρ 1.00 — because on a settled market
  `bestBid` is frozen at the resolving value. Any backtest of this kind has to
  drop `best_bid` and `best_ask` first; standardising the price mix does not
  protect against a column that contains the label.

**And the headline number can be one person's estimate.** The 2024 "French
whale" deployed **>$85M** across election markets through four accounts
Polymarket confirmed were one trader, holding **>20% of Trump-winning shares**
against 7% for the largest Harris holder (*reported*). He was right, and it was
conviction rather than manipulation — but it defeats a wisdom-of-crowds reading
of the price.

### The filters that follow

Apply to the **market**, not the event. Each is backed by a measurement above.

1. **`negRisk == true`** before any sum-to-1 reasoning; exclude `groupItemTitle`
   matching `Person [A-Z]` (augmented-neg-risk placeholders the docs say never to
   trade). The "X by *date*" ladders are **cumulative, not exclusive** — the
   Russia–Ukraine ceasefire ladder legitimately sums to **6.77** across its date
   buckets, so a naive sum-to-1 check flags correct markets. **And `negRisk` alone
   does not tell you which of five ladder shapes you are holding** — see the new
   ladder subsection in §5.
2. **Two-sided CLOB book required.** Reject a null bid or a 404 on `/book`. This
   alone removes **50% of markets 181–365 days out**, 91 of the 121 outcomes in
   the *Iran leader end-2026* event, and every stale `outcomePrices` artefact —
   RFK Jr. in the 2028 Republican event carries `outcomePrices` **0.49 with no
   bid at all**, single-handedly inflating that event's sum from 0.86 to 1.35.
3. **Computed depth within 1¢ of the touch, on the side you would take, ≥
   $10,000.** Never `liquidityNum`. **Read §2 before adopting this number: at the
   horizons this project cares about it removes everything.** Re-measured on the
   fifteen-rung ceasefire ladder: **zero of thirty sides** clear $10,000 within a
   cent, median **$533**, and the largest interval position the book will fill
   within a cent is **$463**.
4. ~~**Relative spread `(ask−bid)/mid` ≤ 10%.**~~ ***REFUTED — delete this
   filter.*** The premise is still correct: absolute spread is useless here, the
   median being **0.1¢** while the median *relative* spread on long-dated political
   markets is **17–22%** and 8.7% on the flagship Taiwan-2027 market. The
   conclusion is wrong, and not merely null — it inverts (*measured*, on Kalshi,
   the only venue whose closed corpus retains a spread worth testing). At 30 days
   and beyond, `median_rel_spread ≤ 0.10` moves the standardised bias from **+2.8pp
   to −12.1pp** — |bias| **9.4pp worse** — and the standardised Brier from **0.101
   to 0.182**, keeping 23% of markets; ≤0.05 gives −24.7pp on 8.4%; **≤0.50, the
   loose direction, is the only one that helps** (+2.7pp better, keeps 65%). The
   mechanism is arithmetic: relative spread is `spread / mid`, so tightness selects
   **expensive** contracts, which are the contracts this corpus prices too low. Its
   rank correlation with the price is **−0.646**, and when the price
   post-stratification is doubled from five strata to ten its quintile ordering
   collapses from ρ +0.60 to **ρ −0.10** — a real effect does not evaporate when you
   look more carefully at the thing it was confounded with. **The honest verdict is
   the operational one**: relative spread is so tightly coupled to the price level
   that it cannot be evaluated independently of what it selects for, and every
   threshold in the recommended direction makes calibration worse. A field with
   those two properties does not belong in a gate.
5. **Exclusive-set coherence: `Σ mid` within ±5% of `exp(−rτ)`.** The strongest
   single quality test — it catches non-exhaustive candidate fields (Nobel at
   0.606), stale mids (VP Nominee at 1.199) and broken books in one shot. On 255
   exclusive political events the median sum is 0.994 at 31–180 days, but only
   **45% are within ±2% of 1.0**, and beyond 365 days **61% are more than 5%
   away**.
6. **Read the resolution text, not the title.** Require a named source or an
   explicit "consensus of credible reporting" standard plus a duration test, and
   record that the market resolves on *reported* fact. Treat an event with an
   open `umaResolutionStatuses` dispute as having no usable price.
7. **Correct before use, and in this order** (*revised — the original order was
   backwards*). First **subtract the measured horizon bias**, which is the largest
   term by an order of magnitude and the only one this stack has measured on its own
   data: −0.4pp inside a day, +3.0pp at 7–30 days, +5.6pp at 30–90 days, +8.3pp at
   180–365 days, +9.0pp at 1–2 years, and on Polymarket geopolitics past 180 days
   **+14.0pp**. Then, if the rungs of a ladder are to be **differenced**, apply
   `p̂ = p / exp(−rτ)` with `r` from the Treasury curve, **only where
   `holdingRewardsEnabled` is false** — mandatory there because rungs settling at
   different dates otherwise mix the discount gradient into the interval mass and
   can manufacture a negative one out of a coherent ladder. A longshot haircut
   below ~10¢ comes **last and probably not at all**: it is worth 0.2–1.4¢, the
   published magnitude is grouping-dependent (equal-weighted, longshots lose
   6.3¢/$; grouped by parent event they *gain* 4.1¢/$), and on Polymarket's
   geopolitics subset the low-end bias is absent and inverts by 10–25¢. **Nothing
   in this list makes a long-dated price informative** — at 1–2 years, Brier skill
   is +0.106 against a climatological baseline, so what subtraction buys is a price
   that is unbiased and still nearly uninformative.
8. **A floor on whether anyone traded it, which is the one filter measured to
   work.** Polymarket `volume_num ≥ $1,000,000` (keeps 14% past 30 days,
   standardised bias +0.1pp from +7.5pp) or `≥ $100,000` (41%, +2.9pp); Kalshi
   `peak_open_interest ≥ $10,000` (56%, +0.5pp from +2.8pp) or `traded_frac ≥ 0.4`
   (42%, +0.4pp); on either venue a floor on median absolute daily move is the same
   information (Polymarket `≥ 0.002`, about its median, keeps 49% at +5.0pp). Three
   warnings, all measured. These are **in-sample thresholds on a settled corpus**
   whose quintile boundaries were chosen by the data, so carry the *shape* — a floor
   helps, a ceiling does not, the floor can be loose, volume and open interest are
   near-interchangeable — and re-derive the cut. **The standardised Brier gets
   worse as every one of them tightens** (Polymarket 0.0974 → 0.1255 at the $1M
   floor): the filters remove the dead 2¢ markets that were nearly always right in
   absolute terms, leaving a population that is unbiased but no more accurate. And
   every one of them removes more than half the universe at range — the same wall
   §1.3 hits from the depth side.

---

## 2. What it can answer today, and what it cannot

### The census

Measured by keyset walk and cross-checked against `/events/pagination`, which is
the only source of exact totals (*and which returns a nonsense `totalResults: 2`
if called with no filter at all*).

| Filter | Events | Note |
| --- | --- | --- |
| `closed=true` (ever) | **1,046,429** | sports and crypto dailies |
| `closed=false` (open now) | **18,939** | 212,709 embedded markets; **median liquidity across all open markets is $7** |
| `tag_slug=geopolitics` (ever) | 2,552 | of which **2,112 closed** — the calibration corpus |
| `tag_slug=geopolitics&closed=false` | **440** | the clean corpus: 61% of its markets clear $10k volume |
| `tag_slug=politics` / `&closed=false` | 10,262 / 2,470 | |
| `tag_slug=elections` / `&closed=false` | 3,142 / 1,753 | 94% per-candidate long tail |
| `midterms&closed=false` | 1,182 | 6,407 markets |
| `economy&closed=false` | 172 | 925 markets |

*Discrepancy, unresolved:* the two passes that counted markets inside the 440
open geopolitics events got **1,195** and **2,172**. The likely cause is that one
excluded `closed`/`archived`/`!active` markets and the other did not. Recount
with an explicit active filter before quoting either.

Requiring a genuine two-sided quote (`bestBid > 0`, `bestAsk < 1`, accepting
orders, order book enabled) collapses the universe to a few hundred markets:

| Category | Open markets | Two-sided | + liq ≥$10k | + vol24h ≥$1k |
| --- | --- | --- | --- | --- |
| US elections | 10,258 | 9,320 | 2,898 | **220** |
| Foreign elections | 4,539 | 3,528 | 1,664 | **163** |
| Geopolitics (broad) | 2,692 | 2,415 | 860 | **227** |
| **Conflict (strict)** | **365** | 345 | 213 | **79** |
| Macro | 1,044 | 960 | 129 | **33** |

*(Single pass. The liquidity columns inherit the `liquidityNum` defect from §1 and
are therefore upper bounds, not depth.)*

### Can answer today — and the questions are the right ones

Open markets with real books, from the geopolitics tag, with liquidity and price
as of 2026-09-26:

- **Iran.** *Will the U.S. invade Iran before 2027?* ($693k, p=0.165, $69.6M
  volume, $7.9M OI, 11 months of history); *Will the Iranian regime fall before
  2027?*; leadership-change slate; *Strait of Hormuz traffic returns to normal by
  December 31?* ($414k).
- **Russia / Ukraine.** Ceasefire front rungs ($120–172k of book); *Will Russia
  announce a new forced mobilization by October 31, 2026?* ($99k, p=0.095);
  *Russia coup attempt in 2026?*
- **NATO.** *NATO × Russia military clash by December 31, 2026?* ($161k, p=0.295).
- **China / Taiwan.** *Will China invade Taiwan by end of 2026?* ($43M volume,
  fee-free); *China coup attempt before 2027?*
- **Leader exit.** Xi ($14M), Putin, Netanyahu, Zelenskyy, Maduro/Venezuela,
  Khamenei — and *Next Prime Minister of Ethiopia?* as a 33-leg neg-risk event.
- **Elections.** US 2026 midterms (1,182 events / 6,407 markets), Brazil
  presidential, next French presidential, Presidential Election Winner 2028.

That is a real short-horizon instability panel, and nothing else in the stack is
forward-looking at all. The differentiation claim in the backlog stands.

### Cannot answer

- **The few-year horizon, in conflict.** Beyond twelve months with ≥$10k nominal
  liquidity, the conflict category holds **four markets, and all four are the
  same question** — *Russia × Ukraine ceasefire agreement by* Sep/Oct/Nov/Dec
  2027. Macro holds **two**: *US recession by end of 2027?* ($23.8k) and a 2028
  fed-funds level ($11.1k). **Nothing at all trades past 48 months.**
- **Those four rungs, on depth.** The full ladder is 15 open monthly rungs from
  Oct 2026 to Dec 2027, monotone **0.065 → 0.705**, every rung two-sided, relative
  spread narrowing 15.4% → 1.4%. It is the only multi-year conflict term structure
  on the platform and an event-level census misses it entirely. But **lifetime
  volume on the four rungs beyond a year is $818, $976, $1,643 and $3,018**, with
  depth within 1¢ of **$88 to $1,215**. A smooth monotone curve with four-figure
  lifetime volume is a market maker interpolating between the front rung and 1.0,
  not 44 traders independently pricing November 2027.
- **A standing panel of instability indicators.** The conflict category is **one
  crisis deep**: of the top 40 conflict markets by liquidity, nearly all are Iran
  — invasion, regime fall, leadership, Kharg Island, Hormuz, enriched uranium,
  plus a ~20-leg neg-risk slate of "head of state in Iran end of 2026?" priced at
  0.001–0.005, which inflates both the count and the liquidity total. When Iran
  resolves the category largely empties and refills with whatever is next. **A
  model cannot be built on a panel whose columns are re-drawn every few months.**
- **Anything long-dated at all, under a real depth floor.** Across the 40
  highest-`liquidityNum` open geopolitics markets with a *market* `endDate` beyond
  180 days: **7 of 40 have no two-sided book** (every one a Nobel Peace Prize
  candidate leg with zero bids); median bid depth within 1¢ **$199**, median ask
  **$495**; **2 of 33** two-sided markets clear $10k on the bid and **0 of 33** on
  the ask; **15 of the 40 are Nobel Peace Prize 2026 legs**. Taiwan-2027's ask
  depth is ~$4.8k. The flagship 2028 event's leading outcome (AOC) has **$8,045**
  of asks within 1¢ inside an event reporting $1.285 billion of volume. So the
  ≥$10,000 filter of §1.3 **eliminates the entire long-dated geopolitics
  universe** — the filter is self-annihilating at exactly the horizons this
  project models, and that is the real answer to "what would make it fail in
  practice."
- **Information rate at range.** Political markets with a real book, mid
  0.02–0.98, volume >$50k: median |1-day move| falls from **1.00¢ at ≤30 days to
  0.10¢ beyond 365 days**; median |1-week| from 2.50¢ to 0.45¢; and **35% of
  markets beyond a year did not move a single tick in a month** *(single pass)*.
- **Thin markets are not probabilities.** The 455k-volume
  `will-china-invade-taiwan-by-june-30-2027` shows **15 distinct prices across
  175 days**, 161 points over 175 days, largest gap 10 days. A step function, not
  a probability path.
- **US domestic instability and enforcement.** Nothing surfaced on political
  violence, protest scale or state capacity; the US domestic book is electoral and
  legislative. *Inferred from the category census rather than from a dedicated
  search — worth one pass before relying on the absence.*
- ~~**Calibration beyond one month.** No evidence exists, from any source.~~
  **ANSWERED — it exists now, and this stack made it.** See the next subsection.
  What replaces it as the horizon limit is narrower and harder: **nothing past two
  years can be measured yet**, because only seven market-bucket rows in the corpus
  sit beyond 24 months — the markets that would answer it have not resolved. That
  limit relaxes on its own and cannot be hurried.

### Calibration at range, measured

The corpus's central result, on 168,644 market-bucket rows — one observation per
market per horizon bucket, three venues pooled (*measured*):

| Horizon | Markets | Mean price | Realised | Bias | Brier | Skill | Slope |
| --- | --- | --- | --- | --- | --- | --- | --- |
| <1d | 48,150 | 0.226 | 0.230 | **−0.0039** | 0.0414 | +0.767 | 1.033 |
| 1–7d | 50,062 | 0.228 | 0.229 | −0.0006 | 0.0739 | +0.581 | 1.025 |
| 7–30d | 37,532 | 0.226 | 0.197 | +0.0296 | 0.0876 | +0.446 | 0.953 |
| 30–90d | 18,720 | 0.243 | 0.188 | +0.0559 | 0.0957 | +0.372 | 0.897 |
| 90–180d | 8,096 | 0.232 | 0.186 | +0.0461 | 0.0906 | +0.401 | 0.945 |
| 180–365d | 4,957 | 0.278 | 0.195 | +0.0827 | 0.1182 | +0.248 | 0.852 |
| **1–2y** | **1,120** | 0.265 | 0.175 | **+0.0896** | 0.1291 | **+0.106** | 0.726 |
| >2y | 7 | — | — | — | — | — | too thin to read |

By venue at 1–2 years: **Polymarket +14.6pp** (n=82 markets), **Kalshi +9.4pp**
(n=990), **IEM −10.4pp** (n=48). Bootstrap intervals clustered on markets exclude
zero from **7–30 days** on Polymarket, from **90–180 days** on Kalshi, and only at
1–2 years on IEM. Four things about this table deserve stating plainly.

**The composition objection was tested and rejected.** The obvious alternative
explanation is that long-horizon buckets hold different markets, so the realised
rate moves for reasons that have nothing to do with the price. Restricting to the
markets that **lived at least a year** — so the same markets appear in every bucket
and the realised rate is fixed by construction — leaves the gradient intact and
makes it *larger* on Polymarket: its 96 such markets run from +1.3pp inside a day
to **+14.6pp** at 1–2 years against a realised rate pinned near 0.085, and
Kalshi's 990 run +0.1pp → +9.4pp against 0.177. The same markets, on the same
questions, were further from their own eventual answers the further out you looked.

**Skill decay and bias growth are different things, and only one is a defect.** All
three venues lose skill with horizon, which is not an error — a market a year out
knows less because the world has not happened. Two of the three also become
*directionally* wrong, which is correctable by subtraction. **IEM alone loses skill
without gaining bias** out to a year.

**Polymarket's geopolitics tag looks unbiased and is the worst offender at range.**
Pooled over all horizons it is −0.8pp on 19,453 rows, better than its political
book; past 180 days it is **+14.0pp** with a skill of **−0.087** — worse than
climatology. Pooling across horizons on this venue hides exactly the thing this
project would be buying.

**And Polymarket's headline cell is the thinnest number here.** Its 1–2 year bucket
is **82 markets**; the +9 to +10 point claim rests on Kalshi's 990. IEM's sign
reversal is 48 contract-rows from a handful of election years with an interval that
excludes zero by three-tenths of a point, and the tidy explanation — IEM charges no
commission, so a fee cannot be pushing its longshots the way it can elsewhere — is
a hypothesis, not a finding. It is the most interesting thing in the corpus to test
properly and it is not tested.

Two limits on all of it, in the open. Every number is measured on markets that have
**already settled**, at daily grain, **ignoring fees**, on prices that may not have
been executable in any size — Kalshi's fee coefficient is not exposed by its API at
all, so the net version of the longshot table cannot be computed from public data.
And no venue-versus-venue verdict is supported: Kalshi is better calibrated than
Polymarket at every horizon here, and three confounds survive partial removal (its
sample is liquidity-stratified while Polymarket's is near-population; the price is a
live mid on one venue and a stale forward-filled print on the other; the two "macro"
populations are different objects). Kalshi's advantage at range survives a matched
stratum and a price-basis check, so it is **probably** real, and probably is as far
as this corpus goes.

### The published evidence, which stops at one month

Every citation below was checked against its source by the verification pass.

| Source | What it measures | Result |
| --- | --- | --- |
| **Clinton & Huang** (SocArXiv `d5yx2`, 2025-12-01) — 2,500+ political markets across IEM, Kalshi, PredictIt and Polymarket, final five weeks of 2024 | share of markets beating chance | **93% PredictIt, 78% Kalshi, 67% Polymarket** — a third of Polymarket's political markets did not beat chance, and the largest, most-cited platform was the *least* accurate. On efficiency: identical contracts diverged across exchanges and **arbitrage opportunities peaked in the final two weeks** |
| **Nam Anh Le** ([arXiv:2602.19520](https://arxiv.org/abs/2602.19520), 2026-02-23) — Kalshi + Polymarket to end-2025 | calibration slope by time-to-resolution, nine bins | **0.99 at 0–1h, 0.97 at 1–3h, 1.32 at 1 month+** — miscalibration grows monotonically with horizon. **The longest bin is "1mo+."** Politics slopes 0.93–1.83; the cross-platform replication (Polymarket 1.31 vs Kalshi 1.64) is called "a structural property of political prediction markets rather than a single-platform artefact" |
| **Gebele & Matthes** ([arXiv:2605.31431](https://arxiv.org/abs/2605.31431), 2026-05-29) | how much of that gradient is discounting | **48–88% of the apparent long-horizon miscalibration gradient is removed by a discount adjustment**, leaving a residual statistically indistinguishable from zero. The magnitude constants are ***UNSUPPORTED*** — see §1 |
| **Polymarket's own accuracy page** (marketing) | snapshots at 1mo / 1wk / 1d / 12h / 4h before resolution | **98.5% at 4 hours, 90.2% at 1 month, Brier 0.0627, 77.8% of markets resolving No** — and **no sample size and no date range**. The 4-hour figure is near-worthless for forecasting. The Brier needs a baseline: on their own 22.2% base rate a constant climatological forecast scores 0.173, making 0.0627 a **Brier skill score of ~0.64** *(a derivation by the research pass, not Polymarket's)* — genuinely good, but pooled across a population dominated by short-horizon sports and crypto, not politics at range |
| **Metaculus superforecaster tournaments** | head-to-head | *reported* as beating Polymarket on 76% of forecast days, ~18–24% worse by Brier depending on aggregation. **No peer-reviewed head-to-head on geopolitical questions specifically was found**, and the "Polymarket 96.7% / Brier 0.0838"-style figures circulating on affiliate sites are unsourced SEO content — excluded |

~~**The gap: neither Polymarket nor any study found reports calibration beyond one
month.**~~ **The gap was the argument for building the corpus, and it closed the
same day.** As of 2026-09-26 the statement is still true *of the literature* —
nothing published reaches past one month on any venue, and the longest bin in the
best cross-venue study is "1mo+". It is no longer true of this stack, and the
answer is that **the one-month shape continues and roughly doubles again by two
years**. The claim that argued this document into existence — "the evidence does
not exist, and it is cheap to create" — held: a few hundred requests was the
estimate, the whole four-venue corpus cost 4,521 requests and sixteen minutes, and
it is the one thing here that did not need a client, a table or a tool to be worth
having.

Two of the literature rows above now have a measured counterpart, and it is worth
recording which way each went. **Clinton & Huang's ordering is not testable here**
(this corpus has no PredictIt at all, for the reason given above, and its Kalshi
sample is stratified) but their *shape* — every venue at its most accurate
immediately before resolution — reproduces exactly. **Le's monotone slope rise does
not reproduce**, in either of the two estimators the corpus computes. And
**Polymarket's own accuracy page is not contradicted and not useful**: 98.5% at
four hours is consistent with a pooled skill of +0.767 inside a day, and both are
statements about a population dominated by short-horizon markets rather than about
politics at range.

### And the conflict signal is permanently offshore

**17 CFR 40.11(a)(1)** — verified verbatim from govinfo's official XML — bars a
registered entity from listing or clearing a contract "based upon an excluded
commodity, as defined in Section 1a(19)(iv) of the Act, that involves, relates
to, or references terrorism, assassination, war, gaming, or an activity that is
unlawful under any State or Federal law." *(One pass quoted this without the
excluded-commodity predicate; the predicate is material to the legal reading even
though the practical conclusion survives.)*

The CFTC's **pending** proposed rule *Prediction Markets; Public Interest
Determinations* (91 FR 35806, published 2026-06-12, comments closed 2026-07-27,
RIN 3038-AF65, **not final**) works the exclusion out on this project's exact
example, verbatim: a contract on "whether Iran initiates armed conflict in the
Strait of Hormuz… would involve war or terrorism," whereas one on "a specified
volume of crude oil transit[ing] the Strait… does not." Polymarket's live Hormuz
*traffic* market falls on the permitted side of that line.

So: **no US-regulated venue may list war contracts, now or under the proposed
rule.** `polymarket.us` is **QCX LLC d/b/a Polymarket US**, a CFTC-designated
contract market (designated 2025-07-09; the amended order vacates the bar on FCM
intermediation) and a word-boundary search of its live page returns **zero** hits
for war, invade, ceasefire, conflict, coup, assassination or terror. Its own
banner: "Trading is blocked in the United States on polymarket.com. Switch to
polymarket.us to trade."

**The one thing Polymarket offers that nothing else does is available only from a
venue a US person may read but not trade — which is fine, because the use case is
reading.** Related, and confirmed but not load-bearing here: in *KalshiEX LLC v.
Schuler / v. Orgel*, Nos. 26-3196/26-5235, the **Sixth Circuit decided and filed
2026-09-25** (panel Clay, Gibbons, Bloomekatz), holding that sports-event
contracts are not "swaps" under the CEA and vacating the February 2026 Tennessee
injunction; there is now a circuit split with the Third (*Flaherty*, 172 F.4th
220), the Ninth affirming against Kalshi (*Assad*, Aug 2026), and the Fourth
pending. It concerns **offering** contracts, not consuming public price data, and
its test — an event "intrinsically associated with a financial consequence…
(e.g., a change in interest rates)" — cuts *in favour* of macro contracts.

---

## 3. Discovery — the endpoints

**Anchor on tags with a volume floor. Search is not the spine.** Tag ids
verified: `politics` 2, `elections` 144, `geopolitics` 100265, `world` 101970,
`global-elections` 1597, `war` 79 (legacy — 0 open, 64 closed).

Three queries do the whole job, all verified:

| Job | Call |
| --- | --- |
| **Enumerate** | `GET /events/keyset?tag_slug=geopolitics&closed=false&order=volume&ascending=false&limit=100` + `after_cursor`. **5 pages for all 440.** |
| **Detect new** | `GET /events/keyset?tag_slug=…&order=createdAt&ascending=false&start_date_min=<last run>`. Returned the seven geopolitics events created in the preceding four days. |
| **Detect resolved** | `GET /events/keyset?closed=true&tag_slug=…&order=closedTime&ascending=false`, then `GET /v2/resolutions?condition=…` (20 condition ids per call) for the outcome and `was_disputed`. |

Supporting routes worth knowing: `/events/pagination` (the only exact totals),
`/events/slug/{slug}`, `/markets/keyset`, `/series/{id}` (the re-issue ladder —
returns *all* its events, open and closed; `/series-summary/slug/{slug}` returns
**no events**, do not use it for this), `/tags` (hard-capped at 100 per page),
`/public-search`, and
`/tags/slug/geopolitics/related-tags/tags`, which returns a **ready-made theatre
watchlist**: iran, lebanon, oil, ukraine, cuba, venezuela, middle-east, gaza,
israel, syria, yemen, turkey, sudan, china, thailand-cambodia, india-pakistan.
The same call on `elections` returns **zero**, so elections needs its country
axis built by hand.

Prices and outcomes:

| Route | Use |
| --- | --- |
| `POST clob/batch-prices-history` | **20 token ids per request**, response keyed by token id — the workhorse for backfill |
| `GET clob/prices-history?market={token_id}` | `interval` ∈ {max, all, 1m, 1w, 1d, 6h, 1h}, `fidelity` in minutes, `startTs`/`endTs` |
| `GET data-api/v2/prices-history?token_id=` | `interval` **or** `start`+`end` **or** `as_of` (a point-in-time read returning one observation — the primitive the series model wants), `bucket_seconds` 60–86400 |
| `GET data-api/v2/resolutions?condition=` | **the authoritative outcome**: `status`, `price`, `was_disputed`, `extended_review`, `last_update_timestamp`, `transaction_hash` |
| `GET clob/book?token_id=` | the only trustworthy depth measurement |
| `GET data-api/v2/oi?condition=` | open interest — the honest interest proxy |

### Pagination and filter traps

- **`limit` caps silently at 100.** Asked 1,000, got 100.
- **`offset` hard-stops:** `offset=20000` → HTTP 422 "use /markets/keyset for
  deeper pagination". Keyset with `next_cursor` → `after_cursor` is the only way
  through a corpus.
- **`/events` and `/markets` are deprecated** — `deprecation: true`,
  `warning: 299 - "use /events/keyset"`, `sunset: Fri, 01 May 2026`, **a sunset
  date already four months past that still serves 200s.** Use the keyset routes.
- **Unhonoured parameters do not error.** `end_date_min` on `/markets/keyset`
  changed the response byte-for-byte not at all. **Every filter must be confirmed
  by inspecting results.**
- **Gamma is CDN-cached** (`max-age=300`; tags 1800), so its embedded
  `outcomePrices` are up to five minutes stale. Never build a live price read on
  Gamma.
- **Free-text discovery is weak.** `/public-search?q=civil war` → **1** event;
  `title_search=coup` → **4**. Fine for "is there a market on X?", useless as the
  spine.
- **A curated tag registry is mandatory.** There are **≥4,000 distinct tag
  slugs** *(one pass counted 2,210 and stopped; the verification walk was still
  returning full pages at offset 4000 — take ≥4,000)* and they are dirty:
  `multi-strikes` means multiple *strike prices* and silently pulled ~1,000
  Bitcoin threshold markets into a conflict count, 1,385 before correction
  against 365 after. **This is exactly what `mcp_server/cdc_datasets.py` already
  solves** — a hand-maintained registry mapping named concepts onto a vendor's
  inconsistent vocabulary. Build the same thing and unit-test it, or the category
  counts lie. **Built and in use** (*measured*): the harvest runs off a hand-curated
  **58-slug** registry — the political and macro slugs plus the theatre list the
  `related-tags` route returns — and the closed-event census it produces sums to
  26,533 **with overlap** against 10,465 distinct events, which is the other reason
  a tag walk cannot be trusted as a count: a market carries several tags and
  nothing in the payload says which one it is "in".

---

## 4. Monitoring — cadence, archive, alerts

**Cadence: daily for series, hourly for new markets. Nothing finer serves this
horizon.**

**Daily needs no vigilance, because 12-hour history is permanent.** Verified on
five markets resolved between Feb 2024 and May 2026, back to **2024-01-26**
(2.7 years), each returning its complete path and terminating in a tick at the
settled value with `resolution_seconds: 0`. A week's outage costs nothing — it
backfills.

**Two corrections at corpus scale, and the second one is the more important.**
Both measured across the 72,838-market closed harvest:

1. **The stored path does not reliably end at the settled value.** On 55,158
   comparable paths the terminal print **agrees with the settled outcome on 40,333
   and disagrees on 14,825 — 26.9%.** The resolving move usually lands inside a
   single bucket, and a daily print misses it. The five-market check above happened
   to land on markets where it did not. **Take the label from `/v2/resolutions`,
   never from the last price**, and treat a price-derived label as a bug waiting to
   be read as a result.
2. **A quarter of closed markets have no stored path at all** —
   **17,605 of 72,838 (24.2%)** returned nothing at `fidelity=1440`, of which 16,959
   had settled to YES or NO. They are not the markets that lived an hour: their
   median life is **42 days** (p90 194, max 367) against **10 days** for the markets
   that do have a path. What they have in common is that **nobody traded them** —
   median reported volume **$0**, 88.8% at zero or absent, against a median of
   $12,939 for the markets with a path and none at zero — while the order book was
   enabled on 17,598 of them. The `p` series is a forward-filled last trade, so a
   market that never traded leaves no series to forward-fill *(this revision, single
   pass)*. The retention promise is intact; the **coverage** promise was too strong.

| Granularity | Retention | Status |
| --- | --- | --- |
| 60 s | ≥ 7 days | *documented*; v2 enforces it (returns `{"data": []}` past the floor) |
| 300 s | ≥ 60 days | *documented*, enforced |
| 1800 s | ≥ 90 days | *documented*, enforced |
| **3 h** | **not permanent** | The docs say 3h and 12h are both permanent. **Wrong for 3h:** on the live Taiwan market `bucket_seconds=10800` returns 1,306 points but the first 400 are spaced 43,200 s, so 3h exists only for roughly the trailing two months; on every resolved market tested, 10800 and 43200 returned **identical counts**. Plan for 12h. |
| **12 h** | **permanent** | verified to 2024-01-26 |

**The fidelity cliff on the legacy CLOB route, which is what made the backlog
wrong.** `interval=max` with **`fidelity` ≥ 720** returns the market's full life;
below 720 it returns only the trailing ~31 days. The flip is sharp:
`fidelity=719` → ~63–64 points over 31 days, `fidelity=720` → **814 points over
429 days**. Call `/prices-history` on a *resolved* market without a `fidelity`
and it returns `{"history": []}` with HTTP 200 — which is exactly the experiment
that produces the backlog's "markets resolve and stop" conclusion. The same
market with `fidelity=1440` returns 139 daily points. **Pin `fidelity=1440`.**
(The cliff *is* documented: "`max` returns full history at 12-hour buckets by
default… Finer widths return only the last 30 days.")

**What must be archived is the catalogue, not the prices.** This inverts the
backlog's assumption, and the reason is narrow and specific: **`description` is
editable and nothing upstream keeps the old text.** `updatedAt` moves and the
prior criteria are gone. If the intention is ever to say "the market said X while
it traded at 0.40", the *prose* is what had to be snapshotted. Keep each day's
catalogue file (~1–2 MB for the geopolitics watchlist) and criteria drift is
recoverable. Prices are permanent upstream; copying them buys nothing.

Two things that cannot be backfilled, both declined: **sub-3h detail** (7–90 day
retention) matters only for intraday crisis reaction, and a market that lives
under a day leaves exactly **2 points at 12h** — the South Korea martial-law
market (Dec 2024) is the example. Short-fuse crisis markets archive to almost
nothing. The markets that matter here live months (Iran-invasion 643 points,
Xi-out 823), so this is acceptable; it is also the only thing a live capture
process would buy, and it is not worth building.

### What an alert is

**An alert is a predicate over the watchlist refresh page — no stored history, no
state.** Every market payload already carries `oneDayPriceChange`,
`oneWeekPriceChange`, `oneMonthPriceChange`, `oneYearPriceChange` (verified −0.005
/ +0.001 / −0.01 / −0.1325 on the Xi market), plus `volume24hr`, `volume1wk`,
`spread`, `bestBid`/`bestAsk`, and `competitive` (Polymarket's own book-quality
score, 0.82 on Xi). So one page of 100 answers "what moved, what got liquid,
what is thin".

| Alert | Predicate | Cadence |
| --- | --- | --- |
| New market on a watched theatre | `order=createdAt&ascending=false`, cross-checked against the tag/country registry. **Use `createdAt`, not `updatedAt`** — `updatedAt` is batch-stamped: the five newest geopolitics events share one identical value to the microsecond, so it is not a change signal at all | hourly |
| Price move | `abs(oneDayPriceChange) > θ`, free on the refresh page | daily |
| Depth crossing | computed `/book` depth within 1¢ crossing a floor — **one extra call per watched market, and the only honest version**; `liquidityNum`, `spread` and `volume` all fail here | daily |
| About to resolve | `endDate` within N days; `/v2/resolutions` flipping `posed` → `resolved`; `closedTime` appearing; `acceptingOrders` going false | daily |

**Daily cost, measured.** A watchlist refresh across geopolitics + world +
elections at ≥$10k is ~39 requests and ~25 MB; an hourly new-market poll is 24;
one price series per market per day for a ~300-market watchlist is 300;
resolution checks ~20. **≈400 requests/day**, plus one `/book` call per watched
market for the depth floor. A full daily backfill of all 440 open geopolitics
events (≈1,700 tokens) via `batch-prices-history` at 20 tokens per call is **~85
requests**. Cheaper per refresh than the existing BLS pull, with no key and no
quota to design around.

**Why a stale catalogue is worse here than anywhere else in the stack, and why
daily is not negotiable.** A stale FRED catalogue means a *missing* series. A
stale Polymarket catalogue means a **wrong probability**: a resolved market still
shows as open, so a document-store hit returns 0.37 for something that settled at
1.0 eight months ago. It does not go quiet — it lies with a number.

---

## 5. Schema, and where it lands

### Where: a live client with a file catalogue. No Postgres.

This is the FRED/BIS/FBI pattern, and it follows from the stack's own rule.
[time-series-source.md](../meida/time-series-source.md) stores only what cannot be
fetched per request; Polymarket's history is permanent upstream at the
granularity that matters, so a `time_series_source` copy would be a cache that
goes stale for nothing. And per
[series-catalog.md](../meida/series-catalog.md), live-API sources keep **file**
catalogues feeding the document store rather than `series_catalog` rows — CDC's
live Socrata rows are the acknowledged exception, not the pattern.

**So the backlog's "Effort: high — needs its own storage strategy" inverts. It
needs no storage strategy; it needs a client, two to four tools, and a catalogue
that refreshes daily.** The one genuinely perishable thing is the resolution
prose, and that is a file snapshot, not a table.

The **calibration corpus** is the exception that proves the rule: it is an
immutable analysis dataset, so it is a one-time export under
`notebooks/polymarket/data/` — gitignored and regenerable, per convention —
loaded by yada if the analysis needs it in a database. It does not belong in
meida's Postgres.

### The hierarchy

```text
Series (optional, ~31% coverage)   id 10171 "china-invade-taiwan"
  └── Event                        id 34044  slug will-china-invade-taiwan-before-2027
        ├── tags[]                 politics, world, geopolitics, foreign-policy, china
        └── Market                 id 567621  conditionId 0xd9fb…e6d4  questionID 0xe72b…a464c
              ├── outcomes         ["Yes","No"]
              ├── clobTokenIds     ["945595…181162","907723…536237"]   ← price/book keys
              └── positionIds      ERC-1155 ids (on-chain, not needed for reads)
```

Five things, three of them catalogue and two of them series:

1. **Event** — the document unit. One `/events/keyset` page returns 100 complete
   catalogue records with `tags[]`, `description`, full `markets[]`, `liquidity`,
   `volume`, `openInterest`, `competitive`, `commentCount`, `closedTime`.
2. **Market** — one binary question, and the series carrier. **Markets carry no
   `tags`**; tags exist only on the event. That decides it: **the catalogue is
   built from events, not markets.**
3. **Outcome** — collapses into market + token side. A multi-candidate election is
   a neg-risk *event* of N binary markets, so `event → market → token` is the
   whole hierarchy. For a binary market NO = 1 − YES; **archive YES only**.
4. **Price observation** — the house contract, with one decision made below.
5. **Resolution** — `/v2/resolutions`, the authoritative record.

**Identifiers.** Stable and usable as keys: `conditionId` (0x + 64 hex),
`questionID`, the two `clobTokenIds`, and the numeric event/market/series ids.
`slug` is stable in practice but **editorial** — the Taiwan event's `title` says
"by end of 2026" while its slug says `before-2027`. **Key on `conditionId`; keep
`slug` as a label.** The join across hosts is Gamma `conditionId` ↔
`/clob-markets/{condition_id}` ↔ `/v2/resolutions?condition=`, and Gamma
`clobTokenIds[i]` ↔ CLOB `market=` ↔ v2 `token_id=`.

**Series id**, following `fbi/{offense}/{scope}/{measure}`:
**`polymarket/{market_id}/yes`**, with the slug and question in the title, and
`conditionId`, `questionID` and `clobTokenIds` in the metadata block.
`retrieval: {tool: "polymarket_price_series", token_id: "…"}`. Facets:
`{tag, event, market, side, status, resolution}`.

**`definition` comes from the vendor — a first for this stack.** Everywhere else
definitions are hand-written (`OFFENSE_NOTES`) or LLM-generated
(`db_import.descriptions`). Here the resolution criteria *are* the definition,
verbatim, and they are load-bearing: "Will the U.S. invade Iran before 2027?"
resolves on "commences a military offensive intended to establish control over
any portion of Iran" — far narrower than a strike. **Do not paraphrase it.**
`description` is present on 100/100 events and 848/848 markets, median 1,155
chars, max 5,456. **At corpus scale** (*measured*, 72,838 closed markets): median
**912** characters, p90 1,837, max 4,756, **absent on none of them**; 67.9% name a
machine-checkable source in the prose, 41.8% invoke "a consensus of credible"
sources, and only **3.2%** carry a duration test — 16.5% of the 7,928
geopolitics-tagged markets, which is where the ten-day continuity tests live.
**Longer prose does not buy calibration**: `resolution_chars` as a quality metric
is worth +1.6pp at 30–180 days and +0.8pp beyond, with ρ +0.6 then +0.3. Read that
as evidence against the *length proxy*, not against reading the text — what filter
6 asks for is a named source and a duration test, and a character count is a poor
stand-in for either.

~~The structured `resolutionSource` field a catalog would want carries nothing
usable.~~ **Corrected, and the shape of the answer matters more than the count**
(*this revision, single pass*): `resolution_source` is non-empty on **12,728 of
72,838** closed markets (**17.5%**), and takes only **117 distinct values** — 12,478
deep links and 250 site roots. The modal values say what kind of market gets one:
`x.com/elonmusk` (4,844 markets), a WTI price app (1,671),
`truthsocial.com/@realDonaldTrump` (726), `x.com/khamenei_ir` (707), `tsa.gov`
passenger volumes (617). **The field is populated where the resolution source is a
feed and empty where the contract needs a judgement** — on the geopolitics tag it is
**52 of 7,928** markets, 0.7%. So a catalogue can use it as a hint on a sixth of the
book and must fall back to parsing `description` on exactly the markets this project
cares about. `resolvedBy` is an Ethereum address (the UMA adapter), not a source.

**`is_active` finally earns its keep.** `series-catalog.md` records it as NULL on
all 13,967 rows. Polymarket is the first source with a real use for
open-vs-resolved — as a catalogue field, since this is a file catalogue. And
`_int` date mirrors matter more here than anywhere: `end_date_int` is what lets
the document store answer "what resolves in the next 90 days", which is the
query this source exists to serve.

**Four tools**, splitting discovery from fetch the way every other source does:
`polymarket_search`, `polymarket_markets` (filterable feed),
`polymarket_market` (question + criteria + resolution + OI + live price in one
call — the tool an agent actually reaches for), `polymarket_price_series`.

### The lifecycle problem, answered

A market is a **bounded** series, not a vanishing one. First observation ~creation
(**discard the first ~24 hours** — Taiwan-2027's first 12h bucket reads 0.435, the
second 0.235, then it settles at 0.225 for weeks; that is launch noise, not a
prior), last observation the settled value, plus a terminal ground-truth label.
What churns is the **catalogue**, not the observations.

**Amended in two places by the corpus, and a loader has to handle both.** The last
observation is **not** the settled value on 26.9% of paths, so the label comes from
`/v2/resolutions` and the path is one column short of self-describing. And a
**quarter of closed markets have no path at all** because nobody traded them, so
"every market leaves a series" is true of 76% of the closed political and macro book
and false of the rest — which for a corpus builder is a **selection** to state
rather than a defect to fix: what is archivable here is the traded subset, and the
untraded quarter is missing not at random. Everything measured in this document is
measured on markets that traded.

A multi-year view of one question means **splicing successive re-issues** — the
same problem as the 2021 NIBRS break and Clio-Infra's historical-border joins,
for which the house already has a convention. Polymarket gives a partial
machine-readable ladder: `series_id=10171` returns seven re-issues of "will China
invade Taiwan by X" spanning 2025–2027. But a series link covers only **31 of
100** sampled open geopolitics events, so the rest need a concept mapping built
and maintained by hand.

**And for grouping a ladder the series primitive is worse than that** (*measured*).
Of **484** cross-event ladders detected in the closed corpus, 250 were probed
against `/series`: **34** resolved to a series at all, and of those **5 matched
exactly**, 8 were supersets and 21 disagreed. The Russia–Ukraine ceasefire ladder is
typical — 18 events found by text grouping against 15 in the series, overlapping on
10. So the re-issue ladder is **not** a machine-readable object on this venue; it is
a text-grouping problem with a vendor field available as a cross-check. The corpus
groups on the question text with every date replaced by `<DATE>` and every number by
`<NUM>`, requires a by/before/prior-to marker, and treats a same-event grouping as
high confidence and a cross-event one as medium — which is the convention to carry
into a catalogue.

### The ladder is five objects, not one, and only one of them is a CDF

This is the part of the venue worth the trouble, and this document originally
treated it as a single shape. Measured across the closed corpus, **3,787 ladders
were detected, in five kinds** — and what you may do with the prices depends
entirely on which kind you are holding (*measured*):

| Kind | Ladders | Rungs | What a price is | What differencing gives |
| --- | --- | --- | --- | --- |
| `value_bucket` | 2,148 | 19,657 | interval mass, on a **neg-risk partition of a number** ("GDP growth 0.7–0.9%") | nothing — it is **already a density** |
| `cumulative` | 1,046 | 3,679 | `P(resolve ≤ T)`, overlapping "X by T" rungs | the mass in each interval — **the only true CDF** |
| `threshold` | 418 | 2,972 | `P(Y ≥ v)`, overlapping strikes — a **survival function** over level | a density over the level, the option-strike analogue |
| `recurrence_panel` | 127 | 1,686 | an independent daily binary, the same question re-asked per period | **meaningless** — read the row as a hazard-rate series |
| `exclusive_bucket` | 48 | 653 | interval mass on a neg-risk partition of **dates** | nothing; the CDF is the **running sum** |

**Two caveats outrank the coherence tests, and both are measured.**

**A by-date ladder is a CDF only for an *absorbing* event.** For a recurring one
the re-issues are **rolling** windows rather than nested ones, and differencing them
is invalid: "US bank failure by October 31 2024" settled YES while "US bank failure
before December 2024" settled NO, because the second window opened after the first
closed. **63 of 1,034** testable cumulative ladders settled non-monotonically for
exactly this reason — YES at one deadline and NO at a later one, which is
arithmetically impossible for a CDF and is not a venue failure. Check the settled
outcomes for monotonicity before treating any by-date row as a distribution.

**Attrition means the object usually does not exist.** Of the 1,046 cumulative
ladders, **568 have exactly two rungs**, 478 have three or more, and only **241 ever
had three or more rungs live at once with stored prices** — 23%, which is the ceiling
on how often a by-date ladder is a readable distribution at all. Even the flagship is
thin in this sense: the Russia–Ukraine ceasefire concept has **18 rungs across 18
separate events** spanning deadlines from 2025-02-01 to 2027-12-31 and
**$309,423,788** of volume, and **never had more than six live simultaneously** —
33% of itself.

**Where coherence does hold, it is not a confidence signal.** Across the 241
scorable ladders and 1,941 snapshots the snapshot-level monotone rate is **86.1%**,
142 ladders (58.9%) were monotone at every reading and 10 never were; the median
staleness of the stalest live rung in a snapshot is **0.53 days** and the median
terminal mass beyond the last rung is **0.725**. But monotonicity correlates more
strongly with **how many rungs you asked to line up** (Spearman −0.264) than with
liquidity (+0.178), and it is cheap to manufacture from one real rung and an
interpolation. The ceasefire ladder was monotone at **every one of eleven readings
across a year** and was wrong about the timing by most of a year: it resolved YES the
day after a reading that gave the rest of that month 2.1%. **Build a ladder for the
shape it shows — implied mass, median, hazard — and difference it as an arithmetic
check; do not read coherence as agreement.**

For a catalogue, the consequence is concrete: a ladder is a **first-class object
with a `kind`**, its rungs sorted on their own axis with any residual "Other" leg
last, and its coherence flags (`outcome_monotone` for cumulative,
`exactly_one_yes` for a partition, plus the count of settled rungs they rest on)
stored beside it. A false flag is a warning about the **grouping**, not necessarily
about the venue.

### The daily reduction, decided

12h buckets land at **00:00 and 12:00 UTC**, so "last bucket of the UTC day" is a
**midday** price labelled as a day — a lie when spliced against a FRED daily.
**Take the 00:00 UTC print as the day's value and carry `bucket_ts` as an extra
key** (the contract is `{"date": "YYYY-MM-DD", "value": "<number as string>"}`
with `extra="allow"`, exactly how WONDER rides `deaths`/`population` along).
Expose the raw 12h path through the tool via a `granularity` argument.

**And record the gotcha that makes daily reduction lossy.** Daily sampling can
miss the entire resolving move. `russia-x-ukraine-ceasefire-by-may-31-2026` has a
daily series ending **2026-05-08 00:00 at p = 0.044** and resolved **Yes**. The
minute window shows what daily threw away: 0.3625 → 0.545 at 18:46, then
0.3245 → 0.500 → 0.175 → 0.544 → 0.938 → 0.745 → 0.965 between 04:26 and 04:33,
0.9995 last trade at 19:32, `closedTime` 19:52. **A 20-hour repricing from 4% to
~100%, invisible at daily resolution.** For "what did the market think, quarter
by quarter" daily is fine. For "how fast did belief move when it broke" it is
not, and the finer data is the one thing that cannot be backfilled.

### Fields not to trust, and modelling mechanics

- **`liquidityNum`** — both-sides bid notional (§1). Ranks a zero-bid market as
  its event's most liquid.
- **`spread`** — Gamma reports 0.001 on books with no bid at all.
- **`volume` / `volumeClob`** — identical to each other, uncheckable, and 88% of a
  flagship event's is in sub-2¢ outcomes (§1). *As a level. As a floor it is the
  best filter measured — see §1.8, and do not collapse the two claims.*
- **The last point of a stored price path, as a label** — it disagrees with the
  settled outcome on **26.9%** of paths (*measured*). `/v2/resolutions` is the
  label; the path is the history.
- **`outcomePrices`** — present on only **646 of 848** markets (76%), CDN-stale up
  to five minutes, and demonstrably wrong on markets with no bid. Fields are
  **omitted, not null**, so the pydantic models need `Optional` with defaults, not
  `nullable`.
- **`endDate` is the eligibility date, not the resolution date**, and it can be
  badly wrong. The Russia/Ukraine May market had `endDate=2026-05-31` and
  `closedTime=2026-05-09 19:52`, three weeks early. Worse: **15 of 440 open
  geopolitics events are past-dated, minimum −668 days**, including two open
  Russia–Ukraine rungs carrying $120–144k of book. A "what resolves in the next 90
  days" query silently drops them.
- **Event `endDate` ≠ market `endDate`, and the census must run on markets.** The
  event-level walk of all 440 open geopolitics events gives median 96 days and p90
  **96 days** — *and an earlier top-100-by-volume sample gave median 97 / p90 140,
  which does not hold on the population.* Either way the event view **hides the
  entire 2027 ladder**, whose market `endDate`s reach 461 days. Any horizon filter
  keyed on events is wrong in both directions.
- **`closedTime` appears twice, in two formats, with two different values, in one
  response tree** — event `2026-05-09T19:35:40.504738Z` against market
  `2026-05-09 19:52:26+00`. And v2's `last_update_timestamp` (the UMA proposal) is
  a third clock. Pick one and document it.
- **`/v2/resolutions.price` is 1e18-scaled** — `1000000000000000000` = Yes, `0` =
  No, 5e17 = a 50/50 vote — and an unresolved market returns the sentinel
  `price: "69"`. v2 `was_disputed` and Gamma `umaResolutionStatuses` mean
  different things; v2 is the one with a transaction hash behind it. Gamma's
  `lastTradePrice` is actively misleading on resolved markets (1 on a *losing*
  Yes token; 0.001 contradicting its own `outcomePrices`).
- **`resolution_seconds` echoes the request, not the delivery** — 405 points
  labelled 10800 but spaced 12h. Point counts lie about granularity. Omit
  `bucket_seconds` to get the densest series that actually exists, and `as_of`
  returns the *containing bucket*, not the requested instant.
- **`startTs`/`endTs` windows are capped at exactly 15 days** (1,296,000 s); 16
  days → `invalid filters: 'startTs' and 'endTs' interval is too long`.
- **On a live market `endTs` is effectively ignored** — the API appends one extra
  point at *now* after the requested window. Clip client-side.
- **The `p` value is a price forward-filled between trades**, not a trade tape.
  Treat it as a mid, never as a volume-weighted anything. Coverage has holes even
  on the flagship: Taiwan-2027 gives 409 daily points over 429 days (95%).
- **The deep minute backfill is real but not a promise.** A 15-day window at
  `fidelity=1` on a market resolved 14 months earlier returned **21,600 points**,
  genuine rather than upsampled (changes land at arbitrary minute offsets, 03:54
  then 03:55, not on bucket boundaries) — but v2 refuses the same window at
  `bucket_seconds` 60, 300 **and** 600. It is a property of the legacy store, not
  a retention guarantee. Do not build on it.

---

## 6. The staged plan

**Stages 0 and 1 are done** — built 26 September 2026 as
`notebooks/prediction_markets/`, at four venues rather than one, and they are what
the rest of this section is now measured against. They are described as originally
scoped below, with what actually happened under each.

**Stage 0 — half a day. A notebook, zero code in `meida/`. DONE, and larger.**
`notebooks/polymarket/explore.ipynb`: walk geopolitics, print the 50
highest-volume open markets with question, criteria and 12h path, plot three
against a structural series. This buys the only question the API cannot answer —
*is there signal here for SDT?* — and the evidence is sobering in both
directions: the top open markets by volume include *Will Jesus Christ return
before 2027?* ($66M) and *Will LeBron James win the 2028 US Presidential
Election?* ($54.8M) alongside *Will the U.S. invade Iran before 2027?* ($69.6M,
$7.9M OI) and *Xi Jinping out before 2027?* ($14M). The corpus has what is
wanted; the filter is the work. **Do this before writing a client.** *What was
built instead:* four venue readers and four notebooks — `polymarket` (hosts,
identifiers, traps, wedges, a worked quality read, the ladder, discovery,
resolution), `kalshi`, `predictit_and_iem`, and `calibration` for the cross-venue
result — plus `utils/metrics.py`, a catalogue of 17 measure families each carrying
a *measures* line, a *blind to* line and a good/bad range, and a
**`NOT_COMPUTABLE` list of nine** things no amount of public data will produce
(quote age, order-flow toxicity, true unique traders, wash-trade share, market-maker
identity, the `resolutionSource` field, criteria drift, PredictIt depth, PredictIt
pre-2025 price quality). The silences are the part worth keeping.

**Stage 1 — one to two days. The labelled calibration corpus. DONE, at four
venues.** *What was built:* the census table at the top of this document, and the
calibration, longshot and metric results throughout it. The cost estimate held —
4,521 requests for Polymarket. Two things the original scoping got wrong: the
corpus is **not** geopolitics-only — it runs off a 58-tag political and macro
registry, because the geopolitics tag alone yields **198 markets at 180–365 days
and 7 beyond a year**, which cannot carry a horizon cut — and
it is **not** Polymarket-only (Kalshi's 990 markets at 1–2 years are what the
headline rests on, since Polymarket's same cell is 82). Originally scoped as:
backfill the
**2,112 closed geopolitics events** — 12h paths via `batch-prices-history` at 20
tokens a call, outcomes via `/v2/resolutions` at 20 conditions a call, a few
hundred requests total — and compute reliability curves **binned by
time-to-resolution at 1, 3, 6 and 12 months**. This is the highest-value thing on
the list and it is independent of every objection in §2: the archive is permanent,
free, keyed and quota-free. **It answers the question that decides whether any
Polymarket number ever enters a model**, and it is a real asset for evaluating
whatever forecast the SDT work eventually produces, regardless of what is decided
about ingestion. Two cheap experiments belong here (§8, items 1 and 2).

**Stage 2 — one to two days. `clients/polymarket.py` + wire models + 2 tools.**
`polymarket_markets` and `polymarket_price_series`, on the §5 client shape:
httpx, `client=` seam, `PolymarketAPIError`, three base URLs in
`environment.py`. **No key means no `.env` secret and no quota to design around**
— the BIS precedent, and `test_polymarket_client.py` should assert that no
credentials are ever sent, as BIS's does.

**Stage 3 — one day. `polymarket_market` + `polymarket_search`.** The one-call
detail tool.

**Stage 4 — one to two days. Catalogue + daily refresh.**
`notebooks/polymarket/utils/catalog.py` on the FBI model: one file per tag,
`definition` = criteria verbatim, `_int` mirrors, `status`, `resolution`,
`retrieval` block, curated tag registry with tests. Keep each day's file.
Gitignored under `notebooks/polymarket/data/`.

**Total ≈ 4–6 days**, against the backlog's "Effort: high". Stages 0 and 1 are
the decision point: **if the reliability curves at 3–12 months are bad, stop
after Stage 1 and keep the corpus.**

**The decision point fired, and the rule should be honoured.** The curves at 3–12
months are bad in the specific way that matters: **+5.6pp at 30–90 days, +4.6pp at
90–180 days, +8.3pp at 180–365 days** pooled, and +7.0pp / +6.7pp / +12.3pp on
Polymarket alone, with skill at 180–365 days of +0.15 on Polymarket and −0.05 on its
geopolitics subset. So: **keep the corpus, and do not build Stages 2–4 for the
long-horizon use case, because there is no long-horizon use case left.** What
survives is smaller and still real, and it is worth about two days rather than four
to six:

- **Stage 2 remains worth doing on its own merits** — a read-only client and two
  tools make the ≤30-day panel and the resolution prose reachable from an agent,
  and the notebook readers are already the prototype. Nothing about the bias
  argues against a tool that returns a price with its horizon attached.
- **Stage 4's daily catalogue snapshot is the one thing that gets more urgent, not
  less.** Three of the vendor's quality fields and the entire resolution prose are
  **unrecoverable after the fact** — 13.5% retention on `liquidityNum`, 13.6% on
  `competitive`, no upstream history on `description`. Every day it is not
  snapshotted is a day nobody will ever be able to validate a live filter against a
  settlement. That is also the only way open question 9 (the market *set* as a
  salience series) ever becomes answerable.
- **Stage 3 and the yada watchlist can wait**, and the watchlist shrinks to ≤30
  days when it happens.

### What not to build

1. **No Postgres.** No `time_series_source` rows, no `series_catalog` rows.
2. **No catalogue of the universe.** A 1,500-event sample is **138.6 MB on disk**
   (~92 KB/event); extrapolated, the full platform is 0.5–1.7 GB for a corpus
   where most rows are an NBA spread. Three tags cover the question.
3. **No order-book or trade ingestion** beyond the per-market depth check —
   `/books`, `/trades`, `/holders`, `/activity`, leaderboards, the RTDS
   websocket. All public, all irrelevant to a probability over months.
4. **No sub-3h capture process.** The only thing that would justify a database,
   and it serves a horizon this project does not have.
5. **No alerting inside meida.** Cheap to compute, but it is a *workflow*, and by
   the repo's own split that is yada's.
6. **No trading path and no wallet code in the repo at all.** The cheapest
   enforcement is that `clients/polymarket.py` never imports anything that can
   sign, plus the no-credentials test. The backlog is right that this separation
   is worth having from the start.
7. **No SDT driver.** It cannot sit beside Clio-Infra and DW-NOMINATE as a series.
8. **No filter on `liquidityNum`, `volume`, `outcomePrices` or `endDate`.**

---

## 7. Alternatives, and where one of them wins

All access facts below were verified by calling, in a single pass on 2026-09-26,
and not re-tested.

| Venue | API | Auth | Licence note | Verdict here |
| --- | --- | --- | --- | --- |
| **Kalshi** | `api.elections.kalshi.com/trade-api/v2` — **200 unauthenticated** | none for market data | Developer Agreement: build tools, **no redistribution of raw market data** to third parties *(reported; the agreement itself has still not been fetched, and it is the one licence constraint in this document that would bind a tool)* | **Build this first for macro — now measured, not just argued.** 14,392 series (815 Economics, 974 Financials, 2,374 Politics, 1,810 Elections); **100,233 settled markets** with a daily candle path back to **2021-09-25**, the settlement join closing **45 of 45**, and better calibration than Polymarket at every horizon |
| **PredictIt** | `predictit.org/api/marketdata/all/` — **200**, 418 KB | none | check ToS | ~~Cheap complement~~ ***REFUTED as a data source.*** **197 markets, all political**, all **Open** — and **zero labelled observations**: the chart endpoint serves seven days whatever timespan is asked for and only the first six contracts of a market. A snapshot venue you must record yourself, from the day you start |
| **Metaculus** | `/api/posts/` — **403, "The API is only available to authenticated users"** | **X-API-Key** | ToS restricts automated access except through the API | Judgemental forecasts, often *longer-dated* than Polymarket. Worth it for horizon; needs a key |
| **Manifold** | `api.manifold.markets/v0/` — **200** | none | permissive | **Play money.** The first market returned was "Who FUNNIER: razib khan or basedbeffjezos" |
| **Iowa Electronic Markets** | none | — | academic | **3 markets**, but genuine downloadable history **1988–present**. Best long archive, useless for monitoring — and **promoted by the corpus**: the only venue here with **no trading commission at all**, so a bias measured on it is a property of traders rather than of a fee schedule. It is also the only venue that loses skill *without* gaining bias out to a year, and the only one whose long-horizon bias is **negative** |
| **Good Judgment Open** | none found | — | — | No programmatic access |

**Kalshi beats Polymarket for macro decisively, and the reason is architectural
rather than a coverage count.** Kalshi's `settlement_sources` name the official
statistic: `KXRECSSNBER` (recession), `KXPCECORE`, `TERMINALRATE`, `KXU3MAX`,
`KXCPIYOY`, `KXFOMCDISSENTCOUNT`, plus foreign central banks — settling against
**BLS, FRED, the Federal Reserve, EIA, World Bank and IMF**, with 207 series
matching headline-macro terms. **Those are the same series meida already
ingests**, so a Kalshi contract joins an existing series *on its own settlement
source*, and resolution is arithmetic rather than "a consensus of credible
reporting". Against that, Polymarket's macro is **33 usable markets** and its
`recession` tag carries **one** event. Kalshi is also the CFTC-regulated venue,
so the read/trade distinction never has to be argued, and its `/series` payload
carries `contract_terms_url` PDFs — better provenance than prose.

**The join was worked end to end, and it closes — but on the agency, not on the
series** (*measured*). `KXCPIYOY` pays on "the one-decimal-place value reported by
the Bureau of Labor Statistics" for the twelve-month change in CPI-U, and the rule
text **never says whether the index is seasonally adjusted**. Forty-six settled
monthly events answer what the text does not: **BLS's own published twelve-month
change reproduces 45 of 45 checkable settlements** to one decimal, FRED's
not-seasonally-adjusted `CPIAUCNS` reproduces **45 of 45** by arithmetic from the
raw index, and the seasonally adjusted `CPIAUCSL` reproduces **33 of 45 (73%)** —
wrong by a tenth or two on a quarter of the months, which is the size of a seasonal
factor. So the contract reads `CUUR0000SA0`, and that was knowable only from the
settled history. **The lesson generalises past CPI: `settlement_sources` names the
agency, and the series has to be pinned by agreement over settled history.** It is
also unaudited metadata — `KXPAYROLLS`, which settles on the Employment Situation
release, points at the **PPI** news release. Key on the agency, pin the series, treat
the URL as a hint.

**And October 2025 is where the join goes silent, which is the boundary of the
thesis rather than a footnote.** The October 2025 CPI-U **was never published** — the
federal shutdown stopped collection, BLS returns the month with an empty value and
FRED returns `.`. That is exactly the case the contract's `rules_secondary` is
written for, and the extension is visible in the record: the event's
`expiration_time` was pushed to 2026-02-12. **It did not wait.** `KXCPIYOY-25OCT`
closed on its scheduled release day, 13 November 2025, and settled nine days later on
**3.3** with all eight listed rungs resolving Yes — and 3.3 does not sit between the
months either side (September 3.0, November 2.7), so it is not an interpolation.
**What it settled on is recoverable from none of these three APIs**; the filed
contract-terms PDF governs and the wire does not say. One event in forty-six, on the
best-provenance contract on the venue, and the cause is a shutdown, which is not a
rare event in this series' future. **Resolution is arithmetic when the print exists.**

**Two Kalshi mechanics worth carrying into a client, both measured.** History is on
a **separate historical route** that serves settled markets at every granularity —
`period_interval` accepts exactly **1, 60 and 1440** minutes and nothing else, at
most 5,000 candles a call — which is the opposite of what the live route alone
suggests, and the same class of mis-test as Polymarket's `fidelity` cliff. And the
**last one-minute candle of every settled market reads bid 0.00, ask 1.00 and
therefore a mid of 0.50** — the empty book after the close, not a forecast of a coin
flip. Anything reading a terminal quote off the final minute candle will read 0.5 on
every settled market on the venue. The daily candles do not show it, which is why the
corpus is built at 1440.

**Kalshi's horizon exists and its price does not, which is the same wall from the
other side.** It formally lists inflation to **December 2036**, beating every
Polymarket horizon; that ladder is thirteen rungs with **five monotonicity violations
on mids**, spreads from **21 to 97 cents**, and **1,660 contracts of lifetime volume
across all of them**. At ten years the collateral discount is worth more than most of
those quotes are wide.

**Kalshi is useless for conflict, and not by accident.** Searching all 14,392
series for conflict terms yields 444 hits that are almost entirely false
positives ("Critics Choice", sports "strikes"). The genuine items are policy and
diplomacy — `KXSANCTIONRUSSIA`, `KXUSAIRANAGREEMENT`, `KXTRUMPVISITISRAEL`; its
"World" category (143 series) is weather, reverse repo and papal conclaves. §2
explains why: 17 CFR 40.11(a)(1) forbids it. **Confirmed at corpus scale**
(*measured*): the absence was re-established by searching **105,205 contract
texts**, not a series list. The consequence of a war is listable; the war is not.

**So the split is clean, with one line of it redrawn.** Macro forward probabilities →
Kalshi. US elections → **Kalshi**; ~~or PredictIt~~ — PredictIt can hold a live
snapshot and nothing else, so it is a venue to *record*, not to read. Long history
for calibration method development → IEM, and more emphatically than before: it is
the only commission-free venue in the study, which makes it the only place a
measured bias is a statement about traders. Conflict and leader-exit → Polymarket,
offshore, read-only, or nowhere.

**What PredictIt's absence costs, precisely.** It is the venue the literature leans
on hardest — Clinton & Huang put it **first of four** on 2024 political markets at
93% beating chance against Polymarket's 67% — and it is the one venue that cannot
contribute a single labelled row to a corpus. Two further reasons to distrust the
transfer of that result, both recorded rather than argued: the 2024 data comes from
the **capped** regime, and when the CFTC removed the 5,000-trader-per-contract limit
on **14 July 2025** it recorded the academic community's own complaint that the cap
"can create distortions in the data generated by the Market, as new traders are not
allowed to enter some popular contracts, which then become illiquid and are not able
to trade at market prices" — so the contracts an accuracy study weights most heavily
are the ones most likely to have been capped, and the binding was never published
(hence `NOT_COMPUTABLE["predictit_pre_2025_price_quality"]`). And its fee is on
**gross profits**, which pushes the same way as longshot bias on the same contracts,
so a bias measured there would be partly a measurement of its fee schedule.

---

## 8. Open questions

Ten questions were open when this document was written. **Two are answered, one is
answered as permanently unanswerable, and six new ones arrived with the corpus.**

| # | Question | State, 26 Sep 2026 | What would settle it |
| --- | --- | --- | --- |
| 1 | **Do the long rungs carry information, or only follow the front rung?** | **Open, and narrowed to unanswerable from public data.** `market_maker_identity` is in `NOT_COMPUTABLE`: whether a smooth ladder is 44 traders or one maker interpolating cannot be established from any public field. What *is* measured says the shape is not evidence about the world — the implied monthly hazard swings fivefold with nothing in the war to match it, two of fifteen interval masses bound negative at the quoted prices, and the largest interval position the book will fill within a cent is **$463** | Cross-rung lead–lag on the archived 12h paths would still be worth running as a *descriptive* test, on the understanding that neither answer identifies who is quoting |
| 2 | **Is Polymarket calibrated on political-instability questions at 3–12 months?** | **ANSWERED — no, and it degrades monotonically.** +7.0pp at 30–90 days, +6.7pp at 90–180, +12.3pp at 180–365, +14.6pp at 1–2 years, and its geopolitics subset is +14.0pp past 180 days at negative skill. The geopolitics cut at 180–365 days is 198 markets with a logit-slope interval of (0.10, 1.53) — too wide to say more than the sign | Nothing further; the limit is now calendar time, not effort. Re-run when markets past two years settle |
| 3 | **Is `conditionId` stable across a question or `description` edit?** | **Open, untouched.** The corpus keys on it and nothing in a closed-market harvest can test re-minting | Snapshot `(conditionId, sha256(description))` daily on the open geopolitics set and watch for a description change |
| 4 | **What is the true settlement-discount magnitude?** | **Open, and now lower-stakes but wrongly framed before.** Still ***UNSUPPORTED*** in the citation, still unnarrowable inside [0.55%, 4.95%] by direct measurement. What changed is that the discount is **worth about a point of a nine-point gap and points the wrong way** to explain it | Read the body of [arXiv:2605.31431](https://arxiv.org/abs/2605.31431) — and read it for *which* miscalibration it corrects, not for the constant |
| 5 | **Does `resolutionSource` ever carry anything?** | **ANSWERED — yes, on 17.5% of closed markets, 117 distinct values, and almost never in geopolitics (52 of 7,928).** It is populated where the source is a feed *(this revision, single pass)* | Nothing; re-derive the count if a catalogue is going to key on it |
| 6 | **How many *active* markets are in the 440 open geopolitics events?** | **Open.** The corpus is `closed=true` only, so the 1,195-against-2,172 *discrepancy* is untouched | Recount with an explicit `closed`/`archived`/`active` filter and state the filter |
| 7 | **Does the geopolitics fee exemption persist?** | **Open, and untestable retrospectively.** `fee_bearing` takes one value across the whole closed corpus, so it cannot be evaluated as a quality field at all; the fifteen live ceasefire rungs all report `feeType: None`, `feesEnabled: False` on 2026-09-26 | Re-read `feeSchedule` per market on every catalogue refresh and store it — the only way this becomes a series |
| 8 | **Are there markets on US domestic instability** — political violence, protest scale, state capacity? | **Open.** The 58-tag harvest registry contains no such concept, which is weak evidence of absence rather than a search | One targeted `/public-search` and tag sweep |
| 9 | **Is the market *set* itself the better SDT variable?** | **Open, and strengthened.** The venue serves the object directly: **127 `recurrence_panel` ladders / 1,686 rungs** are the same question re-asked per period, which is a hazard-rate series and a conflict-intensity series in its own right rather than a distribution | Still needs archived daily catalogues for a history — the argument for starting the Stage 4 snapshot early, now with a named object to count |
| 10 | **Can reported volume ever be cleaned?** | **Open, and largely moot.** Not from the API, and it does not matter: volume works as a **floor** without being interpretable as a level | Trade-level on-chain Polygon data. Out of scope |
| 11 | **Does the untraded quarter bias the corpus?** **17,605 of 72,838** closed markets (24.2%) left no price path because nobody traded them, and they lived a median 42 days | **New, and the largest unqualified caveat on every measurement here** — all of it is conditional on a market having traded | Their settled outcomes *are* retrievable, so the base rate of the untraded set is computable without a price: compare it against the traded set's, and the selection's direction becomes visible |
| 12 | **Is Kalshi's calibration advantage real or an artefact?** It is better at every horizon, with three confounds: a liquidity-stratified sample against a near-population one, a live mid against a stale forward-filled print, and two different "macro" populations | **New.** The advantage survives a matched stratum and a price-basis check, so it is *probably* real | An unstratified Kalshi pull, which is ~100,000 candle paths rather than 4,393 |
| 13 | **Do the metric floors transfer?** Every threshold in §1.8 is in-sample on a settled corpus whose quintile boundaries the data chose | **New, and it blocks using any exact cut** | Re-derive on a held-out period — the corpus already spans 2021–2026, so a temporal split costs nothing but the rerun |
| 14 | **What did `KXCPIYOY-25OCT` settle on?** The October 2025 CPI-U was never published and the contract settled on 3.3 anyway | **New.** Recoverable from no API; the filed contract-terms PDF governs | Read the `contract_terms_url` PDF. It is also the test case for what a shutdown does to any macro join |
| 15 | **Does Kalshi's Developer Agreement permit a stored corpus and an MCP tool?** The no-redistribution clause is *reported*, from a venue table, and the agreement has not been read | **New, and it gates Kalshi Stage 2** — "may we store this" is answered by the gitignore convention; "may a model hand it onward" is not | Read the agreement before the first `clients/kalshi.py` line |
| 16 | **Is IEM's negative long-horizon bias real?** −10.4pp on 48 contract-rows, interval excluding zero by three-tenths of a point, on a commission-free venue | **New, and the most interesting thing in the corpus** | IEM's own archive runs to 1988 and only 34 winner-take-all markets were used; 12 of 44 pre-1996 markets were not recovered under any naming variant tried |

---

## Sources

**The corpus, and everything marked *measured*** — in meida, all gitignored and
regenerable: `notebooks/prediction_markets/utils/polymarket.py` (2,091 lines),
`kalshi.py`, `kalshi_harvest.py`, `predictit.py`, `iem.py`, `corpus.py`,
`corpus_iem.py`, `metrics.py` (the 17-family catalogue and `NOT_COMPUTABLE`);
notebooks `calibration.ipynb` (the cross-venue result), `polymarket.ipynb`,
`kalshi.ipynb`, `predictit_and_iem.ipynb`; exports under
`notebooks/prediction_markets/data/` — `polymarket_manifest.json` is the one to read
first, since it records the census, the attrition, the ladder counts, the network
cost and a `skipped_and_why` block naming what was deliberately left out.

Polymarket docs: [llms.txt index](https://docs.polymarket.com/llms.txt) ·
[prices and order books](https://docs.polymarket.com/market-data/prices-order-books.md) ·
[discover markets](https://docs.polymarket.com/market-data/discover-markets.md) ·
[resolution](https://docs.polymarket.com/concepts/resolution.md) ·
[pUSD](https://docs.polymarket.com/concepts/pusd.md) ·
[fees](https://docs.polymarket.com/trading/fees.md) ·
[SDKs and APIs](https://docs.polymarket.com/getting-started/sdks-apis.md) ·
[builder tiers](https://docs.polymarket.com/programs/builders/tiers.md) ·
[Perps rate limits](https://docs.polymarket.com/api-reference/perps/rate-limits.md) ·
[data API v1→v2 migration](https://docs.polymarket.com/migrate/data-api-v1-to-v2.md) ·
[holding rewards](https://help.polymarket.com/en/articles/13364459-holding-rewards) ·
[accuracy page](https://polymarket.com/accuracy) ·
[polymarket.us](https://polymarket.us/)

Calibration literature: [Cardozo & Rivero-Wildemauwe, *The Favorite-Longshot Bias in Prediction Markets: Evidence from Polymarket*, arXiv:2609.12878](https://arxiv.org/abs/2609.12878) ·
[Nam Anh Le, *Decomposing Crowd Wisdom: Domain-Specific Calibration Dynamics in Prediction Markets*, arXiv:2602.19520](https://arxiv.org/abs/2602.19520) ·
[Gebele & Matthes, *When Certainty Is Not Worth It*, arXiv:2605.31431](https://arxiv.org/abs/2605.31431) ·
[Clinton & Huang, *Prediction Markets? The Accuracy and Efficiency of $2.4 Billion in the 2024 Presidential Election*, SocArXiv](https://doi.org/10.31235/osf.io/d5yx2)

Regulatory and litigation:
[17 CFR 40.11](https://www.ecfr.gov/current/title-17/chapter-I/part-40/section-40.11) ·
[CFTC, *Prediction Markets; Public Interest Determinations*, 91 FR 35806 (2026-06-12)](https://www.federalregister.gov/documents/2026/06/12/2026-11854/prediction-markets-public-interest-determinations) ·
[CFTC Amended Order of Designation, QCX LLC d/b/a Polymarket US](https://www.cftc.gov/media/12806/Polymarket%20US%20Amended%20Order%20of%20Designation/download) ·
[*KalshiEX LLC v. Schuler / v. Orgel*, 6th Cir., Nos. 26-3196/26-5235 (2026-09-25)](https://www.opn.ca6.uscourts.gov/opinions.pdf/26a0272p-06.pdf) ·
[CRS, *Prediction Markets: Policy Issues for Congress*](https://www.congress.gov/crs-product/IF13187)

Resolution controversies (*reported*, not independently checked):
[Ukraine mineral deal](https://www.coindesk.com/markets/2025/03/27/polymarket-uma-communities-lock-horns-after-usd7m-ukraine-bet-resolves) ·
[Zelenskyy's suit](https://decrypt.co/329210/polymarket-rules-no-237m-bet-zelenskyys) ·
[US–Iran peace deal](https://www.calcalistech.com/ctechnews/article/wgc50wv09) ·
[the French whale](https://www.cnbc.com/2024/10/24/polymarket-trump-french-election-bet.html) ·
[wash-trading estimates](https://inca.digital/news/fortune-polymarket/)

Alternatives: [Kalshi API docs](https://docs.kalshi.com/welcome) ·
[Metaculus API changes](https://www.metaculus.com/notebooks/42554/changes-to-the-metaculus-api/) ·
[Iowa Electronic Markets](https://iemweb.biz.uiowa.edu/) ·
[Treasury par yield curve](https://home.treasury.gov/resource-center/data-chart-center/interest-rates/)

Stack references: [architecture.md](../meida/architecture.md) ·
[series-catalog.md](../meida/series-catalog.md) ·
[time-series-source.md](../meida/time-series-source.md) ·
[FBI reference](../meida/api/fbi.md) ·
[structural-demographic-theory.md](structural-demographic-theory.md) ·
[data-sources-backlog.md](data-sources-backlog.md)
