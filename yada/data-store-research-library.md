# Research Library Data Store

A ChromaDB index of the personal research corpus — papers, research notes, blog posts, and
publications — chunked by document section. It backs questions like "what does my library say
about the Carnot cycle?"

See [architecture.md](architecture.md) for how this fits the wider system.

---

## Identity

| | |
| --- | --- |
| Engine | ChromaDB (persistent) |
| Path | `.db/research_library` |
| Collection | `research-library` |
| Documents | ~4,900 **chunks** |
| Embeddings | `OpenAIEmbeddings` (`embedding_ctx_length=2000`, `chunk_size=100`) |
| Loader | `apps/agentic/core/document_loaders/research_library_document_loader.py` → `ResearchLibraryChromaDocumentLoader` |
| Source tree | `research_library/` (**gitignored**) |
| Manifest | `research_library/research_documents.yml` (~70 entries) |

The smallest of the four Chroma catalogs, but the most curated — documents are declared in a YAML
manifest rather than discovered by crawling.

---

## What a document looks like

Page content is a section-sized slice of a markdown document:

```text
Analytic Mechanics
Troy Stribling
Now. 12, 2018
```

Chunking follows document structure: `_page_starts_from_h2()` locates `##` headings and
`_page_of()` maps a character offset back to its section, so a chunk knows which part of the
document it came from.

---

## Metadata schema

| Field | Example | Notes |
| --- | --- | --- |
| `shelf` | `notes`, `jaynes` | Collection the document belongs to. **Filterable** — closed vocabulary (below). |
| `title` | `Analytic Mechanics` | Document title. **Filterable**, spelling-corrected by the extractor. |
| `authors` | `Troy Stribling` | Author(s). **Filterable**, spelling-corrected. |
| `topic` | | Subject tag from the manifest. |
| `published_date` | | Publication date where known. |
| `section` | | Section heading the chunk falls under. |
| `section_char_offset` | `0` | Offset of the section within the document. |
| `start_index` | `0` | Offset of the chunk. |
| `filename`, `path`, `ext` | `.md` | Source file provenance. |
| `images` | | Associated image references, where present. |

### Shelves

Five shelves are in use, verified against the live collection:

| Shelf | Contents |
| --- | --- |
| `jaynes` | Papers by E. T. Jaynes |
| `notes` | Research notes (Troy Stribling) |
| `posts` | Blog posts (Troy Stribling) |
| `publications` | Published academic papers (Troy Stribling) |
| `reading_list` | Papers by external authors |

`ResearchLibraryFilters` maps colloquial phrasing onto these exact values ("blog" → `posts`,
"reading list" → `reading_list`).

---

## Loading and refresh

`research_documents.yml` is the manifest: it declares each document's shelf, title, authors,
topic, and source path. The loader reads a document, splits it into section-aware chunks, and
writes them with the manifest metadata attached.

| Entry point | Behavior |
| --- | --- |
| `DocumentLoaderAgent.load_research_document` | Load one document; collects its fields via a human-in-the-loop form. |
| `ResearchLibraryChromaDocumentLoader.load_all_documents(base_path)` | Batch load from a directory. |
| `notebooks/documents/research_library_document_loader.ipynb` | Interactive loading. |
| `notebooks/documents/research_library_chroma_query.ipynb` | Interactive querying. |

`delete_document(filename)` (inherited from `ChromaDocumentLoader`) removes a document's chunks by
filename, so a document can be re-indexed cleanly.

---

## How it is queried

**Agent** — `ResearchLibraryAgent` (`apps/agentic/agents/document/research_library_agent.py`), a
**`FileChromaRAGAgent`** — it aggregates matching chunks back up to whole documents, so answers
cite documents rather than fragments. Reached via the DocumentAgent delegate
`delegate_to_research_library_search_agent`.

**Filters** — `extract_research_library_filters()` → `ResearchLibraryFilters` →
`research_library_filters_to_where()`, filtering on `shelf`, `title`, and `authors`.

```text
"Search my research library for the definition of the Carnot Cycle"
  → where=None, query="definition of the Carnot Cycle"     # pure semantic search

"What are the Jaynes papers about entropy?"
  → {"shelf": "jaynes"} + query="entropy"
```

`DataInfoAgent` adds inventory tools over this store — `research_library_metadata_summary` and
`research_library_titles_by_metadata` — for "what shelves/topics do I have?" questions that need
no semantic retrieval. These synthesize prose, which is why `DataInfoAgent` deliberately runs on
the full generation model rather than the cheap router model.

---

## Operational notes

- **The corpus is gitignored.** `research_library/` (including the manifest) is excluded from the
  repo, so the store cannot be rebuilt from a fresh clone alone — the source documents must be
  present locally.
- **The manifest is the source of truth** for shelf/title/authors. Fixing a mis-tagged document
  means editing `research_documents.yml` and re-indexing that document, not patching Chroma.
- **Chunks are section-aware**, so retrieval quality depends on documents using `##` headings;
  a flat document degrades to offset-based chunking.
- Like the GitHub store, this has **no relationship to the time-series cache** — nothing here is
  lifted into PostgreSQL.
