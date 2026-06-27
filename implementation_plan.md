# Implementation Plan — LETS_GO Lab Experiment Tracking (TDD-first)

This is the execution plan for the schema, Docker setup, and seed/test data described in
[PROBLEM.md](./PROBLEM.md), built on the assumptions in
[QUESTIONS_ASSUMPTIONS.md](./QUESTIONS_ASSUMPTIONS.md) and the decisions in
[README.md](./README.md). It is **test-first**: the expected ingestion behavior (seed +
valid/invalid CSV + assertions) is written *before* the schema, then the schema is built to
satisfy it.

## Context

The repo started as **documentation only** — the full domain design existed, but there was **no
schema, no migrations, no Docker, no seed/test data**. This plan delivers the three PROBLEM
deliverables: Postgres migrations startable with a single Docker command, seed/test data that
exercises the model, and the README "how to start" + decisions.

**Invariant (AGENTS.md / A0):** no application layer. Every rule lives in the database, so the
ingestion test suite's whole job is to prove **the database — not app code — accepts good CSV
rows and rejects bad ones, for every entity**.

### Locked decisions
- **Two-tool split:** **Flyway** owns the **schema** (versioned DDL migrations);
  **`run_pipeline.sh`** owns **CSV ingestion + tests** (load seed, ingest valid CSVs → assert
  accepted, ingest invalid CSVs → assert rejected). A `pipeline_tester` compose service runs it
  after Flyway succeeds. → written up as a README **Decision** (Step 10).
- **Lifecycle enums include `planning`:** `project_status`/`experiment_status` =
  `planning | active | completed | cancelled`. Projects accept experiment/measurement writes
  while `planning` or `active`; terminal `completed`/`cancelled` freeze them (B1 trigger).
  Experiment status is descriptive, not a write gate.
- **CSV identity contract:** database IDs stay `GENERATED ALWAYS AS IDENTITY`; CSV fixtures never
  depend on generated IDs. Relationship files use stable fixture keys and session TEMP staging:
  `researcher_email`, `project_title`, `sample_code`, and `(project_title, experiment_title)` for
  experiment references. The demo fixtures keep those titles unique; production external IDs are
  deferred with the raw-export ETL work from README Decision 0.1. Lookups must be
  failure-preserving: required references use scalar subqueries into `NOT NULL` FK columns, and
  optional references treat blank as `NULL` but nonblank missing keys as FK failures. Do not
  `INNER JOIN` bad fixture rows away.
- **Naming/transform:** follow committed [docs/csv-ingestion.md](./docs/csv-ingestion.md) —
  `measurements (measurement_type, value)`, flat staging columns → `jsonb_build_object`
  (the `::numeric` cast is validation gate 1, the `CHECK` is gate 2).

### Documentation is part of every step
No separate documentation step — each step carries its own `Docs:` line.

### Target layout
```
implementation_plan.md      # this plan
docker-compose.yml          # postgres + flyway(one-shot) + pipeline_tester(one-shot)
run_pipeline.sh             # ingestion + assertion harness (TDD runner)
migrations/                 # FLYWAY — schema only
  V1__enums_and_reference.sql  V2__core_tables.sql
  V3__constraints_and_triggers.sql  V4__measurement_value_check.sql
seeds/seed.sql              # minimal trusted anchors + lifecycle flips CSV can't express
samples/                    # focused valid + invalid CSV fixtures (Step 2 matrix)
```

---

# PHASE 1 — Write the expectation first (the failing test)

## Step 1 — `seeds/seed.sql` (minimal trusted baseline)
Re-runnable (`TRUNCATE ... RESTART IDENTITY CASCADE` then `INSERT`). Holds only what the
ingestion CSVs **can't** express, so it stays small:
- A couple **researchers** and one **active Project Alpha** + samples/experiments to act as
  valid FK targets for the invalid-case tests.
- **Project Beta** created active, given an experiment, then flipped to **`completed`** — the
  lifecycle transition the CSV path can't perform (you can't ingest an experiment into an
  already-frozen project). Beta is the frozen target the experiment/measurement freeze tests
  fire against.
- **Project Gamma** in **`planning`** — the positive control proving `planning` accepts writes
  (B1 freezes only terminal states); the experiments valid case (Step 2) targets it.

`Docs:` header comment mapping each block to the scenario it anchors.

## Step 2 — CSV fixture **matrix** (`samples/*.csv`)
For each entity: one **valid** file that must ingest, and a small set of **targeted invalid**
files that each trip exactly one documented DB invariant. Keep this focused on proving the
database model, not building a production CSV test framework. Derived from PROBLEM +
QUESTIONS_ASSUMPTIONS:

