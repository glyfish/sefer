# ETF / Fund Data Store

A ChromaDB catalog of exchange-traded funds and mutual funds — one document per fund, used both
for semantic search ("what VanEck fixed income ETFs are there?") and as the **metadata catalog**
that enriches cached Tiingo price series.

See [architecture.md](architecture.md) for how this fits the wider system.

---

## Identity

| | |
| --- | --- |
| Engine | ChromaDB (persistent) |
| Path | `.db/etf` |
| Collection | `etf-info` |
| Documents | ~36,500 (one per fund, unchunked) |
| Embeddings | `OpenAIEmbeddings` (`embedding_ctx_length=2000`, `chunk_size=100`) |
| Loader | `apps/agentic/core/document_loaders/etf/finance_database_loader.py` → `FinanceDatabaseLoader` |
| Upstream source | the [`financedatabase`](https://pypi.org/project/financedatabase/) package (`fd.ETFs().select(...)`) — a static dataset, not a live API |

---

## What a document looks like

Page content is a small markdown fact sheet, so semantic search matches on fund name, family, and
asset class together:

```markdown
# WISDOMTREE EURO HGD EQ.FD
- **Ticker:** 003D.BE
- **Fund Family:** WisdomTree Asset Management
- **Asset Class:** Financials
- ...
```

---

## Metadata schema

| Field | Example | Notes |
| --- | --- | --- |
| `ticker` | `IHY`, `003D.BE` | Primary key for lookups. Non-US listings carry an exchange suffix. |
| `name` | `VANECK INTERNATIONAL HIGH YIELD BOND ETF` | Fund name. |
| `family` | `VanEck Asset Management` | Fund family. **Filterable** — the extractor normalizes colloquial names ("VanEck" → "VanEck Asset Management"). |
| `category_group` | `Fixed Income` | Broad asset class. **Filterable**, closed vocabulary. |
| `category` | `Corporate Bonds` | Specific category. **Filterable**, closed vocabulary. |
| `exchange` | `PCX`, `BER` | Exchange code. **Filterable**. |
| `currency` | `USD` | Trading currency. |
| `isin` | | International securities id, where present. |

The four **filterable** fields are exactly those lifted into the time-series cache (below) and
enumerated in `ETFFilters`. Exchange codes are documented in
`apps/agentic/core/document_loaders/etf/exchange_metadata.py`; the US set is
`ASE, NCM, NIM, NMS, NYQ, PCX, PNK`.

---

## Loading and refresh

Driven by the `DocumentLoaderAgent`, so it is reachable conversationally:

| Tool | Behavior |
| --- | --- |
| `load_etf_data` | Load funds from `financedatabase` into the collection. |
| `reload_etf_data` | `delete_all()` then reload — a full rebuild. |

`delete_all()` resets the collection and reports the number of documents removed. Because the
upstream is a static package dataset, refresh is driven by upgrading `financedatabase`, not by
polling an API.

The notebook `notebooks/documents/etf_document_loader.ipynb` covers the same path interactively.

---

## How it is queried

**Agent** — `ETFDataInfoAgent` (`apps/agentic/agents/document/etf_data_info_agent.py`), a
`ChromaRAGAgent`, reached via the DocumentAgent delegate
`delegate_to_etf_data_info_search_agent`.

**Filters** — `extract_etf_filters()` parses the user's request into `ETFFilters`
(`family`, `category_group`, `category`, `exchange`) and `etf_filters_to_where()` converts it to a
Chroma `where` dict. A single value becomes equality; several become `$in`; multiple fields are
combined with `$and`.

```text
"VanEck fixed income ETFs"
  → {"$and": [{"family": "VanEck Asset Management"},
              {"category_group": "Fixed Income"}]}
```

The vocabularies are described in prose inside the `ETFFilters` field descriptions, so the model
maps colloquial language onto the exact stored strings ("bonds" → `Fixed Income`, "tech" →
`Information Technology`).

---

## Relationship to the time-series cache

This store is the **catalog for the `tiingo` cache source**. Note the deliberate asymmetry: the
*price data* comes from Tiingo, but the *descriptive metadata* comes from this ETF catalog. In
`series_metadata.py`:

```python
"tiingo": {"loader": FinanceDatabaseLoader,
           "key": "ticker",
           "fields": ("family", "category_group", "category", "exchange")}
```

When a Tiingo series is fetched, `catalog_metadata("tiingo", ticker)` looks the ticker up here and
writes those four fields into the cache row's `metadata` under the `tiingo` key as single-element
lists. That is what makes a **cached series** and a **saved report** filterable with the same
`extract_etf_filters()` used for document search — one vocabulary, three query surfaces.

A missing catalog row is not an error: enrichment is best-effort and yields `{}`.

---

## Operational notes

- The collection is large (~36.5k docs) but **unchunked** — one document per fund keeps ticker
  lookups exact and cheap.
- Ticker is not globally unique across venues; non-US listings are suffixed (`003D.BE`).
  `catalog_metadata` matches on exact `ticker`.
- Adding a filterable field means: include it in `_build_documents` metadata, add it to
  `ETFFilters` + `etf_filters_to_where`, and add it to `_CATALOG["tiingo"]["fields"]` and
  `_CATALOG_FIELDS["tiingo"]` so it reaches the relational store and its filters.
