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

> [ASSUMPTION]: Both `completed` and `cancelled` freeze all descendant writes — no new experiments, no new measurements. Per [A0](#a-language-and-core-concepts), this is enforced at the database level (trigger or FK-based check), not in application code. The distinction between statuses is semantic only: `completed` signals successful conclusion, `cancelled` signals early termination. Both produce immutable records for audit and regulatory traceability, consistent with biotech governance (GxP/ALCOA+ principles where raw data is never overwritten after finalization).


B2. When an experiment is a 'follow-up' to a previous experiment, what exactly is it inheriting?
> Does it automatically target the same hypothesis or use the same samples? Is it a strict linear chain (Experiment A ->  B -> C), or can one failed experiment spawn three separate, parallel follow-up experiments?

> [IMPACT]    : 

> [ASSUMPTION]: 

B3. Must an experiment's dates fall within the project's lifecycle? Must `end_date ≥ start_date`?

> [IMPACT]    : 

> [ASSUMPTION]: 

B4. When a measurement "references the sample it was taken from," must that sample be one the experiment actually uses?

> [IMPACT]    : 

> [ASSUMPTION]: 

## C. Follow-up experiments

C1. Can a follow-up experiment belong to a *different* project than the one it follows?** (Replication often happens under a new grant.)

C2. Is the follow-up relationship a strict linear chain (A→B→C), or can one experiment spawn several parallel follow-ups? Are cycles ever valid?

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