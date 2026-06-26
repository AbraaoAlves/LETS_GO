# LETS_GO: Lab Experiment Track System for Governance and Operations

## Project Summary

The system is a Laboratory Experiment Tracking System (LETS) to manage laboratory governance and operations. Created to solve this challange ([PROBLEM.md](./PROBLEM.md)) 

## OpenQuestions & Assumptions

To start this solutions i made a list questions and assumptions about each one of them. You can see here: (QUESTIONs_ASSUMPTIONS.md)[./QUESTIONs_ASSUMPTIONS.md].



## Trade-offs & Decisions

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

#### Accepted Trade-offs & Risks : 

##### Mitigation Strategies:


