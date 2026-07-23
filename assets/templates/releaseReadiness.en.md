---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: CAB / release readiness
language: en
---

<!-- _class: title -->

# CAB / release readiness

---

# Change summary

- What is changing: …
- Why now: …
- Requested by: …

---

# Scope and impact

- Systems and services affected: …
- Users affected: …
- Expected disruption: … (duration, timing)

---

<!-- _class: table table-editable -->

# Test status

| Test | Result | Evidence |
| --- | --- | --- |
| Functional test | Passed / open | … |
| Regression test | … | … |
| Performance test | … | … |

---

# Security and privacy check
<!-- ocideck_list_style: checklist -->

- [ ] Security review performed
- [ ] No new personal data — or DPIA checked
- [ ] Secrets and access rights checked
- [ ] Vulnerability scan clean

---

<!-- _class: table table-editable -->

# Implementation plan

| Step | Time | Who |
| --- | --- | --- |
| … | … | … |
| … | … | … |
| … | … | … |

---

# Rollback plan
<!-- ocideck_list_style: numbered -->

1. Rollback possible until: …
2. Rollback steps: …
3. Go/no-go rollback decision point: …

---

# Communication plan

- Inform in advance: … (who, when)
- During the change: …
- Confirm afterwards: …

---

# Go / no-go checklist
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Tests completed and approved
- [ ] Rollback tested or plausible
- [ ] Communication prepared
- [ ] Operations informed and available

---

<!-- _class: table table-editable -->

# CAB decision

| Decision | Conditions | Date and time |
| --- | --- | --- |
| Go / no-go / postponed | … | … |
