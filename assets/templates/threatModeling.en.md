---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Threat modeling session
language: en
---

<!-- _class: title -->

# Threat modeling session
## System · Date · Facilitator · Participants

---

# Scope and goal

- Which system or component are we modeling today?
- What is explicitly out of scope: …
- Assumptions we are working with: …
- Outcome: weighted threats with mitigations and an owner

---

<!-- _class: table table-editable -->

# Mapping the system

| Element | Kind | Notes |
| --- | --- | --- |
| … | Component | … |
| … | Data flow | … |
| … | External party | … |

---

# Trust boundaries

- Where does data cross from trusted to untrusted?
- Which boundaries do we see: network, process, user, supply chain?
- Where do authentication and input validation happen?
- Draw every boundary on the system sketch: …

---

<!-- _class: table -->

# STRIDE reference

| Category | Meaning |
| --- | --- |
| Spoofing | Pretending to be another user or service |
| Tampering | Unauthorised modification of data or code |
| Repudiation | Denying that an action ever took place |
| Information disclosure | Information reaching those not allowed to see it |
| Denial of service | Making the system unusable or unreachable |
| Elevation of privilege | Gaining more privileges than granted |

---

<!-- _class: table table-editable -->

# Collecting threats

| Threat | STRIDE category | Component | Risk |
| --- | --- | --- | --- |
| … | … | … | … |
| … | … | … | … |
| … | … | … | … |

---

# Prioritising: likelihood × impact

- Likelihood: how probable is abuse (low, medium, high)?
- Impact: how much damage if it happens?
- Risk = likelihood × impact; high-high goes first
- In doubt: pick the higher estimate and note why

---

<!-- _class: table table-editable -->

# Mitigations and actions

| Mitigation | Owner | Status |
| --- | --- | --- |
| … | … | … |
| … | … | … |
| … | … | … |

---

# What we knowingly accept

- Which threats do we deliberately not address: …
- Why is that justified (likelihood, cost, context): …
- Who owns this decision: Role
- When do we revisit this: …

---

# Session complete
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Scope and assumptions recorded
- [ ] Components, data flows and external parties mapped
- [ ] Trust boundaries drawn
- [ ] All six STRIDE categories walked through
- [ ] Threats prioritised by likelihood × impact
- [ ] Mitigations assigned to an owner
- [ ] Accepted risks recorded and owned
