# LETS_GO: Lab Experiment Track System for Governance and Operations

## Project Summary

The system is a Laboratory Experiment Tracking System (LETS) to manage laboratory governance and operations. Created to solve this challange ([PROBLEM.md](./PROBLEM.md)) 

## OpenQuestions & Assumptions

To start this solutions I made a list questions and assumptions about the problem. You can see here: (QUESTIONs_ASSUMPTIONS.md)[./QUESTIONs_ASSUMPTIONS.md].


## Trade-offs & Decisions

### 0. Runtime context: CSV ingestion workflow

Based on [A0](./QUESTIONS_ASSUMPTIONS.md#a-language-and-core-concepts), I assume the first runtime context is a **CSV ingestion workflow for lab exports**, not a full web API or long-running application service.

This keeps the solution focused on what the challenge asks for: a Postgres data model, Docker startup, and seed data that prove the model works. The domain rules should live as close to the data as possible through tables, foreign keys, unique constraints, enums, and check constraints. Any CSV-specific parsing or row-shape validation can live in the ingestion step when that workflow is implemented.

Below is the rationale behind this choice and the trade-offs considered.

---

- **Web API Microservice Approach** : Build an HTTP API around the model, with request handlers, DTOs, service classes, authentication concerns, and validation in the application layer. **Why it was rejected:** The prompt asks for a database model that can be started with Docker and inspected live. Adding an API now would create more code to explain without proving the core model better.

- **Full Domain Application Layer Approach** : Build a DDD-style application layer with use cases, repositories, and schema validators before the database is exercised. **Why it was rejected:** The current ambiguity is mostly about domain invariants, not transport or orchestration. Capturing those invariants in the schema and documentation gives faster value and keeps the interview surface smaller.

- **[Chosen] CSV Ingestion Workflow Approach** : Treat the lab's current spreadsheet/export world as the input boundary. CSV rows are parsed and validated before insert, while Postgres remains the source of truth for relationships and durable constraints. See [docs/csv-ingestion.md](./docs/csv-ingestion.md) for the flat-CSV → JSONB transform seam that bridges this decision with the JSONB measurement model in [Decision 1](#1-measurements-the-jsonb-approach).

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

To solve this flexibility requirement, I chose to implement a **JSONB column (`data`)** within a unified `measurements` table to store the polymorphic payload, rather than relying on strict relational alternatives.

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

- **Validation must live somewhere explicit**: The structural checking that typed columns give for free has to be written by hand. Under [A0](./QUESTIONS_ASSUMPTIONS.md#a-language-and-core-concepts) there is no application layer to host it (no Zod/TypeScript request handler in the path), so it belongs in the database, next to the data the CSV importer writes.

##### Mitigation Strategies:

Enforce the payload contract with a Postgres `CHECK` on `value` that branches on `measurement_type`: assert the shape and `jsonb_typeof` of the known core types (a numeric reading must be a JSON `number`, a unit a JSON `string`), while staying permissive for not-yet-seen types so adopting a new technique still needs no migration. The CSV importer then relies on the database to reject malformed rows. Promoting a brand-new shape to a validated core type is an additive `CHECK` migration — cheap, no table rewrite. See [A1](./QUESTIONS_ASSUMPTIONS.md#a-language-and-core-concepts) for the full reasoning, and [docs/csv-ingestion.md](./docs/csv-ingestion.md) for the concrete `CHECK` and transform SQL.
