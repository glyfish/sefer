# Known Issues

A running log of known problems and deferred decisions across the gly.fish repos —
enough context to **recreate** each and revisit later. These are rough edges and
"deal with it when it bites" items, distinct from the feature roadmap
([planning/](planning/)).

Each entry: what it is, why it's deferred, the options considered, and how to
reproduce it when we come back.

---

## FRED/BLS series overlap — duplicate twins across stores

**Status:** deferred — not worth solving yet.

**The issue.** FRED republishes BLS data, so the same statistic exists under both
a FRED ID and a BLS ID — unemployment `UNRATE` (FRED) / `LNS14000000` (BLS); CPI
`CPIAUCSL` / `CUUR0000SA0`. Each data source has its own document store, so there
is no *in-store* collision; but a request that fans across the FRED and BLS stores
returns **both twins** in the merged result.

**Why deferred.** The current workflow is human-in-the-loop — search, then the
user selects which series go in a report. The human is the disambiguator, so
seeing both twins is fine (two options to pick from). The only real risk is
**double-counting**: a user who doesn't realize the two are the same could put
both in one report and plot the statistic twice.

**Options (for when we revisit):**

- **Exclude at build** — filter FRED's catalog by `source = BLS` (a source that has
  its own store) and drop the mirrors; BLS becomes the home. Simplest store, but
  loses FRED's ALFRED vintages and its memorable IDs for those series.
- **Return both + flag** — keep both stores complete; flag the collision at
  selection ("FRED mirror of BLS") — a hint for the human now, the notification an
  agent raises once selection is automated.
- **How the agent could know twins (beyond descriptions):** (1) a provenance field
  — FRED's `source = BLS` marks a mirror; (2) an explicit `mirror_of: BLS/<id>`
  twin-map, precomputed; (3) value fingerprinting — identical observations over the
  overlap confirm the exact pair. Recipe: source-tag → fingerprint → store
  `mirror_of`, all at catalog-build time.

**To reproduce.** Once the FRED and BLS catalogs are both indexed, query across
both stores for a shared statistic (e.g. "unemployment rate") and observe both
`UNRATE` and `LNS14000000` come back; then walk it through the report-build
selection flow and see how it's handled.
