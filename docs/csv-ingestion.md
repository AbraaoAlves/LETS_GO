# CSV ingestion: flat rows → validated JSONB

This note documents the transform seam that connects two decisions:

- **[A0](../QUESTIONS_ASSUMPTIONS.md#a-language-and-core-concepts) / [Decision 0](../README.md#0-runtime-context-csv-ingestion-workflow)** — the runtime is a CSV ingestion workflow, so invariants live in the database, not an app layer.
- **[A1](../QUESTIONS_ASSUMPTIONS.md#a-language-and-core-concepts) / [Decision 1](../README.md#1-measurements-the-jsonb-approach)** — a measurement's value is a polymorphic `JSONB` payload, validated by a type-aware `CHECK`.

The gap between them: a CSV export is **flat text columns**, not JSON. Something has to build the JSONB payload and prove it is well-typed before it lands in `measurements`. With no application layer (A0), that "something" is SQL.

This is deliberately a *sketch*, not a full importer spec — column mapping, required-column rules, and row-level error reporting stay deferred per A0 until real production files justify them.

## The transform

Load the flat CSV into a session-scoped `TEMP` table, then `INSERT ... SELECT` into `measurements`, building the payload with `jsonb_build_object`:

```sql
-- per-load, session-scoped, auto-dropped at session end
CREATE TEMP TABLE staging_measurements (
  measurement_type text,
  numeric_value    text,   -- everything arrives as text from CSV
  unit             text,
  categorical_value text,
  note             text
);

\copy staging_measurements FROM 'export.csv' WITH (FORMAT csv, HEADER true)

INSERT INTO measurements (measurement_type, value)
SELECT
  measurement_type,
  CASE measurement_type
    WHEN 'numeric' THEN jsonb_build_object('value', numeric_value::numeric, 'unit', unit)
    WHEN 'categorical' THEN jsonb_build_object('value', categorical_value)
    WHEN 'text'    THEN jsonb_build_object('note',  note)
    ELSE              to_jsonb(note)    -- unknown type: pass the raw payload through
  END
FROM staging_measurements;
```

### The cast is the first validation gate

The `::numeric` cast *inside* `jsonb_build_object` does double duty:

1. It coerces text → number, so the stored value is a genuine JSON number (`jsonb_typeof = 'number'`), which is exactly what the `CHECK` asserts.
2. It is where a garbage value such as `"12.x"` is rejected — with a clear Postgres error, at the transform, before it ever reaches the table.

So bad data is caught in two places: the **cast** (right type?) and then the **CHECK** (right shape?).

### This TEMP table is not the deferred staging table

A0's mitigation defers a *durable staging + error-report* table for triaging bad production files. The `TEMP` table here is a different thing: an ephemeral transform buffer that drops at session end and adds zero ongoing infrastructure. No contradiction with A0.

## The type-aware CHECK

Shape validation lives on `measurements` as a single `CHECK` that branches on `measurement_type`:

```sql
ALTER TABLE measurements ADD CONSTRAINT measurements_value_shape CHECK (
  CASE measurement_type
    WHEN 'numeric' THEN jsonb_typeof(value->'value') = 'number'
                    AND jsonb_typeof(value->'unit')  = 'string'
    WHEN 'categorical' THEN jsonb_typeof(value->'value') = 'string'
    WHEN 'text'    THEN jsonb_typeof(value->'note')  = 'string'
    ELSE TRUE   -- unknown type: accept any payload, no migration
  END IS TRUE
);
```

The final `IS TRUE` matters: PostgreSQL `CHECK` constraints accept `NULL`, so a missing JSON key
must be forced to `FALSE`, not allowed to drift through as unknown.

### `ELSE TRUE` keeps new techniques migration-free

Adopting a measurement type the CHECK has never seen does not fail — the `ELSE TRUE` branch accepts any payload. The database still validates the types it knows, while staying open to the ones it doesn't. This is what A1 means by "permissive for not-yet-seen types."

### The discriminator must be a column on the row

A `CHECK` can only reference columns on its **own row** — it cannot reach through a join. So `measurement_type` has to be a **stable text code stored on `measurements`**, not just a `measurement_type_id` pointing at a lookup table (you cannot branch a `CASE` on an opaque id). The clean shape: a `measurement_types` registry table, with `measurements.measurement_type` a text foreign key into it.

### Registering a type and validating its shape are decoupled

This split is the payoff of the whole approach:

| Action | Cost | When |
| --- | --- | --- |
| **Register a new type** | one `INSERT` into `measurement_types` — data, no migration | every time the lab adopts a technique |
| **Enforce its shape** | one additive `WHEN` branch on the `CHECK` — a cheap migration, no table rewrite | only when a type is common enough to be worth hardening |

So "new types need no migration" holds. You pay a (small, additive) migration only when you *choose* to harden a type — never just to start recording it.

## Fixture key contract

The challenge fixtures do not depend on generated database IDs. They use stable CSV keys and
TEMP staging tables to resolve relationships:

| CSV | Relationship key |
| --- | --- |
| `researchers` | `email` |
| `projects` | `title` |
| `project_researchers` | `project_title`, `researcher_email` |
| `samples` | `sample_code`, optional `parent_sample_code` |
| `experiments` | `project_title`, `title`, optional predecessor pair |
| `measurements` | `experiment_project_title`, `experiment_title`, optional `sample_code` |

Required missing references land in `NOT NULL`/FK failures. Optional references treat blank as
`NULL`; nonblank missing references use an impossible FK value so bad rows are not silently
filtered away.
