---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Business continuity / DR test
language: en
---

<!-- _class: title -->

# Business continuity / DR test

---

# Test scenario

- Scenario: … (e.g. data center outage, ransomware)
- Assumption beforehand: …
- Test type: tabletop / partial / full

---

# Objectives and success criteria

- Objective of the test: …
- Success criterion 1: …
- Success criterion 2: …

---

<!-- _class: table table-editable -->

# Critical processes

| Process | Priority | Depends on |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

<!-- _class: table table-editable -->

# RTO / RPO overview

| Process or system | RTO | RPO | Met? |
| --- | --- | --- | --- |
| … | … | … | Yes / no |
| … | … | … | … |

---

<!-- _class: timeline -->

# Test timeline

- T+0 :: Test start :: Scenario announced.
- T+… :: Failover started
- T+… :: Recovery verified
- T+… :: Test end

---

<!-- _class: table table-editable -->

# Findings

| Finding | Severity | Component |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

# Deviations and blockers

- Deviation from the playbook: …
- Blocker during the test: …
- Workaround used: …

---

# Improvement points
<!-- ocideck_list_style: checklist -->

- [ ] Update playbook on point: …
- [ ] Adjust technical setup: …
- [ ] Schedule training or exercise: …

---

# Go / no-go recovery capability
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Critical processes recovered within RTO
- [ ] Data loss stayed within RPO
- [ ] Playbook proved usable
- [ ] Verdict: recovery capability demonstrated
