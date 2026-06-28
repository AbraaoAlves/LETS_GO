# Security Governance

This system carries the name on purpose: its security model is **database-resident integrity plus
write-once governance, with the runtime hardened at the edges**. Consistent with
[A0](../QUESTIONS_ASSUMPTIONS.md#a-language-and-core-concepts), there is no application layer to trust
or bypass. Every durable rule is enforced by Postgres itself, so the same guarantees hold whether a
row arrives through the CSV pipeline today or a future importer, CLI, or API.

## Current Controls

### Data trust: integrity and attribution

- Referential integrity on every relationship (`NOT NULL` + foreign keys). The ingestion pipeline
  uses failure-preserving lookups, so a bad reference fails the row against a constraint instead of
  being silently dropped.
- Stable identity guards: `researchers.email` and `samples.sample_code` are `UNIQUE`; roles and
  statuses are enum types, not free text.
- Typed measurement payloads: the
  [A1](../QUESTIONS_ASSUMPTIONS.md#a-language-and-core-concepts) `jsonb_typeof` `CHECK`
  (`migrations/V4`) rejects a numeric reading stored as a JSON string before it becomes durable data.
- Attribution by construction: every `measurement` carries a `NOT NULL researcher_id` and a
  `recorded_at`, so the record always answers who took the reading and when.

### Governance: records that hold up

- Immutability: the [E1](../QUESTIONS_ASSUMPTIONS.md#e-the-semantics-of-measurements) trigger blocks
  every `UPDATE`/`DELETE` on `measurements` (`migrations/V3`). Raw data is write-once.
- Finalization freeze: [B1](../QUESTIONS_ASSUMPTIONS.md#b-defining-bound-of-project---experiments---measurement)
  triggers reject new experiments and measurements beneath `completed`/`cancelled` projects. A
  finalized study cannot quietly grow new data.
- Honest gap disclosure is part of the control surface. The known traceability gaps — corrections
  leave no trace and zero-measurement samples are invisible — are documented in README trade-offs
  instead of hidden.

### Operations: local by default

- Postgres binds to `127.0.0.1` by default; exposure on a routable interface is an explicit opt-in
  via `POSTGRES_BIND_ADDRESS`.
- Source, migrations, and CSV fixtures are mounted read-only (`:ro`) into the Flyway and tester
  containers. The pipeline cannot mutate its own inputs.
- Images are pinned (`postgres:15.13-alpine`, `postgres:15.13`, `flyway:10.22.0`), so rebuilds do
  not drift to `latest`.

## Row-Level Security: a deliberate non-choice

RLS answers one question: at query time, which rows may this principal see or change? It earns its
place only when a database has multiple query-time principals with different row-level visibility
(multi-tenant isolation, per-researcher read scopes).

This system has neither. Under [A0](../QUESTIONS_ASSUMPTIONS.md#a-language-and-core-concepts), it is
a CSV ingestion workflow with a single principal: the role Flyway and `tests/run_pipeline.sh` run as.
There is no query-time application serving distinct users. Enabling `ROW LEVEL SECURITY` today would
create policies that always evaluate against that one role: ceremony, not protection.

**Trigger to revisit:** the moment something other than the ingestion pipeline queries this database
on behalf of distinct people: per-lab tenancy, or read-only researcher access. That hinge is already
captured as an open question: do researcher roles drive access control, or are they descriptive
metadata? When the answer is access control, RLS is the right tool and slots in without reshaping the
schema.

## Hardening Roadmap

None of this is implemented yet. Each item names the condition that makes it worth the weight.

1. **Least-privilege ingestion role**: a `lab_ingest` role distinct from the migration/superuser
   role, with the `SELECT`/`INSERT`, temporary-table, and identity-sequence privileges needed by the
   CSV pipeline. Worth doing as soon as ingestion runs anywhere shared.
2. **Append-only audit trail**: `pgaudit`, or a trigger-backed `audit_log` table, to record who
   performed rare out-of-band DBA corrections. Worth doing when corrections stop being exceptional.
3. **Row-Level Security**: when a query-time, multi-principal reader appears.
4. **Deploy-time hardening**: non-default credentials via a secret manager, TLS in transit, and
   encryption at rest. The default `postgres/postgres` credentials are a deliberate local-only choice
   for this TDD stack; these matter the moment it leaves a developer machine.
