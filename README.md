# durag

**durag** is a private, long-lived, knowledge base for operational documents. It collects supported PDF, Word, and Excel documents from email attachments and manual uploads, preserves their provenance, and makes them searchable for cited answers and summaries.

> **Status:** Design stage. No components are implemented yet. Do not add credentials or private documents to this repository.

## What it should do

- Import attachments from Gmail, Microsoft 365, and generic IMAP via a **polling worker** (scheduled background service); accept documents via drag-and-drop Web UI and CLI import.
- Preserve unmodified originals in MinIO with enough metadata to trace each answer to its source.
- Parse mixed-format documents (including tables) and flag unsupported or low-quality extraction.
- Accumulate content over months and years without relying on a single long-context prompt.
- Search by meaning and exact technical tokens (service names, error codes, versions, IPs, hashes).
- Produce grounded answers and summaries with citations and clear uncertainty.
- Keep sync repeatable, documents deduplicated, and the search index rebuildable from originals.

## Proposed stack

| Component | Choice |
|---|---|
| Language | Python |
| Object store | MinIO |
| Metadata DB | PostgreSQL |
| Search index | pgvector or Qdrant (evaluating) |
| Email ingestion | `google-api-python-client` (Gmail), `msal` + `requests` (Microsoft Graph), `imaplib` (generic IMAP) |
| Parsing | Docling (evaluating); Unstructured and LlamaParse as alternatives |
| LLM | Ollama (local default) / OpenAI API (optional) |
| Orchestration | LlamaIndex (optional) |
| Deployment | Kubernetes (packaged via Helm) |

## Architecture overview

Two main paths: a **write path** for collecting and indexing documents, and a **read path** for retrieval and answer generation.

```
[Polling Worker]  -->  [Ingestion & ETL]  -->  [Chunking & Parsing]  -->  [Storage & Indexing]  -->  [Retrieval & LLM]
(Gmail / Graph / IMAP)  (PDF, DOCX, XLSX)      (Docling / Unstructured)    (pgvector/Qdrant + BM25)   (Rerank -> Synthesis)
```

→ Full architecture, diagrams, and design details: [docs/architecture.md](docs/architecture.md)

## Open decisions

1. Which email provider first: Gmail or Microsoft 365?
2. Web UI drag-and-drop or CLI import delivered first? (Both use the same ingestion pipeline.)
3. Is sending selected excerpts to the OpenAI API acceptable, or must all processing remain local?
4. What MinIO deployment, bucket versioning/retention, backup, and encryption controls?
5. Are scanned PDFs/OCR and numeric Excel analysis required initially?
6. Which representative documents for parser comparison (Docling vs. Unstructured vs. managed)?

## Delivery plan

1. **Design and data policy** — provider, upload path, MinIO, metadata DB, model policy, retention
2. **Storage and ingestion** — MinIO bucket, event notifications, ingestion service, CLI/email, deduplication
3. **Parsing and retrieval** — parser quality testing, embeddings, hybrid search, evaluation corpus
4. **Grounded Q&A** — citations, uncertainty, hierarchical summaries, Ollama/OpenAI answer generation
5. **Production operations** — second provider, deletion/retention, backup, monitoring, OCR

→ Details: [docs/architecture.md](docs/architecture.md#suggested-delivery-plan) and implementation plan in [docs/wbs.md](docs/wbs.md)

## Getting started

Design stage — no components to run yet. To contribute:

1. Review the [architecture document](docs/architecture.md)
2. Review the [work breakdown structure (WBS)](docs/wbs.md)
3. Weigh in on the [open decisions](#open-decisions) above

## Contributors

- [Cedric KOUEKAM](https://github.com/CedricElie)
- [Guylaine NGOUDJO](https://github.com/ngoug)

## License

See [LICENSE](LICENSE).
