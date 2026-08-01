# GitHub Code Data Store

A ChromaDB index of **source code** from cloned GitHub repositories, chunked for retrieval. It
backs questions like "where do I handle MIDI output in zgomot?" — semantic code search across
personal and organization repos.

See [architecture.md](architecture.md) for how this fits the wider system.

---

## Identity

| | |
| --- | --- |
| Engine | ChromaDB (persistent) |
| Path | `.db/github` |
| Collection | `github-repos` |
| Documents | ~415,000 **chunks** (largest collection in the system) |
| Embeddings | `OpenAIEmbeddings` (`embedding_ctx_length=2000`, `chunk_size=100`) |
| Loader | `apps/agentic/core/document_loaders/github_document_loader.py` → `GitHubChromaDocumentLoader` |
| Working tree | `.repos/` (gitignored) — repos are cloned locally, then indexed |
| Accounts | `troystribling`, `glyfish` (`GITHUB_ACCOUNTS`), excluding `3dmodels` |

Unlike the ETF and FRED catalogs (one document per entity), this store is **chunked** — a single
file becomes many documents, each with a `start_index` offset.

---

## What a document looks like

Page content is a raw slice of a source file:

```text
README.rdoc
lib/**/*.rb
bin/*
features/**/*.feature
LICENSE
```

Chunks carry enough metadata to reconstruct provenance — which repo, which file, which commit.

---

## Metadata schema

| Field | Example | Notes |
| --- | --- | --- |
| `account` | `glyfish` | GitHub owner. **Filterable**. |
| `repo` | `meida` | Repository name. **Filterable**. |
| `branch` | `main` | Branch indexed (the repo's default branch). |
| `commit` | | Commit SHA the chunk was indexed from. |
| `commit_ts`, `commit_ts_unix` | | Commit timestamp, ISO and epoch. |
| `file_path` | `lib/foo/bar.rb` | Path within the repo. |
| `file_name`, `filename`, `path`, `source` | | Overlapping path/name variants retained for retrieval and display. |
| `ext` | `.rb` | File extension. **Filterable** — how "Ruby code" is expressed. |
| `file_type` | `ruby` | Language, mapped from `ext` via `PROGRAMMING_LANGUAGE_MAP`. |
| `start_index` | `0` | Character offset of the chunk within the file. |
| `ts_iso`, `ts_unix` | | Index timestamps. |

Language filtering works on **extension**, not language name: `CodeRepoFilters` instructs the
model to map "Python" → `.py`, "Ruby" → `.rb`, and so on, matching `PROGRAMMING_LANGUAGE_MAP` in
`apps/agentic/core/constants.py`.

---

## Loading and refresh

Driven by `DocumentLoaderAgent`, so it is reachable conversationally:

| Tool | Behavior |
| --- | --- |
| `load_github_repo` | Clone/update one `account/repo` into `.repos/`, then index it. Collects `account` + `repo` via a human-in-the-loop form. |
| `load_all_github_repos` | Index every repo across `GITHUB_ACCOUNTS`, minus `GITHUB_EXCLUDED_REPOS`. Runs without a form. |

Re-indexing a repo calls `_delete_repo(account, repo)` first, which deletes the repo's existing
chunks by metadata filter — so a reload replaces rather than duplicates. The loader resolves the
default branch (`get_default_branch`) and builds a commit map (`build_commit_map`) so chunks can
be stamped with per-file commit provenance.

The `load_github_repo` form prefill is filled deterministically when the model leaves it blank:
`HumanInputNode._augment_github_prefill()` parses an `owner/repo` slug or GitHub URL out of the
user's message.

---

## How it is queried

**Agent** — `CodeRepoAgent` (`apps/agentic/agents/document/code_repo_agent.py`), a
**`FileChromaRAGAgent`** (file-aware: it can aggregate chunks back up to whole files), reached via
the DocumentAgent delegate `delegate_to_code_repository_search_agent`.

**Filters** — `extract_code_repo_filters()` → `CodeRepoFilters` → `code_repo_filters_to_where()`,
filtering on `account`, `repo`, and `ext`.

```text
"Find MIDI output handling in troystribling/zgomot"
  → {"$and": [{"account": "troystribling"}, {"repo": "zgomot"}]}
```

`DataInfoAgent` also exposes inventory tools over this store — `repository_names` and
`filenames_for_repository` — for "what repos do I have indexed?" style questions that need no
semantic search.

---

## Operational notes

- **`.repos/` is gitignored and large.** The API server's `--reload` watcher is deliberately
  scoped to `api` and `apps` so cloning during `load_github_repo` does not trigger restarts.
- **Chunk count dominates cost.** At ~415k chunks this is the most expensive collection to
  rebuild; prefer per-repo reloads over a full re-index.
- **Reload is delete-then-insert**, and the two steps are not transactional, so an interrupted
  reload can leave a repo partially indexed — re-running `load_github_repo` for that repo is the
  fix, since it deletes first.
- This store has **no relationship to the time-series cache** — unlike the ETF and FRED catalogs,
  nothing here is lifted into PostgreSQL. It is purely a retrieval corpus.
