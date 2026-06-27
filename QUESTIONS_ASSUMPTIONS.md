# Questions

Before drawing tables or setting up Docker containers. I need to look at this problem not as a data storage problem, but as a living, breathing domain model.
In my experience, when software projects fail, it's rarely because of the technology; it's because the team built a beautifully optimized database schema for a domain they didn't actually understand.

To uncover the **business rules (invariants)** that govern THE operation of this lab, I wrote these **OpenQuestions**. 
Feel free to give me your thoughts.

## A. Language and core concepts

A0. Which context this system will be used? A integration data pipeline microservice, web api, cli, or just a single script to import and validate a csv content file?

> [IMPACT]    : Where rules should be living? App layer, database or both?

> [ASSUMPTION]: it is a CSV ingestion workflow for lab exports.

A1. Is "measurement" one concept, or is it hiding several (raw reading vs. interpreted result vs. free-text observation)?

> [IMPACT]    : whether the model is one polymorphic Measurement or split entities — and, given [A0](#a-language-and-core-concepts), where its type rules live. With no application layer, the JSONB payload must be validated by the database itself.

> [ASSUMPTION]: one `measurement` is a single entity carrying a typed value, classified by a first-class `measurement_type` and a `value JSONB`. New types that reuse an existing payload shape need no migration, keeping the door open for new techniques. To honor [A0](#a-language-and-core-concepts) (invariants live in the database, not an app layer), the JSONB risk noted in [Decision 1](./README.md#1-measurements-the-jsonb-approach) is recovered with a Postgres `CHECK` on `value` that branches on `measurement_type`: it asserts the payload shape and `jsonb_typeof` of the known core types (a numeric reading must be a JSON `number`, a unit must be a JSON `string`) while staying permissive for not-yet-seen types. The CSV importer then relies on the database to reject malformed rows. Promoting a brand-new shape to a validated core type is an additive `CHECK` migration — cheap, no table rewrite — not a table redesign.

> [RISKS]:
> - **Unknown types bypass payload validation**: the `CHECK` asserts shape and `jsonb_typeof` only for known core types and stays permissive for not-yet-seen `measurement_type`s. A new type can therefore be ingested with a malformed payload — a numeric reading stored as the JSON string `"5.0"` instead of the number `5.0`, or a missing unit — and the database accepts it. The defect stays invisible until the shape is promoted to a validated core type or an aggregation query trips over the wrong `jsonb_typeof`. This is the accepted cost of adding types without migrations; the guard is promoting recurring shapes to core types early, at the data source under [A0](#a-language-and-core-concepts), not in absent app code.

A2. When a sample is "divided into smaller vials," is that aliquoting — i.e., do you need parent→child sample lineage?

> [IMPACT]    : whether Sample needs a self-referencing genealogy and whether quantity is tracked — and, under [A0](#a-language-and-core-concepts), whether lineage integrity is enforced by the database rather than by import code.

> [ASSUMPTION]: support an optional `parent_sample_id` self-reference so lineage is representable. Per [A0](#a-language-and-core-concepts), its invariants live in the database: a self-referencing foreign key keeps every parent valid, and a `CHECK (parent_sample_id <> id)` blocks a sample from being its own parent. Deeper-tree rules (cycle prevention, generation limits) and quantity tracking are deferred until a real workflow needs them.

> [RISKS]:
> - **Multi-hop aliquot cycles undetected**: `CHECK (parent_sample_id <> id)` blocks only a sample being its own direct parent. A multi-hop loop (A → B → C → A) introduced by an `UPDATE` to `parent_sample_id` is not caught, and a recursive CTE walking the lineage would not terminate. This mirrors the experiment-lineage risk in [C2](#c-follow-up-experiments) and is accepted for the same reason: CSV ingestion over historical logs is effectively append-only, so retroactive re-parenting is an operational anomaly, not a normal write. The O(1) escape hatch is the same `generation` counter described in [C2](#c-follow-up-experiments).


## B. Defining bound of Project <-> Experiments <-> Measurement:

B1. When a Project is marked as 'Completed' or 'Cancelled', what happens to its internal Experiments? Is still allowed inside it — adding a new experiment? logging a measurement on an experiment inside a cancelled?

> [IMPACT]    : Whether project status gates descendant writes, and whether the database enforces it or application code does.

> [ASSUMPTION]: Both `completed` and `cancelled` freeze all descendant writes — no new experiments, no new measurements. The distinction between statuses is semantic only: `completed` signals successful conclusion, `cancelled` signals early termination. Both produce immutable records for audit and regulatory traceability, consistent with biotech governance (GxP/ALCOA+ principles where raw data is never overwritten after finalization).

> [ENFORCEMENT]: `status` enum column on `project` (`active | completed | cancelled`). A trigger on `experiments` and `measurements` checks that the root project status is `active` before allowing an insert, per [A0](#a-language-and-core-concepts).


B2. When an experiment is a 'follow-up' to a previous experiment, what exactly is it inheriting?
> Does it automatically target the same hypothesis or use the same samples? Is it a strict linear chain (Experiment A ->  B -> C), or can one failed experiment spawn three separate, parallel follow-up experiments?

> [IMPACT]    : Whether `experiment` needs a self-referencing lineage edge and whether the shape is a linear chain or a DAG (one predecessor → many follow-ups).

> [ASSUMPTION]: A follow-up experiment inherits nothing automatically — the researcher manually sets up the new experiment, reusing the same samples or hypothesis at their discretion. "Follow-up" is a lineage pointer for traceability, not a content-copy mechanism. One experiment can spawn multiple parallel follow-ups (DAG, not a strict chain). A cancelled or completed experiment can be a valid predecessor — follow-ups on failed runs are a legitimate biotech workflow. Multi-hop cycle detection is addressed in [C2](#c-follow-up-experiments).

> [ENFORCEMENT]: Optional `predecessor_experiment_id FK → experiments.id` (NULL = original experiment). `CHECK (predecessor_experiment_id <> id)` blocks self-reference, per [A0](#a-language-and-core-concepts). No constraint on predecessor status — pointing to a `cancelled` experiment is allowed.

B3. Must an experiment's dates fall within the project's lifecycle? Must `end_date ≥ start_date`?

> [IMPACT]    : Whether the database needs to enforce date ordering (`end_date ≥ start_date`) and date containment (experiment dates within project bounds), and whether each requires a `CHECK` or a cross-table trigger.

> [ASSUMPTION]: `end_date ≥ start_date` is enforced — it is always true by definition and costs nothing. `end_date` is nullable (experiment still running). Project-date containment is **not** enforced: [B1](#b-defining-bound-of-project---experiments---measurement) already freezes writes once a project is `completed` or `cancelled`, which is the meaningful lifecycle boundary. Labs frequently don't know project end dates upfront, and requiring experiment dates to stay within project bounds would need a cross-table trigger for no additional regulatory value beyond the status gate.

> [ENFORCEMENT]: `CHECK (end_date IS NULL OR end_date >= start_date)` on `experiment`. No cross-table date-containment constraint — project lifecycle is enforced by the status trigger from [B1](#b-defining-bound-of-project---experiments---measurement), not by date comparisons, per [A0](#a-language-and-core-concepts).

B4. When a measurement "references the sample it was taken from," must that sample be one the experiment actually uses?

> [IMPACT]    : Whether `measurement.sample_id` must be constrained to samples formally registered to the experiment — implying an `experiment_samples` join table and a cross-table trigger — or whether a plain FK to `samples` is sufficient.

> [ASSUMPTION]: A plain FK is sufficient for this MVP. The measurement row is the record that an experiment used a sample — no prior registration step is needed. This rests on a known semantic assumption: **"sample used" is synonymous with "sample that generated a measurement"** — the cases where that breaks, and the read-path cost, are in [RISKS] below. If [D1](#d-the-physical-vs-digital-nature-of-samples) confirms that samples can be consumed without generating measurements, an `experiment_samples` associative table becomes necessary — that is the extension path. `sample_id` is nullable — see [E2](#e-the-semantics-of-measurements) for the case where a measurement has no sample at all.

> [ENFORCEMENT]: `sample_id FK → samples.id` (nullable) on `measurement`. No `experiment_samples` join table and no cross-table containment trigger, per [A0](#a-language-and-core-concepts). See [Decision 2](./README.md#2-sample-usage-tracking-fk-only-vs-experiment_samples-join-table) for the accepted trade-offs.

> [RISKS]:
> - **Consumed-before-measured samples vanish from the audit trail**: a sample destroyed or fully consumed before any reading is taken produces no `measurement` row, so there is no evidence the experiment ever touched it.
> - **Inputs without a measurement are invisible**: control samples and reagents are genuine experiment inputs that never generate an individual measurement row, so FK-as-usage-record cannot represent them.
> - **No project scope guard**: the FK accepts any valid `samples.id`, so a CSV typo can silently link a sample from an unrelated project. A cross-table containment trigger would close this but is declined per [A0](#a-language-and-core-concepts); see [Decision 2](./README.md#2-sample-usage-tracking-fk-only-vs-experiment_samples-join-table).
> - **Sample enumeration is a read bottleneck**: `SELECT DISTINCT sample_id FROM measurements WHERE experiment_id = X` is the only way to list an experiment's samples and degrades on high-frequency telemetry tables. The `experiment_samples` table is the fix when [D1](#d-the-physical-vs-digital-nature-of-samples) forces it.

## C. Follow-up experiments

C1. Can a follow-up experiment belong to a *different* project than the one it follows? (Replication often happens under a new grant.)

> [IMPACT]    : Whether `predecessor_experiment_id` needs a same-project guard trigger on top of the FK established in [B2](#b-defining-bound-of-project---experiments---measurement).

> [ASSUMPTION]: Cross-project follow-ups are allowed. `project_id` is an administrative and funding boundary; scientific lineage (`predecessor_experiment_id`) is orthogonal — replication under a new grant, a spin-off collaboration, or a follow-on study are all legitimate predecessor chains that cross project lines. The problem statement never asserts same-project restriction, so no trigger is warranted.

> [ENFORCEMENT]: The `predecessor_experiment_id FK → experiments.id` from [B2](#b-defining-bound-of-project---experiments---measurement) is sufficient — it guarantees the predecessor exists. No cross-table same-project trigger, per [A0](#a-language-and-core-concepts).

C2. Is the follow-up relationship a strict linear chain (A→B→C), or can one experiment spawn several parallel follow-ups? Are cycles ever valid?

> [IMPACT]    : Whether a cycle-detection trigger is needed on top of the self-reference `CHECK` from [B2](#b-defining-bound-of-project---experiments---measurement).

> [ASSUMPTION]: Parallel follow-ups (DAG) are established by [B2](#b-defining-bound-of-project---experiments---measurement) — one experiment can spawn multiple follow-ups, and a strict linear chain is not required. Cycles are semantically invalid in this context: the problem statement describes historical lab log imports, not iterative pipelines where re-running the original experiment under new conditions is a routine workflow step. The realistic risk vector is an **UPDATE** to `predecessor_experiment_id` that retroactively rewires lineage and creates a multi-hop loop — not an ordinary INSERT. In a CSV ingestion workflow over historical lab logs, the experiment inheritance structure is effectively append-only: once a row is imported, its lineage pointer does not change. Retroactive modifications to an experiment's predecessor are operational anomalies, not routine writes. A recursive CTE trigger would impose read locks and full-tree traversal on every write to guard against a class of mutation that the normal workflow never performs. That cost is not justified. The one-hop case is already blocked by B2's `CHECK (predecessor_experiment_id <> id)`. If lineage depth needs enforcing, a `generation` integer column (`generation = predecessor.generation + 1`, capped by a `CHECK`) is the O(1) escape hatch — it requires a `BEFORE INSERT` trigger with a single predecessor lookup (not recursive), which introduces row-level lock contention on the predecessor row under concurrent inserts but is the accepted cost of O(1) depth enforcement. See [Decision 3](./README.md#3-experiment-lineage-cycle-detection).

> [ENFORCEMENT]: The `CHECK (predecessor_experiment_id <> id)` from [B2](#b-defining-bound-of-project---experiments---measurement) covers direct self-reference. No recursive cycle-detection trigger, per [A0](#a-language-and-core-concepts).

> [RISKS]:
> - **Multi-hop lineage cycles via UPDATE**: the self-reference `CHECK` stops a one-hop loop, but a multi-hop cycle (A → B → C → A) created by an `UPDATE` to `predecessor_experiment_id` is not detected, and a recursive ancestor/descendant query would not terminate. Accepted because the inheritance structure is append-only in a historical-log import — retroactive re-wiring is an operational anomaly, not a routine write — and a recursive CTE trigger would lock and traverse the whole tree on every insert. If depth ever needs bounding, the O(1) `generation` counter is the escape hatch. See [Decision 3](./README.md#3-experiment-lineage-cycle-detection).

C3. Is "follow-up" really just an experiment-to-experiment edge, or the shadow of a missing concept (a "study," "line of inquiry," or "research thread")?

> [IMPACT]    : Whether a first-class `study` / `research_thread` entity is needed between `project` and `experiment` to group experiments sharing a scientific question even when they share no direct lineage edge.

> [ASSUMPTION]: "Follow-up" is just a lineage edge — no missing concept. `project` is the administrative grouping; `predecessor_experiment_id` is the scientific lineage pointer. A "study" entity would require its own table, a new FK on `experiment`, and lifecycle rules — none of which the problem statement names or implies. The DAG built from `predecessor_experiment_id` already lets a researcher navigate to all ancestors and descendants of any experiment. If thematic grouping across unrelated lineage chains ever matters, `project` is the natural placeholder until a real workflow proves the need for a finer-grained grouping entity.

> [ENFORCEMENT]: No new table. The `predecessor_experiment_id FK → experiments.id` from [B2](#b-defining-bound-of-project---experiments---measurement) is the complete model.


## D. The Physical vs. Digital Nature of "Samples"

D1. Are these samples physical resources that get consumed, altered, or depleted during an experiment?

> If a sample is a chemical compound and an experiment uses 50ml of it, the system needs to track 'quantity' and 'state changes'. If it's a soil sample that remains intact after a visual scan, it's treated differently. If it's a blood sample that gets divided into smaller vials, we are dealing with a parent-child genealogy of samples.

> [IMPACT]    : Whether `sample` needs a `quantity` column, a `state` enum (`intact | consumed | degraded | depleted`), and depletion-tracking logic, or whether it is a reference entity with no live inventory semantics.

> [ASSUMPTION]: Samples are immutable reference entities — named, typed, optionally linked by parent lineage ([A2](#a-language-and-core-concepts)), but not tracked for quantity or state changes. The problem statement describes samples as things experiments reference; it never names inventory management, depletion tracking, or state transitions. Under [A0](#a-language-and-core-concepts) (CSV ingestion of historical lab logs), the import records what samples were used, not how much was consumed or what physical state they were in at each step. The operational risks this accepts are listed in [RISKS] below; both are accepted because the scope is a historical log import, not a real-time operational system.

> [ENFORCEMENT]: No `quantity` column, no `state` enum on `sample`. The `parent_sample_id FK → samples.id` from [A2](#a-language-and-core-concepts) covers aliquoting lineage. `measurement.sample_id FK → samples.id` from [B4](#b-defining-bound-of-project---experiments---measurement) is the record of sample usage, per [A0](#a-language-and-core-concepts). Extension paths if the workflow evolves: add a `status` enum (`active | depleted | destroyed`) to `sample` for lifecycle tracking; introduce a `sample_location_history` child table for chain-of-custody auditing rather than mutating the `storage_location` field.

> [RISKS]:
> - **Phantom-linkable samples**: a sample consumed, destroyed, or disposed of in the physical world still appears linkable in the database — no status guard stops a researcher from associating discarded bio-waste with a new experiment. The same holds after aliquoting ([A2](#a-language-and-core-concepts)): a parent fully fractionated into child vials remains a valid reference target though it no longer physically exists in its original form. Extension path: a `status` enum (`active | depleted | destroyed`) on `sample`.
> - **Chain-of-custody gap on `storage_location`**: the field is a point-in-time snapshot from the CSV import, so any later move — freezer rotation, bench work, disposal — is invisible, which matters in regulated environments. Extension path: a `sample_location_history` child table rather than mutating `storage_location` in place.




## E. The Semantics of "Measurements"

E1. Once a measurement is recorded, can it ever be edited or deleted, or is it an immutable historical record?

> [IMPACT]    : Whether `measurement` allows corrections (`UPDATE`), removals (`DELETE`), soft-delete (`deleted_at`), versioning (`superseded_by FK`), or an audit log — and whether researcher-level corrections are a first-class workflow.

> [ASSUMPTION]: Measurements are immutable historical records once ingested. The problem statement frames this as a historical lab log import ([A0](#a-language-and-core-concepts)) — the CSV import is the authoritative write event, and the measurement row is the permanent record of what was observed. This closes the same logic as [B1](#b-defining-bound-of-project---experiments---measurement): ALCOA+ principles (raw data is never overwritten after finalization) apply to individual measurement rows, not just to the project lifecycle. [B1](#b-defining-bound-of-project---experiments---measurement)'s trigger blocks new inserts on non-active projects but does not prevent `UPDATE` or `DELETE` on rows that already exist — E1 fills that gap. If a row was imported with a wrong value, that is a DBA-level correction, not a routine researcher workflow; it does not belong in the schema.

> [ENFORCEMENT]: A trigger on `measurement` that raises an exception on any `UPDATE` or `DELETE`, per [A0](#a-language-and-core-concepts). No `deleted_at` column, no `superseded_by FK`, no audit log table. The immutability of the project record ([B1](#b-defining-bound-of-project---experiments---measurement)) and the immutability of its measurement rows (E1) are the same invariant expressed at two levels.

> [RISKS]:
> - **Corrections leave no trace**: a row imported with a wrong value cannot be fixed through any schema-sanctioned path — the trigger blocks `UPDATE` and `DELETE`, and there is no `superseded_by` version chain or audit-log table. The only remedy is an out-of-band DBA action (disable the trigger, edit, re-enable), which mutates finalized data with no record of who changed what or why. That is itself an ALCOA+ gap: immutability is preserved at the cost of traceable, attributable corrections. Accepted because corrections are rare DBA events, not a researcher workflow; if they become routine, the extension path is a `superseded_by FK` version chain rather than in-place edits, keeping the original row intact.

E2. Does a measurement always require a sample, or can it be an observation of the experiment as a whole?

> [IMPACT]    : Whether `measurement.sample_id` is nullable or required — and whether experiment-level observations (environmental readings, equipment calibrations, whole-run outcomes) need a separate entity or fit in the unified `measurement` table.

> [ASSUMPTION]: A measurement does not always require a sample. Experiment-level observations — ambient temperature during a run, equipment calibration baselines, whole-experiment outcome notes — are legitimate measurement rows with no sample reference. A second entity (`experiment_observation`) would duplicate the type/value/experiment structure already in `measurement` for no modelling gain. This is already pre-decided: [B4](#b-defining-bound-of-project---experiments---measurement) declared `sample_id` nullable precisely for this case. E2 names the semantic justification — `sample_id IS NULL` means "this measurement describes the experiment context, not a specific sample."

> [ENFORCEMENT]: The nullable `sample_id FK → samples.id` from [B4](#b-defining-bound-of-project---experiments---measurement) is the complete model. No additional constraint. No separate entity, per [A0](#a-language-and-core-concepts).


## F. About Roles

F1. Are these roles purely for identity and access management (e.g., who can log into the system), or do they dictate critical domain business logic? For example, does an experiment lifecycle require a Principal Investigator to sign off on a Graduate Student’s hypothesis before it can move from "planning" to "active"?

> The "Role" of Researcher: The document notes that the lab tracks names, contact details, and roles (principal investigators, lab technicians, graduate students), but not say if that info will be used for something else.

> [IMPACT]    : Whether `researcher.role` drives workflow gates, database access policies, or is purely a descriptive attribute — and whether the schema links researchers to the scientific records they produce.

> [ASSUMPTION]: `role` is researcher metadata, not an IAM control or workflow gate. Under [A0](#a-language-and-core-concepts), there is no authenticated session, no approval queue, and no state machine — nothing to attach role-based access or sign-off logic to. The problem statement lists principal investigator, lab technician, and graduate student as attributes of the people the lab tracks; it never names an approval workflow or permission boundary. `role` is implemented as a Postgres enum (`principal_investigator | lab_technician | graduate_student`); adding a new role (postdoc, lab manager) requires `ALTER TYPE ... ADD VALUE` — additive, no table rewrite, the same category of cost as promoting a new measurement type in [A1](#a-language-and-core-concepts).

> [ENFORCEMENT]: A `role` enum on the `researcher` table. `experiment` and `measurement` carry a `researcher_id FK → researchers.id` — the researcher who ran the experiment or recorded the measurement — which is what makes role queryable against scientific records ("find all measurements recorded by a PI"). No row-level security policies, no sign-off trigger, no state machine, per [A0](#a-language-and-core-concepts).

> [RISKS]:
> - **Attribution gap (ALCOA+)**: The database cannot validate personnel compliance violations originating from the CSV — if a row records a graduate student completing a project that lab regulations require a PI to sign off on, the import succeeds silently. Under [A0](#a-language-and-core-concepts), governance validation belongs at the data source or pre-processing pipeline, not in the database core.
> - **Enum migration cost**: Adding a new role requires `ALTER TYPE ... ADD VALUE`. If the team structure is highly dynamic, the natural extension path is a `roles` lookup table.