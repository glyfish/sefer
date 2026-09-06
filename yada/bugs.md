# yada — Bugs

Known defects in the yada codebase, with enough detail to confirm and fix each.
Distinct from [known-issues.md](../known-issues.md) (cross-repo rough edges and
deferred decisions) and from the per-store references in this directory.

---

## FRED document store contains 19,810 duplicate documents

**Status:** open — confirmed by measurement, not yet fixed.

**The issue.** `.db/fred/chroma.sqlite3` holds **145,679 documents** covering only
**125,869** distinct `(series_id, category_id)` pairs. **19,810 documents are exact
repeats.** 9,905 pairs are affected and each appears exactly **three times**, so the
ingest was run three times over part of the corpus.

Not every extra document is a bug. A FRED series legitimately belongs to several
categories, and the loader deliberately emits one document per *(series, category)*
join so each carries its own category breadcrumb — that accounts for
125,869 − 123,119 = **2,750 correct extras** over the 123,119 distinct series. The
remaining 19,810 are true duplication.

Measured with:

```python
import sqlite3, collections

con = sqlite3.connect("file:.db/fred/chroma.sqlite3?mode=ro", uri=True)
rows = con.execute("""
    SELECT id, key, COALESCE(string_value, CAST(int_value AS TEXT))
    FROM embedding_metadata WHERE key IN ('series_id', 'category_id')
""").fetchall()

doc = collections.defaultdict(dict)
for doc_id, key, value in rows:
    doc[doc_id][key] = value

pairs = {(d["series_id"], d.get("category_id")) for d in doc.values() if "series_id" in d}
series = {d["series_id"] for d in doc.values() if "series_id" in d}

print(len(doc), len(pairs), len(series))   # 145679  125869  123119
```

**Root cause.** Two things combine, both in
`apps/agentic/core/document_loaders/fred_document_loader.py`:

1. Documents are added with **no IDs** (lines 194–196), so `langchain_chroma`
   generates a fresh `uuid4` per document on every run. Nothing can match an
   existing row, so a re-run always appends.
2. `load_document` never calls `self.delete_document(filename)` before loading.

Both sibling loaders get this right, and either pattern would fix it:

- `research_library_document_loader.py:53` — deletes by `filename` first.
- `etf/finance_database_loader.py:146-165` — `reload_all_documents()` wipes the
  collection, then reloads.

**Impact.** MMR retrieval can return the same series up to three times in one result
set, wasting slots in a `k=50` window and crowding out distinct matches. A full
rebuild also embeds ~16% more documents than necessary, which is real money and
time given the corpus size.

**Documentation drift.** [data-store-fred.md](data-store-fred.md) has enshrined the
inflated number in two places, and both should be corrected alongside the fix:

- Line 18 — `| Documents | ~145,700 (one per series) |`. Wrong twice: the count
  includes the duplicates, and the grain is one per *(series, category)* pair, not
  one per series.
- Line 88 — "indexing embeds ~145k documents". Should be ~126k.

**To reproduce.** Open `.db/fred/chroma.sqlite3`, join `embedding_metadata` on `id`
to collect each document's `series_id` and `category_id`, then compare three counts:
total documents, distinct `series_id`, and distinct `(series_id, category_id)`. The
gap between the first and third is the duplication. Re-running
`python clients/bin/fred.py` grows the first count while leaving the third unchanged.

**The fix.** Preferred: pass explicit IDs to `add_documents`, keyed on
`f"{series_id}/{category_id}"`, which makes ingest an idempotent upsert and needs no
delete pass. Alternative: add a `reload_all_documents()` mirroring the ETF loader.

The general lesson for the coming document-store redesign: **every source needs a
stable natural document key.** CDC already has one (`series_id` embeds the dataset,
so all 2,502 are unique); FRED needs the compound `(series_id, category_id)`.
