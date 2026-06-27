# Architecture

This document is the high-level map for implementation. It is intentionally source-readable:
Mermaid diagrams stay in Markdown so GitHub and agents can read the same artifact.

The core architectural decision comes from [A0](./QUESTIONS_ASSUMPTIONS.md#a-language-and-core-concepts):
this is a **CSV ingestion workflow**, not a web API or full application layer. Postgres is the
source of truth, and domain invariants are enforced by database constraints, foreign keys,
checks, and triggers.

## Runtime View

```mermaid
flowchart LR
  CSV[CSV fixture files] --> TEMP[Session TEMP staging tables]
  TEMP --> TRANSFORM[SQL transform and inserts]
  TRANSFORM --> DB[(Postgres)]

  FLYWAY[Flyway migrations] --> DB
  PIPELINE[run_pipeline.sh] --> CSV
  PIPELINE --> TEMP
  PIPELINE --> ASSERTS[Acceptance assertions]
  ASSERTS --> DB

  DB --> SCHEMA[Tables, enums, FKs, checks]
  DB --> TRIGGERS[Database triggers]

  SCHEMA --> ACCEPT[Valid rows become durable data]
  SCHEMA --> REJECT[Invalid rows are rejected]
  TRIGGERS --> REJECT
```

The diagram overlays three flows; their order is fixed — **Flyway provisions the schema first**,
then `run_pipeline.sh` ingests CSV fixtures and runs assertions against the live schema.

### Responsibilities

- **Flyway** owns schema history: tables, enums, constraints, checks, and triggers.
- **`run_pipeline.sh`** owns the executable proof: load seed data, ingest valid CSV files, reject
  invalid CSV files, and assert the interesting invariants.
- **Temporary staging tables** are per-ingestion SQL buffers, not a durable staging subsystem.
- **Postgres** is the final guard. There is no Zod, TypeScript service layer, repository layer,
  or API validator in this design.

## Domain Model

```mermaid
erDiagram
  RESEARCHERS {
    bigint id PK
    text name
    text email
    researcher_role role
  }

  PROJECTS {
    bigint id PK
    text title
    text description
    project_status status
  }

  PROJECT_RESEARCHERS {
    bigint project_id FK
    bigint researcher_id FK
  }

  SAMPLES {
    bigint id PK
    text sample_code UK
    text sample_type
    timestamptz collected_at
    text storage_location
    bigint parent_sample_id FK
  }

  EXPERIMENTS {
    bigint id PK
    bigint project_id FK
    text title
    text hypothesis
    experiment_status status
    date start_date
    date end_date
    bigint predecessor_experiment_id FK
    bigint lead_researcher_id FK
  }

  MEASUREMENT_TYPES {
    text type PK
    text description
  }

  MEASUREMENTS {
    bigint id PK
    bigint experiment_id FK
    bigint sample_id FK
    text measurement_type FK
    jsonb value
    timestamptz recorded_at
    text notes
    bigint researcher_id FK
  }

  PROJECTS ||--o{ PROJECT_RESEARCHERS : has
  RESEARCHERS ||--o{ PROJECT_RESEARCHERS : collaborates_on
  PROJECTS ||--o{ EXPERIMENTS : contains
  RESEARCHERS ||--o{ EXPERIMENTS : leads
  EXPERIMENTS ||--o{ EXPERIMENTS : follows
  SAMPLES ||--o{ SAMPLES : parent_of
  EXPERIMENTS ||--o{ MEASUREMENTS : produces
  SAMPLES ||--o{ MEASUREMENTS : may_reference
  MEASUREMENT_TYPES ||--o{ MEASUREMENTS : classifies
  RESEARCHERS ||--o{ MEASUREMENTS : records
```

## Invariant Map

```mermaid
flowchart TB
  WRITABLE[B1: terminal project status freezes descendant writes]
  IMMUTABLE[E1: measurements are immutable after insert]
  SHAPE[A1: known measurement JSONB shapes are checked]
  LINEAGE[B2: direct self-lineage blocked; C2 multi-hop deferred]
  SAMPLE[A2: direct sample self-parenting is blocked]
  DATE[B3: experiment end date cannot precede start date]

  WRITABLE --> EXPERIMENTS[experiments insert trigger]
  WRITABLE --> MEASUREMENTS[measurements insert trigger]
  IMMUTABLE --> MEASUREMENTS_MUTATION[measurements update/delete trigger]
  SHAPE --> MEASUREMENTS_CHECK[measurements value CHECK]
  LINEAGE --> EXPERIMENTS_CHECK[experiments predecessor CHECK]
  SAMPLE --> SAMPLES_CHECK[samples parent CHECK]
  DATE --> EXPERIMENT_DATES[experiments date CHECK]
```

### Database-Enforced Rules

- Projects in terminal states (`completed`, `cancelled`) freeze new experiments and measurements
  beneath them; `planning` and `active` projects both accept writes.
- Measurements cannot be updated or deleted through normal database writes.
- Known measurement types use a `jsonb_typeof`-based `CHECK` on `measurements.value`.
- New measurement types can be registered as data first; hardening their JSONB shape is an
  additive migration when the shape becomes stable enough to enforce.
- Experiment and sample lineage block direct self-reference. Multi-hop cycle detection is
  deliberately deferred because CSV ingestion is treated as append-only historical import.
- Declarative constraints carry the rest: `samples.sample_code UNIQUE` (the lab's unique specimen
  id), `project_researchers PK(project_id, researcher_id)` (collaboration is M:N, deduplicated),
  enum domains on `researcher.role` and the two `*_status` columns, and `NOT NULL`/FK integrity
  across every relationship.

## Deliberate Non-Goals

- No web API, authentication, service classes, DTOs, or application-layer validation.
- No generated PNG/SVG architecture artifact unless a presentation needs one.
- No `experiment_samples` join table until the domain requires sample usage without a
  measurement row.
- No inventory management, depletion tracking, or sample state machine.
- No recursive lineage trigger until retroactive lineage editing becomes a real workflow.

For the step-by-step build order, see [implementation_plan.md](./implementation_plan.md).
