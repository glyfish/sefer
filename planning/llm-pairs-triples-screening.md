# LLM-Assisted Screening for Pairs & Triples Trading

An idea recorded for later: use an LLM as a **first-pass screen** on candidate
trading pairs and triples, pruning the search space *before* the expensive
statistical-testing (cointegration) stage. The LLM proposes economically-plausible
candidates; the statistics verify them. This is a finance application built on the
existing Tiingo price data — tangential to the current data-source work.

See [architecture.md](../meida/architecture.md) for the client pattern and
[data-sources-backlog.md](data-sources-backlog.md) for related sources (Tiingo,
LittleSis).

---

## The problem

Statistical-arbitrage strategies — pairs trading, and 3+-asset baskets — look for
groups of assets whose prices are **cointegrated** (a mean-reverting spread you can
trade). Finding them by brute force does not scale:

- **Combinatorial explosion.** N assets → N(N−1)/2 pairs and N-choose-3 triples.
  N=1,000 → ~500K pairs, ~166M triples; N=5,000 → ~12.5M pairs, ~20B triples.
- **Multiple hypothesis testing.** At 5% significance, a million blind
  cointegration tests return ~50,000 "significant" pairs by pure chance. Blind
  search *manufactures* spurious relationships (data snooping).
- **Compute.** Even setting statistics aside, you cannot run Johansen on billions
  of triples.

The fix predates LLMs: impose an **economic prior** — only test groups with a
plausible reason to co-move (same industry, shared input, supply chain). The
classic pairs literature (Gatev, Goetzmann & Rouwenhorst, 2006) and common
practice restrict candidates to related assets for exactly this reason. An LLM is
a scalable, richer way to encode that prior.

## Core principle: the LLM proposes, statistics dispose

The LLM never decides a trade. It generates *hypotheses* — candidate groups with
an economic rationale — that the cointegration test confirms or rejects.

- **LLM = recall** — find plausibly-linked assets. Good at *relational* reasoning
  over entities (sectors, competitors, supply chains), which is what it's actually
  good at, unlike numeric prediction.
- **Statistics = precision** — is the spread really cointegrated / mean-reverting?
- A bad LLM suggestion costs **compute, not money** — the test is the arbiter.

The right division of labour for a model that reasons well about relationships and
poorly about numbers.

## The scaling rule: annotate O(N), never score O(N²)

Do **not** ask the LLM to score every pair or triple — that is the same explosion.
Instead:

1. **Annotate each asset once — O(N).** The LLM emits structured attributes per
   ticker: sub-industry, business model, key input commodities, supply-chain role,
   named competitors/substitutes, geography, index membership.
2. **Generate candidates by cheap rules/similarity on the attributes.** Same
   sub-industry, shared commodity exposure, competitor pairs, supplier→customer
   links → candidate groups; only test *within* groups. Combinatorially controlled.
3. **(Optional) LLM re-rank** the reduced candidate set with an economic-rationale
   score — now operating on hundreds, not billions.
4. **Statistical stage.** Engle–Granger for pairs, **Johansen** for triples/
   baskets; estimate the mean-reversion half-life (Ornstein–Uhlenbeck); apply a
   **false-discovery-rate correction** (Benjamini–Hochberg) and **walk-forward
   out-of-sample** validation.

The LLM defines the equivalence classes; the tests run inside them.

## Metadata & enrichment

Annotation quality drives candidate quality. Source it in layers — cheapest and
most reliable first:

| Layer | For | Notes |
| --- | --- | --- |
| **Structured data** | sector/sub-industry, index membership, fundamentals | Tiingo fundamentals, SEC/EDGAR, GICS/SIC, OpenFIGI, Wikidata. Clean, cheap, **point-in-time-able**. |
| **LLM parametric** | the well-known majority | Large-caps: the model already knows sector, competitors, business model. |
| **Web retrieval (Tavily)** | the long tail + soft/relational attributes | Obscure/small-cap/foreign/new tickers, supply-chain specifics. **Retrieve-when-uncertain** gating, not blanket search. |
| **Relationship graphs** | inter-company links | **LittleSis** (ownership, board interlocks), Wikidata (competitor/subsidiary edges). Structured beats scraping the open web. |

**Why enrichment matters — the recall asymmetry.** The statistical stage catches
**false positives** (a bad candidate just fails the test — cheap) but **cannot
catch false negatives**: a pair never proposed is never tested. So enrichment's
real payoff is **recall on assets the LLM doesn't know** — the long tail, where
without grounding you silently miss real relationships. For a liquid large-cap
universe, enrichment adds little; for a broad/small-cap/international universe, it
matters.

This is where the **LittleSis** idea from the backlog converges: its
corporate-relationship graph is a natural, structured feed for the
"who's-linked-to-whom" signal pairs trading wants.

## Risks & caveats

- **Look-ahead bias (the big one).** Both the LLM's parametric knowledge (to its
  cutoff) and live web retrieval (Tavily's "today") can leak future information — a
  merger or new business line that only became true *after* the backtest window.
  Fine for **forward/live screening**; hazardous for **historical backtests**.
  Mitigate with **stable structural** attributes (sector, business model, commodity
  exposure) over event-driven ones, point-in-time structured sources, and
  validation on periods the annotation can't have seen.
- **Interpretability bias.** The screen favours economically-legible pairs and
  misses purely-statistical co-movements. But storyless pairs are also the most
  likely to be overfit and break out-of-sample — so the bias doubles as a
  **robustness filter**, arguably a feature.
- **Multiple testing still applies** to the reduced set — smaller, not zero. Keep
  the FDR correction and out-of-sample validation.
- **Don't over-engineer annotation.** Because the cointegration test is the real
  gatekeeper, annotation can be noisy; spend the enrichment budget only where it
  changes *which candidate groups form* (recall), not on perfecting precision.

## Fit with the stack

- **Tiingo** supplies both the prices (for the spread tests) and fundamentals (for
  annotation).
- **Ties to the "customize LLMs" thread.** The O(N) asset annotator is an ideal
  **distillation** target: label a few thousand tickers with a frontier model
  (Claude), then fine-tune a cheap small model to annotate the whole universe — the
  same technique explored for the Congressional-Record work, applied to finance.
- **LittleSis / Wikidata** feed the relationship layer.

## Open questions / next steps

- **Regime first:** backtest vs. forward/live — this decision drives the entire
  look-ahead treatment and metadata sourcing.
- **Prototype** the annotation schema + rule-based candidate generation on a small
  universe (e.g. one sector) and inspect the candidate groups before any testing.
- **Statistical suite:** confirm Engle–Granger / Johansen + half-life + FDR +
  walk-forward as the validation stack.
- **Tavily gating:** implement retrieve-when-confidence-is-low so it fires on the
  tail, not the whole universe.
- **Point-in-time metadata** for honest backtests — the hardest engineering piece.
