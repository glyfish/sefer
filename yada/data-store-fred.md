# FRED Metadata Data Store

A ChromaDB catalog of **FRED series metadata** — one document per series, describing what each
series measures, how often it is released, and what period it covers. It is a discovery index,
not a data store: observations are fetched separately through MCP and land in PostgreSQL.

See [architecture.md](architecture.md) for how this fits the wider system.

---

## Identity

| | |
| --- | --- |
| Engine | ChromaDB (persistent) |
| Path | `.db/fred` |
| Collection | `fred` |
| Documents | ~145,700 (one per series) |
| Embeddings | `OpenAIEmbeddings` (`embedding_ctx_length=2000`, `chunk_size=100`) |
| Loader | `apps/agentic/core/document_loaders/fred_document_loader.py` → `FREDChromaDocumentLoader` |
| Upstream source | YAML exports under `clients/fred/` produced by `clients/bin/fred.py` |

This is by far the largest catalog in the system — it is the reason a user can ask "what GDP
series are still being updated?" without calling the FRED API.

---

## What a document looks like

Markdown, titled with the series name and units so semantic search has something meaningful to
match:

```markdown
# Australian Bank Transactions: RBA Spot and Forward Transactions: Net with Dealers (AUD Millions)

## Series Information
- **Series ID:** ...
- **Frequency:** ...
- ...
```

---

## Metadata schema

| Field | Example | Notes |
| --- | --- | --- |
| `series_id` | `UNRATE`, `GGGDTPUSA188N` | FRED identifier. **Filterable**, exact match. |
| `series_title` | `Total Federal Receipts` | Human-readable title. |
| `units` | `Mil. of $`, `% of GDP` | Display units — reused for plot axes and legends. |
| `frequency` | `Monthly`, `Quarterly` | Release frequency, long form. **Filterable**. |
| `seasonal_adjustment` | `Not Seasonally Adjusted` | **Filterable**. |
| `category_id` / `category_name` | `Government Debt` | FRED category. `category_name` is **filterable**. |
| `category_path` | `Indicators > National Accounts > Government Debt` | Full classification path. |
| `leaf_name` | | Terminal category node. |
| `popularity` | `5` | FRED popularity score (0–87). **Filterable** by range. |
| `observation_start` / `observation_end` | `2006-12-29` | Coverage bounds (ISO strings). |
| `observation_start_int` / `observation_end_int` | `19831212` | **Numeric YYYYMMDD mirrors.** |
| `last_updated` / `last_updated_int` | `2008-03-03T…` / `20080303` | Last release, string + numeric mirror. |
| `filename` | | Source YAML the document came from. |

### Why the `*_int` mirrors exist

ChromaDB cannot range-compare strings — a `$gte` against `"2025-01-01"` raises at query time. So
every date is stored **twice**: the ISO string for display, and a `YYYYMMDD` integer for
comparison. All recency filtering ("series updated within the last year", "data ending after
2020") targets the `_int` fields.

The same convention carries into the PostgreSQL cache, whose `observation_*_int` values are
filtered with `jsonb_path_exists`.

---

## Loading and refresh

Two stages:

1. **Export** — `clients/bin/fred.py` walks the FRED category tree and writes YAML under
   `clients/fred/`:
   - `clients/fred/categories/` — category trees (e.g. `fred_academic_data_33060.yaml`)
   - `clients/fred/series/` — per-category series metadata

2. **Index** — `FREDChromaDocumentLoader.load_all_documents()` reads those exports (default base
   path `clients/fred/categories`) and writes documents into the collection.

`notebooks/documents/fred_chroma_query.ipynb` is the interactive query/inspection notebook.

Because indexing embeds ~145k documents, a full rebuild is expensive — treat it as an occasional
batch operation, not something to run casually.

---

## How it is queried

**Agent** — `FredDataInfoAgent` (`apps/agentic/agents/document/fred_data_info_agent.py`), a
`ChromaRAGAgent`, reached via the DocumentAgent delegate
`delegate_to_fred_data_info_search_agent`.

**Filters** — `extract_fred_filters()` parses the request into `FredFilters` and
`fred_filters_to_where()` converts it:

| Filter field | Produces |
| --- | --- |
| `category_name`, `series_id`, `frequency`, `seasonal_adjustment` | Equality |
| `popularity_op` + `popularity_value` | `{"popularity": {"$gte": 50}}` |
| `observation_end` (+ `observation_end_op`) | `{"observation_end_int": {"$gte": 20250101}}` |
| `last_updated` (+ `last_updated_op`) | `{"last_updated_int": {"$gte": …}}` |

Relative dates ("within a year of today") are resolved to absolute ISO dates by the extractor,
then converted to `YYYYMMDD` ints. A missing comparison operator on a recency phrase defaults to
`$gte`, since recency phrasing is overwhelmingly "on or after".

A request naming no filterable attribute yields `None` — a plain semantic search. That is correct
behavior, not a failure: bare "GDP" should return GDP series across all countries.

---

## Relationship to the time-series cache

This store is the catalog for the `fred` cache source (`series_metadata.py`):

```python
"fred": {"loader": FREDChromaDocumentLoader,
         "key": "series_id",
         "fields": ("category_name", "category_path", "seasonal_adjustment", "frequency")}
```

On fetch, `catalog_metadata("fred", series_id)` copies those four fields into the cache row's
`metadata` under the `fred` key, so cached series and saved reports are filterable with the same
`extract_fred_filters()` used here.

Note the store also supplies `frequency` in **long form** (`Monthly`), which is what the cache's
metadata and its filters use — and what drives the per-series TTL.

---

## Operational notes

- **Vocabulary is closed and verbose.** `FredFilters` enumerates valid `category_name` and
  `frequency` strings in its field descriptions so the model maps onto exactly what is stored;
  a near-miss silently matches nothing.
- **Never range-filter a date string** — use the `_int` mirror.
- The catalog's `observation_end` reflects **when the catalog was exported**, so it can lag
  reality. Recency filtering over *cached* series therefore uses the cache's own
  `observation_end_int`, recorded at fetch time, rather than this store's value.
