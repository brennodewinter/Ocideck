---
id: fmea
engine: matrix
phase: analyze
label:
  nl: FMEA
  en: FMEA
guidance:
  nl: RPN = S×O×D wordt berekend — typ hem niet zelf.
  en: RPN = S×O×D is derived — never type it yourself.
columns:
  - { key: step, label: { nl: Processtap, en: Process step } }
  - { key: failure, label: { nl: Faalwijze, en: Failure mode } }
  - { key: effect, label: { nl: Effect, en: Effect } }
  - { key: severity, label: { nl: S, en: S } }
  - { key: cause, label: { nl: Oorzaak, en: Cause } }
  - { key: occurrence, label: { nl: O, en: O } }
  - { key: control, label: { nl: Beheersing, en: Control } }
  - { key: detection, label: { nl: D, en: D } }
  - { key: rpn, label: { nl: RPN, en: RPN }, derived: true }
---
| Process step | Failure mode | Effect | S | Cause | O | Control | D |
|---|---|---|---|---|---|---|---|
|  |  |  |  |  |  |  |  |
