# LETS_GO

This is repos is a challenge/problem (described [here](./PROBLEM.md)) that I need to solve, first using DDD to document to document: 


- OpenQuestions & Assumptions: find the questions [here](./QUESTIONS_ASSUMPTIONS.md), 
- Trade-offs & Decisions: find the documented trade-off [here](./README.md#accepted-trade-offs--risks-).


## Who will read this project

An Software Engineer from [BitHippie](https://www.bithippie.com/team) company. This is very pragmatic and values ​​the deliberate simplicity that generates quick value. He hates over-engineering. Because of that, remember always use YAGNI to think before answer any prompt.


## About OpenQuestions & Assumptions

All questions should have three fields documented below each one of them:
- `[IMPACT]` — what design decision this forces
- `[ASSUMPTION]` — the chosen answer and its rationale
- `[ENFORCEMENT]` — how the database enforces it (per [A0](./QUESTIONS_ASSUMPTIONS.md#a-language-and-core-concepts): always the database, never application code)

Sometimes assumptions generate important trade-offs & decisions and should be documented in the README section.

All questions have a reference: A0, A1, B2, C2 … This is important for navigation between concepts and files.

## About Trade-offs & Decisions

All new trade-off & decision item should be documented with the same structure than [JSONB value](./README.md#0-runtime-context-csv-ingestion-workflow)

## Invariant: Never contradict A0

[A0](./QUESTIONS_ASSUMPTIONS.md#a-language-and-core-concepts) establishes that this system has **no application layer** — it is a CSV ingestion workflow. Every assumption, trade-off, and enforcement decision must be consistent with this: domain invariants live in the database (constraints, triggers, check constraints), not in application code (Zod, TypeScript, service classes). If a proposed assumption would require an app layer to enforce, reject it or reframe it as a database-level rule.





