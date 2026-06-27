# LETS_GO: Lab Experiment Track System for Governance and Operations

## Project Summary

The system is a Laboratory Experiment Tracking System (LETS) to manage laboratory governance and operations. Created to solve this challange ([PROBLEM.md](./PROBLEM.md)) 

## Architecture

See [ARCHITECTURE.md](./ARCHITECTURE.md) for the runtime map, domain graph, and database
invariant map used to guide implementation.

## OpenQuestions & Assumptions

To start this solutions I made a list questions and assumptions about the problem. You can see here: [QUESTIONS_ASSUMPTIONS.md](./QUESTIONS_ASSUMPTIONS.md).


## Decisions & Trade-offs

### 0. Runtime context: CSV ingestion workflow

Based on [A0](./QUESTIONS_ASSUMPTIONS.md#a-language-and-core-concepts), I assume the first runtime context is a **CSV ingestion workflow for lab exports**, not a full web API or long-running application service.

This keeps the solution focused on what the challenge asks for: a Postgres data model, Docker startup, and seed data that prove the model works. The domain rules should live as close to the data as possible through tables, foreign keys, unique constraints, enums, and check constraints. Any CSV-specific parsing or row-shape validation can live in the ingestion step when that workflow is implemented.

Below is the rationale behind this choice and the trade-offs considered.

---

- **Web API Microservice Approach** : Build an HTTP API around the model, with request handlers, DTOs, service classes, authentication concerns, and validation in the application layer. **Why it was rejected:** The prompt asks for a database model that can be started with Docker and inspected live. Adding an API now would create more code to explain without proving the core model better.

- **Full Domain Application Layer Approach** : Build a DDD-style application layer with use cases, repositories, and schema validators before the database is exercised. **Why it was rejected:** The current ambiguity is mostly about domain invariants, not transport or orchestration. Capturing those invariants in the schema and documentation gives faster value and keeps the interview surface smaller.

- **[Chosen] CSV Ingestion Workflow Approach** : Treat the lab's current spreadsheet/export world as the input boundary. CSV rows are parsed and normalized before insert, while Postgres remains the source of truth and final validation guard for relationships and durable constraints. See [docs/csv-ingestion.md](./docs/csv-ingestion.md) for the flat-CSV → JSONB transform seam that bridges this decision with the JSONB measurement model in [Decision 1](#1-measurements-the-jsonb-approach).

#### Advantages

- **Simple Delivery Path**: Matches the required Docker + Postgres + seed-data deliverable without adding an unrequested API surface.
- **Pragmatic Migration from Spreadsheets**: Fits the lab's current reality: they are already working from spreadsheet-like systems and need a clean target model.
- **Centralized Data Integrity**: Core rules are enforced by the database, so future import scripts, CLIs, or APIs inherit the same constraints.

#### Accepted Trade-offs & Risks :

- **Batch-Oriented Feedback**: CSV ingestion usually reports errors after a file is processed, not interactively while a researcher is typing.
- **Importer Responsibility**: CSV header mapping, required columns, type coercion, and row-level error messages still need to be handled outside the database.
- **Limited Product Surface**: This does not yet solve user workflows such as login, approval, dashboards, or real-time experiment editing.

##### Mitigation Strategies:

Keep the database strict on durable invariants, document the expected CSV contract near the ingestion script when it exists, and add a small staging/error-report table only if bad production files become a real workflow problem.

### 1. Measurements: The JSONB approach

My first design decisions in this system revolves around [how to store `Measurements`](./QUESTIONS_ASSUMPTIONS.md#a-language-and-core-concepts). The requirements state that measurements can take several forms and that **new kinds of measurements are added occasionally** as the lab adopts new techniques.

To solve this flexibility requirement, I chose to implement a **JSONB column (`value`)** within a unified `measurements` table to store the polymorphic payload, rather than relying on strict relational alternatives.

Below is the rationale behind this choice and the trade-offs considered.

---

- **Classic Relation Approach** : A single `measurements` table containing optional columns for every possible type: `numeric_value`, `unit`, `categorical_value`, and `text_value`. **Why it was rejected:** While this maintains strict database-level data typing, it fails to support the requirement that new measurement types will be added over time. Every time the lab adopts a new technique, it would require executing a migration (`ALTER TABLE`) to add new columns. This introduces unnecessary operational friction, potential table locks in production, and leads to a heavily sparse table filled with `NULL` values.

- **Entity-Attribute-Value (EAV) Approach** : Splitting the data into `measurement_attributes` (metadata like name, type, unit) and `measurement_values` (rows mapping a measurement instance to an attribute and its value). **Why it was rejected:** The EAV pattern is notorious for complicating queries. Fetching a complete experiment profile with multiple measurements requires complex, multi-layered `JOIN` operations or pivoting data in application memory. It also degrades indexing performance and obfuscates the data structure for future developers.


- **[Chosen] JSONB Polymorphism Approach** : By utilizing PostgreSQL's native `JSONB` data type, the table structure remains lean and completely decoupled from the specific domain of the scientific technique being introduced.

--- 

#### Advantages:

- **Future-Proof Extensibility**: The lab can introduce a complex, nested measurement type tomorrow (e.g., a genomic sequence slice or an array of multidimensional sensor readings) without requiring a single database migration.  
- **Performance**: JSONB stores data in a decomposed binary format. This allows us to inject GIN (Generalized Inverted Index) indexes directly on JSON keys, ensuring that queries targeting specific internal properties remain fast.
- **Operational Simplicity**: Avoids the complexity of managing multiple joined tables or running risky structural schema updates on growing production databases.


#### Accepted Trade-offs & Risks : 

- **No type safety from the column definition**: Unlike a typed column, a `JSONB` column does not, on its own, guarantee that a numeric measurement holds a valid number. That guarantee has to be added explicitly.

- **Known JSONB shapes are still database-enforced**: A `JSONB` column does not infer the expected shape from `measurement_type` by itself, but Postgres can enforce that contract with a `CHECK` using `jsonb_typeof`. Under [A0](./QUESTIONS_ASSUMPTIONS.md#a-language-and-core-concepts), the database is the last guard: a numeric measurement inserted as a JSON string is rejected before it becomes durable data.

##### Mitigation Strategies:

Enforce the payload contract with a Postgres `CHECK` on `value` that branches on `measurement_type`: assert the shape and `jsonb_typeof` of the known core types (a numeric reading must be a JSON `number`, a unit must be a JSON `string`), while staying permissive for not-yet-seen types so adopting a new technique still needs no migration. The CSV importer then relies on the database to reject malformed rows. Promoting a brand-new shape to a validated core type is an additive `CHECK` migration — cheap, no table rewrite. See [A1](./QUESTIONS_ASSUMPTIONS.md#a-language-and-core-concepts) for the full reasoning, and [docs/csv-ingestion.md](./docs/csv-ingestion.md) for the concrete `CHECK` and transform SQL.

### 3. Experiment lineage cycle detection

Based on [C2](./QUESTIONS_ASSUMPTIONS.md#c-follow-up-experiments), the decision is whether to enforce acyclicity in the experiment predecessor graph at the database level, and if so, which mechanism to use.

---

- **Recursive CTE trigger**: On every `INSERT` or `UPDATE` to `predecessor_experiment_id`, walk the entire ancestor chain with a recursive CTE and reject if a cycle is detected. Full cycle detection, O(depth) per write, imposing read locks and full-tree traversal. **Why it was rejected:** The normal write path in a CSV ingestion workflow is append-only — retroactive lineage rewiring via `UPDATE` is an operational anomaly, not a routine operation. Paying the recursive traversal cost on every insert to guard against a mutation the workflow never performs is not justified.

- **Generation counter**: A `generation` integer column enforces `generation = predecessor.generation + 1` via a `BEFORE INSERT` trigger with a single predecessor lookup (O(1), not recursive), capped by a `CHECK` constraint. Any row that would create a cycle violates the monotonicity invariant. **Why it was deferred:** Under concurrent inserts targeting the same predecessor, the single-row lookup creates row-level lock contention — a real cost for a guard against UPDATE-based lineage rewiring that the append-only ingestion workflow does not perform.

- **[Chosen] `CHECK`-only deferral**: The `CHECK (predecessor_experiment_id <> id)` from [B2](./QUESTIONS_ASSUMPTIONS.md#b-defining-bound-of-project---experiments---measurement) blocks the one-hop self-reference case. Multi-hop cycle detection is deferred.

---

#### Accepted Trade-offs & Risks:

- **Silent multi-hop cycles under `UPDATE`**: An `UPDATE` that rewires `predecessor_experiment_id` retroactively (e.g., changing B's predecessor from A to C when A→C already exists) creates a multi-hop cycle the database will not catch. If the generation counter escape hatch is also active, the lineage becomes inconsistent with corrupted generation values.
- **Generation counter's own concurrency cost**: If the generation counter is activated, its `BEFORE INSERT` trigger introduces row-level lock contention on the predecessor row under concurrent inserts — a cost that is O(1) but not zero.

##### Mitigation Strategies:

The append-only nature of CSV ingestion over historical lab logs is the load-bearing assumption. If the workflow evolves to allow retroactive lineage edits, activate the generation counter (`BEFORE INSERT` trigger + `CHECK (generation < MAX_DEPTH)`) as the O(1) incremental guard. Reserve the recursive CTE trigger only if generation depth enforcement proves insufficient for the cycle patterns that emerge in practice.

### 2. Sample usage tracking: FK-only vs. `experiment_samples` join table

Based on [B4](./QUESTIONS_ASSUMPTIONS.md#b-defining-bound-of-project---experiments---measurement), the decision is whether to track which samples an experiment uses as a first-class relationship, or to derive it from the measurements that reference those samples.

---

- **`experiment_samples` join table approach**: An explicit `(experiment_id, sample_id)` association is recorded before any measurement is taken. Enforcing that `measurement.sample_id` belongs to the experiment becomes a trigger check against this table. **Why it was deferred:** It introduces a new first-class entity the problem statement never mentions, requires maintaining a pre-registration step in the CSV ingestion workflow, and enforcement still needs a cross-table trigger (not a simple `CHECK`) — adding write cost and complexity before a real workflow has proven the need.

- **[Chosen] FK-only approach**: `measurement.sample_id FK → samples.id` (nullable). The measurement row is the record that an experiment used a sample. No join table, no cross-table trigger.

---

#### Accepted Trade-offs & Risks:

- **Zero-measurement samples are invisible**: A sample placed into an experiment but destroyed or consumed before any measurement is collected will not appear in the experiment's audit trail. This is a real GxP traceability gap.
- **Semantic overloading**: "Sample used" is treated as synonymous with "sample that generated a measurement." Control samples and reagents that are inputs to the experiment but do not produce individual measurement rows are also invisible.
- **No scope guard**: The FK accepts any valid `samples.id` in the system. A CSV typo that references a sample from an unrelated project passes silently.
- **Query cost at scale**: Deriving sample usage via `SELECT DISTINCT sample_id FROM measurements WHERE experiment_id = X` becomes a bottleneck on high-frequency telemetry tables.

##### Mitigation Strategies:

If [D1](./QUESTIONS_ASSUMPTIONS.md#d-the-physical-vs-digital-nature-of-samples) confirms that samples can be consumed without generating measurements, introduce an `experiment_samples` associative table at that point — it is an additive migration, not a redesign. Until then, the FK-only model keeps CSV ingestion simple and avoids a join table the current scope does not justify.