| Entity CSV | Valid case (accept) | Invalid case(s) (reject) | DB invariant |
| --- | --- | --- | --- |
| `researchers` | name, email, role ∈ enum | role `postdoc` (unknown); name NULL | `researcher_role` enum (F1); `NOT NULL` |
| `projects` | title, desc, status ∈ enum | status `archived`; title NULL | `project_status` enum (B1); `NOT NULL` |
| `project_researchers` | existing `project_title` + `researcher_email` | nonexistent `researcher_email`; duplicate pair | FK; `PK(project_id,researcher_id)` (M:N) |
| `samples` | unique `sample_code`, type, collected_at; valid `parent_sample_code` | duplicate `sample_code`; parent ref nonexistent | `UNIQUE`; FK; (A2 `CHECK parent<>id`) |
| `experiments` | active **or planning** project by `project_title`; end≥start; cross-project predecessor by `(project_title, experiment_title)` (C1) | end_date<start_date; project ref nonexistent; **target = completed Beta**; predecessor=self asserted directly because generated-ID CSVs cannot point a new row at itself | `CHECK` end≥start (B3); `CHECK` self (B2); FK; **B1 freeze trigger** |
| `measurements` | numeric / categorical / text / `sample_code` NULL (E2) / registered unknown-type | numeric value as JSON string or missing unit; `numeric_value="12.x"`; experiment ref nonexistent; **target experiment under frozen Beta** | shape `CHECK` (A1); `::numeric` cast gate; FK; **B1 freeze** |

Plus the **non-ingest** invariants asserted directly in Step 3: experiment self-predecessor
(`OVERRIDING SYSTEM VALUE` is needed to express it without CSV IDs), numeric JSON string shape,
and UPDATE/DELETE on a measurement → rejected (E1). The `unknown-type` measurement row is a
**valid** case only after the pipeline inserts that new type into `measurement_types`; it proves
new techniques need data registration, not a schema migration, until their JSONB shape is worth
hardening (A1).

`Docs:` a **CSV contract** note per entity appended to `docs/csv-ingestion.md`, including the
fixture key columns used to resolve generated database IDs and the two measurement validation
gates.

## Step 3 — `run_pipeline.sh` (the TDD runner)
Based on the harness shape (`test_case` / `assert_success` / `assert_failure` / `finish`, each
assertion its own `psql -v ON_ERROR_STOP=1`):
1. `TRUNCATE measurements CASCADE;` then `\i seeds/seed.sql` (TRUNCATE bypasses the E1 row
   trigger by design, so the harness can reset; E1 still blocks UPDATE/DELETE).
2. **Ingest valid CSVs in dependency order** (researchers → projects → project_researchers →
   samples → experiments → measurement_types additions → measurements), each `assert_success`.
   Every relationship CSV loads into a TEMP table, then `INSERT ... SELECT` resolves fixture keys
   to generated IDs (`researcher_email`, `project_title`, `sample_code`, `(project_title,
   experiment_title)`) without silently filtering rows. Measurements use a per-call `CREATE TEMP
   TABLE staging_measurements (...flat text...)` + `\copy` + `INSERT ... SELECT CASE
   measurement_type WHEN 'numeric' THEN jsonb_build_object('value',numeric_value::numeric,
   'unit',unit) WHEN 'categorical' THEN jsonb_build_object('value',categorical_value) WHEN 'text'
   THEN jsonb_build_object('note',note) ELSE to_jsonb(note) END` — TEMP buffers match
   `docs/csv-ingestion.md` (no schema pollution).
3. **Ingest each invalid CSV** in a `BEGIN/…/ROLLBACK-on-error` → `assert_failure`.
4. **Immutability asserts** (direct SQL, not CSV): `UPDATE` and `DELETE` a seeded measurement →
   `assert_failure` (E1).
- Caveat: `postgres:15-alpine` lacks `bash`/`tput` — use a `bash`-capable image for
  `pipeline_tester` or guard `tput` and run under `/bin/sh`.

`Docs:` top-of-file comment declaring this the executable spec — the "write the test, then make
it pass" artifact for Phase 2.

---

# PHASE 2 — Make it pass (Flyway schema migrations)

## Step 4 — `migrations/V1__enums_and_reference.sql`
`researcher_role`, `project_status`, `experiment_status` enums; `measurement_types(type PK,
description)` registry with bootstrap reference rows for `numeric`/`categorical`/`text`.
`Docs:` migration comments cite A1/F1/B1; update `QUESTIONS_ASSUMPTIONS.md` **B1** ENFORCEMENT
one line → `planning|active|completed|cancelled`, noting terminal (`completed`/`cancelled`)
freezes writes while `planning`/`active` permit them (A0).

