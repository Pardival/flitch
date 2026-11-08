# 0002 · GRDB/SQLite for history and memory

- Status: Accepted (2026-11-08)

## Context
Flitch keeps conversation history, an "About me" profile and learned memories. It needs relevance search (which memories go into the prompt), easy wiping and no server.

## Decision
- One local SQLite file at `~/Library/Application Support/Flitch/flitch.sqlite`, accessed through GRDB 7.
- Search uses FTS5 indexes on messages and memories.

## Consequences
- Fast, local and inspectable. Migrations are versioned in code, and tests use an in-memory database.
- One third-party dependency (MIT licence).
- SwiftData was rejected: less control over FTS and migrations, and it is harder to test outside an app.
