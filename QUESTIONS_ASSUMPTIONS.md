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

A2. When a sample is "divided into smaller vials," is that aliquoting — i.e., do you need parent→child sample lineage?

> [IMPACT]    : whether Sample needs a self-referencing genealogy and whether quantity is tracked — and, under [A0](#a-language-and-core-concepts), whether lineage integrity is enforced by the database rather than by import code.

> [ASSUMPTION]: support an optional `parent_sample_id` self-reference so lineage is representable. Per [A0](#a-language-and-core-concepts), its invariants live in the database: a self-referencing foreign key keeps every parent valid, and a `CHECK (parent_sample_id <> id)` blocks a sample from being its own parent. Deeper-tree rules (cycle prevention, generation limits) and quantity tracking are deferred until a real workflow needs them.


## B. Defining bound of Project <-> Experiments <-> Measurement:

B1. When a Project is marked as 'Completed' or 'Cancelled', what happens to its internal Experiments? Is still allowed inside it — adding a new experiment? logging a measurement on an experiment inside a cancelled?

> [IMPACT]    : Whether project status gates descendant writes, and whether the database enforces it or application code does.

> [ASSUMPTION]: Both `completed` and `cancelled` freeze all descendant writes — no new experiments, no new measurements. The distinction between statuses is semantic only: `completed` signals successful conclusion, `cancelled` signals early termination. Both produce immutable records for audit and regulatory traceability, consistent with biotech governance (GxP/ALCOA+ principles where raw data is never overwritten after finalization).

> [ENFORCEMENT]: `status` enum column on `project` (`active | completed | cancelled`). A trigger on `experiments` and `measurements` checks that the root project status is `active` before allowing an insert, per [A0](#a-language-and-core-concepts).


B2. When an experiment is a 'follow-up' to a previous experiment, what exactly is it inheriting?
> Does it automatically target the same hypothesis or use the same samples? Is it a strict linear chain (Experiment A ->  B -> C), or can one failed experiment spawn three separate, parallel follow-up experiments?

> [IMPACT]    : Whether `experiment` needs a self-referencing lineage edge and whether the shape is a linear chain or a DAG (one predecessor → many follow-ups).

> [ASSUMPTION]: A follow-up experiment inherits nothing automatically — the researcher manually sets up the new experiment, reusing the same samples or hypothesis at their discretion. "Follow-up" is a lineage pointer for traceability, not a content-copy mechanism. One experiment can spawn multiple parallel follow-ups (DAG, not a strict chain). A cancelled or completed experiment can be a valid predecessor — follow-ups on failed runs are a legitimate biotech workflow. Cycle prevention is deferred (YAGNI).

> [ENFORCEMENT]: Optional `predecessor_experiment_id FK → experiments.id` (NULL = original experiment). `CHECK (predecessor_experiment_id <> id)` blocks self-reference, per [A0](#a-language-and-core-concepts). No constraint on predecessor status — pointing to a `cancelled` experiment is allowed.

B3. Must an experiment's dates fall within the project's lifecycle? Must `end_date ≥ start_date`?

> [IMPACT]    : Whether the database needs to enforce date ordering (`end_date ≥ start_date`) and date containment (experiment dates within project bounds), and whether each requires a `CHECK` or a cross-table trigger.

> [ASSUMPTION]: `end_date ≥ start_date` is enforced — it is always true by definition and costs nothing. `end_date` is nullable (experiment still running). Project-date containment is **not** enforced: [B1](#b-defining-bound-of-project---experiments---measurement) already freezes writes once a project is `completed` or `cancelled`, which is the meaningful lifecycle boundary. Labs frequently don't know project end dates upfront, and requiring experiment dates to stay within project bounds would need a cross-table trigger for no additional regulatory value beyond the status gate.

> [ENFORCEMENT]: `CHECK (end_date IS NULL OR end_date >= start_date)` on `experiment`. No cross-table date-containment constraint — project lifecycle is enforced by the status trigger from [B1](#b-defining-bound-of-project---experiments---measurement), not by date comparisons, per [A0](#a-language-and-core-concepts).

B4. When a measurement "references the sample it was taken from," must that sample be one the experiment actually uses?

> [IMPACT]    : Whether `measurement.sample_id` must be constrained to samples formally registered to the experiment — implying an `experiment_samples` join table and a cross-table trigger — or whether a plain FK to `samples` is sufficient.

> [ASSUMPTION]: A plain FK is sufficient for this MVP. The measurement row is the record that an experiment used a sample — no prior registration step is needed. However, this model carries a known semantic assumption: **"sample used" is synonymous with "sample that generated a measurement."** This breaks in three real scenarios: (1) a sample is consumed or destroyed before any measurement is collected — it simply disappears from the experiment's audit trail; (2) control samples or reagents are inputs to the experiment but never produce an individual measurement row; (3) a typo in a CSV row can silently associate a sample from an unrelated project, since the FK accepts any valid `samples.id` with no scope guard. Additionally, `SELECT DISTINCT sample_id FROM measurements WHERE experiment_id = X` becomes a read bottleneck on high-frequency telemetry tables. If [D1](#d-the-physical-vs-digital-nature-of-samples) confirms that samples can be consumed without generating measurements, an `experiment_samples` associative table becomes necessary — that is the extension path. `sample_id` is nullable — see [E2](#e-the-semantics-of-measurements) for the case where a measurement has no sample at all.

> [ENFORCEMENT]: `sample_id FK → samples.id` (nullable) on `measurement`. No `experiment_samples` join table and no cross-table containment trigger, per [A0](#a-language-and-core-concepts). See [Decision 2](./README.md#2-sample-usage-tracking-fk-only-vs-experiment_samples-join-table) for the accepted trade-offs.

## C. Follow-up experiments

C1. Can a follow-up experiment belong to a *different* project than the one it follows? (Replication often happens under a new grant.)

> [IMPACT]    : Whether `predecessor_experiment_id` needs a same-project guard trigger on top of the FK established in [B2](#b-defining-bound-of-project---experiments---measurement).

> [ASSUMPTION]: Cross-project follow-ups are allowed. `project_id` is an administrative and funding boundary; scientific lineage (`predecessor_experiment_id`) is orthogonal — replication under a new grant, a spin-off collaboration, or a follow-on study are all legitimate predecessor chains that cross project lines. The problem statement never asserts same-project restriction, so no trigger is warranted.

> [ENFORCEMENT]: The `predecessor_experiment_id FK → experiments.id` from [B2](#b-defining-bound-of-project---experiments---measurement) is sufficient — it guarantees the predecessor exists. No cross-table same-project trigger, per [A0](#a-language-and-core-concepts).

C2. Is the follow-up relationship a strict linear chain (A→B→C), or can one experiment spawn several parallel follow-ups? Are cycles ever valid?

> [IMPACT]    : Whether a cycle-detection trigger is needed on top of the self-reference `CHECK` from [B2](#b-defining-bound-of-project---experiments---measurement).

> [ASSUMPTION]: Parallel follow-ups (DAG) are established by [B2](#b-defining-bound-of-project---experiments---measurement) — one experiment can spawn multiple follow-ups, and a strict linear chain is not required. Cycles are semantically invalid in this context: the problem statement describes historical lab log imports, not iterative pipelines where re-running the original experiment under new conditions is a routine workflow step. The realistic risk vector is an **UPDATE** to `predecessor_experiment_id` that retroactively rewires lineage and creates a multi-hop loop — not an ordinary INSERT. In a CSV ingestion workflow over historical lab logs, the experiment inheritance structure is effectively append-only: once a row is imported, its lineage pointer does not change. Retroactive modifications to an experiment's predecessor are operational anomalies, not routine writes. A recursive CTE trigger would impose read locks and full-tree traversal on every write to guard against a class of mutation that the normal workflow never performs. That cost is not justified. The one-hop case is already blocked by B2's `CHECK (predecessor_experiment_id <> id)`. If lineage depth needs enforcing, a `generation` integer column (`generation = predecessor.generation + 1`, capped by a `CHECK`) is the O(1) escape hatch — it requires a `BEFORE INSERT` trigger with a single predecessor lookup (not recursive), which introduces row-level lock contention on the predecessor row under concurrent inserts but is the accepted cost of O(1) depth enforcement. See [Decision 3](./README.md#3-experiment-lineage-cycle-detection).

> [ENFORCEMENT]: The `CHECK (predecessor_experiment_id <> id)` from [B2](#b-defining-bound-of-project---experiments---measurement) covers direct self-reference. No recursive cycle-detection trigger, per [A0](#a-language-and-core-concepts).

C3. Is "follow-up" really just an experiment-to-experiment edge, or the shadow of a missing concept (a "study," "line of inquiry," or "research thread")?


## D. The Physical vs. Digital Nature of "Samples"

D1. Are these samples physical resources that get consumed, altered, or depleted during an experiment?

> If a sample is a chemical compound and an experiment uses 50ml of it, the system needs to track 'quantity' and 'state changes'. If it's a soil sample that remains intact after a visual scan, it's treated differently. If it's a blood sample that gets divided into smaller vials, we are dealing with a parent-child genealogy of samples.




## E. The Semantics of "Measurements"

E1. Once a measurement is recorded, can it ever be edited or deleted, or is it an immutable historical record?

E2. Does a measurement always require a sample, or can it be an observation of the experiment as a whole? 


## F. About Roles

F1. Are these roles purely for identity and access management (e.g., who can log into the system), or do they dictate critical domain business logic? For example, does an experiment lifecycle require a Principal Investigator to sign off on a Graduate Student’s hypothesis before it can move from "planning" to "active"?

> The "Role" of Researcher: The document notes that the lab tracks names, contact details, and roles (principal investigators, lab technicians, graduate students), but not say if that info will be used for something else. 