## Step 5 — `migrations/V2__core_tables.sql`
Tables in dependency order, `bigint GENERATED ALWAYS AS IDENTITY` PKs, `timestamptz` stamps:
`researchers`(F1, `UNIQUE email`) · `projects`(B1) · `project_researchers`
PK(project,researcher) (M:N) · `samples`(A2/D1, `UNIQUE sample_code`, `parent_sample_id`
self-FK, `CHECK parent<>id`) ·
`experiments`(B2/B3/C1, `project_id NOT NULL`, `end_date` nullable + `CHECK end≥start`,
`predecessor_experiment_id` self-FK + `CHECK self`, `lead_researcher_id`) · `measurements`
(B4/E2/A1, `experiment_id NOT NULL`, `sample_id` nullable, `measurement_type` FK→registry,
`value jsonb NOT NULL`, `recorded_at`, `notes`, `researcher_id`).
`Docs:` migration comments cite each table's governing assumption.

## Step 6 — `migrations/V3__constraints_and_triggers.sql`
- **B1 freeze** `enforce_writable_project()` BEFORE INSERT on `experiments` (by `NEW.project_id`)
  and `measurements` (join experiment→project by `NEW.experiment_id`); RAISE when project status
  ∈ {`completed`,`cancelled`}.
- **E1 immutability** `prevent_measurement_mutation()` BEFORE UPDATE OR DELETE on `measurements`
  → RAISE (TRUNCATE intentionally unguarded — Step 3 cleanup).
`Docs:` comments cite B1/E1 (two levels of one invariant).

## Step 7 — `migrations/V4__measurement_value_check.sql`
A1 type-aware `CHECK` in its own migration (hardening a type = one additive `WHEN`; final
`END IS TRUE` keeps missing JSON keys from passing as nullable CHECK results):
`numeric`→value number + unit string; `categorical`→value string; `text`→note string;
`ELSE TRUE`. `Docs:` keep in sync with `docs/csv-ingestion.md` CHECK section.

---

# PHASE 3 — Wire it together + the tooling Decision

## Step 8 — `docker-compose.yml` + single command
`postgres`(15-alpine, db `lab`, `pg_isready` healthcheck) · `flyway`(`flyway/flyway:10`,
`migrate`, `-locations=filesystem:/flyway/sql`, mounts `./migrations`, depends_on postgres
healthy) · `pipeline_tester`(runs `./run_pipeline.sh`, mounts repo, `DB_URL`, depends_on flyway
`service_completed_successfully`). Single command: **`docker compose up`** → postgres healthy →
flyway V1–V4 → pipeline builds the world via ordered valid CSV ingest, proves every invalid CSV
is rejected, proves immutability. Postgres stays up with schema + ingested data.
`Docs:` README **Quick start** (the command, how to connect, 2–3 demo queries: M:N
collaborators, ancestor chain via recursive CTE, distinct samples per experiment) + a **schema
overview** linking tables to assumptions.

## Step 9 — Cross-link this plan
Reference `implementation_plan.md` from the README so the planning artifact sits alongside the
existing DDD docs.

## Step 10 — README **Decision: Flyway (schema) split from `run_pipeline.sh` (ingestion/tests)**
Same structure as the existing JSONB decision:
- **Options / why-rejected:** (a) one tool/app does migrate+ingest — conflates concerns, app
  layer contradicts A0; (b) Flyway does everything incl. seed-as-migration — couples demo data
  to schema history, no place to express valid/invalid CSV *assertions*; (c) plain init scripts
  — not versioned, fresh-volume only, no assertion harness.
- **[Chosen]** Flyway for schema + `run_pipeline.sh` for ingestion/tests.
- **Advantages:** separation of concerns; pipeline doubles as an executable test suite proving
  invariants live in the DB across **every entity** (TDD); fixtures iterate without new
  migrations; single command stays `docker compose up`.
- **Trade-offs/Risks:** two moving parts + container ordering; bespoke bash harness (not a real
  test framework); pipeline is illustrative of the future importer, not production-grade
  (column mapping/error reporting still deferred per A0).
- **Mitigation:** keep the harness small + assertion-driven; document the CSV contract by the
  fixtures; promote to a real test runner only if the suite grows.

---

## Verification (end-to-end)
1. `docker compose up` → `flyway` exits 0; `pipeline_tester` exits 0 (**all assertions pass**).
2. Schema present: `psql -U postgres -d lab -c "\dt"` lists 7 tables, including
   `measurement_types`.
3. Positive scenarios (queries): M:N collaborators; recursive-CTE ancestor chain Exp-A→B/C +
   cross-project Beta→Alpha; `DISTINCT sample_id` shows S1 under Exp-A and Exp-B; multi-kind
   measurements present from the valid measurements CSV.
4. Invariants — asserted by the harness across **all entities** (re-runnable by hand):
   enum domain (bad role/status), `NOT NULL`, FK (bad refs), `UNIQUE` (dup sample_code),
   `PK` (dup collaborator pair), `CHECK` end≥start + self-reference, JSONB shape + `::numeric`
   cast, **B1 freeze** (writes into completed Beta), **E1 immutability** (UPDATE/DELETE),
   and `ELSE TRUE` permissiveness (unknown type accepted).
5. Idempotency: `docker compose down -v && docker compose up` reproduces the same green run.
