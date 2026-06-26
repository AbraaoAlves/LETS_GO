# LETS_GO: Lab Experiment Track System for Governance and Operations

## Project Summary

The system is a Laboratory Experiment Tracking System (LETS) to manage laboratory governance and operations. Created to solve this challange ([PROBLEM.md](./PROBLEM.md)) 

## OpenQuestions & Assumptions

To start this solutions i made a list questions and assumptions about each one of them. You can see here: (QUESTIONs_ASSUMPTIONS.md)[./QUESTIONs_ASSUMPTIONS.md].



## Trade-offs & Decisions

### 1. Measurements: The JSONB approach

My first design decisions in this system revolves around how to store `Measurements`. The requirements state that measurements can take several forms and that **new kinds of measurements are added occasionally** as the lab adopts new techniques.

To solve this flexibility requirement, I chose to implement a **JSONB column (`data`)** within a unified `measurements` table to store the polymorphic payload, rather than relying on strict relational alternatives.

Below is the rationale behind this choice and the trade-offs considered.

---

- **Classic Relation Approach** : 

- **Entity-Attribute-Value (EAV) Approach** :

- **[Chosen] JSONB Polymorphism Approach** :

--- 

#### Advantages:

#### Accepted Trade-offs & Risks : 

##### Mitigation Strategies:


