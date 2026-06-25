# Questions

Before drawing tables or setting up Docker containers. I need to look at this problem not as a data storage problem, but as a living, breathing domain model.
In my experience, when software projects fail, it's rarely because of the technology; it's because the team built a beautifully optimized database schema for a domain they didn't actually understand.

To uncover the **business rules (invariants)** that govern THE operation of this lab, I wrote these **OpenQuestions**. 
Feel free to give me your thoughts.

## A. Language and core concepts

A1. Is "measurement" one concept, or is it hiding several (raw reading vs. interpreted result vs. free-text observation)?

A2. When a sample is "divided into smaller vials," is that aliquoting — i.e., do you need parent→child sample lineage?


## B. Defining bound of Project <-> Experiments <-> Measurement:

B1. When a Project is marked as 'Completed' or 'Cancelled', what happens to its internal Experiments? Is still allowed inside it — adding a new experiment? logging a measurement on an experiment inside a cancelled?

B2. When an experiment is a 'follow-up' to a previous experiment, what exactly is it inheriting?
> Does it automatically target the same hypothesis or use the same samples? Is it a strict linear chain (Experiment A ->  B -> C), or can one failed experiment spawn three separate, parallel follow-up experiments?

B3. Must an experiment's dates fall within the project's lifecycle? Must `end_date ≥ start_date`?

B4. When a measurement "references the sample it was taken from," must that sample be one the experiment actually uses?

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