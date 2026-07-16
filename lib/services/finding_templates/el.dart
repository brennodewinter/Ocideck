// GEGENEREERD noch handwerk-vrij: de proza hieronder is vertaald, de rest is
// vastgezet. Zie PENTEST_MIAUW §12.1/§12.3 en
// test/finding_template_languages_test.dart.
//
// Wat NIET vertaald mag worden, en waarom:
//  - de `## …`-koppen zijn parse-ankers van FindingSpec; vertaal je ze, dan
//    komt de sectie leeg terug bij het invoegen;
//  - `cwe:` is een MITRE-citaat en `severity:` het door FIRST gepubliceerde
//    bandlabel dat een bevinding zélf ook opslaat;
//  - `cvss_vector`/`cvss_version` zijn tokens, `references` zijn URL's.
//
// Vertaald is wat van ons is: de titel (die de kop van de bevinding wordt) en
// de vier prozasecties — een skelet dat de tester per opdracht aanscherpt.

/// De meegeleverde finding-sjablonen in het Grieks (el).
const Map<String, String> findingTemplatesEl = {
  'sql-injection': '''
---
title: Ένεση SQL
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of Special Elements used in an SQL Command
references:
  - https://owasp.org/www-community/attacks/SQL_Injection
  - https://cwe.mitre.org/data/definitions/89.html
---

## Description

Η είσοδος του χρήστη ενσωματώνεται σε ερώτημα SQL χωρίς κατάλληλη
παραμετροποίηση, επιτρέποντας σε έναν επιτιθέμενο να αλλάξει τη λογική του
ερωτήματος.

## Confirmation (reproduction)

Υποβάλετε μια κατασκευασμένη τιμή στην επηρεαζόμενη παράμετρο και διαπιστώστε ότι
η εφαρμογή επιστρέφει δεδομένα εκτός του προβλεπόμενου συνόλου αποτελεσμάτων.

## Possible impact

Ένας επιτιθέμενος μπορεί να διαβάσει, να τροποποιήσει ή να διαγράψει δεδομένα στη
βάση και, ανάλογα με τη διαμόρφωσή της, να αποκτήσει περαιτέρω πρόσβαση στον
κεντρικό υπολογιστή.

## Recommendation

Χρησιμοποιήστε παραμετροποιημένα ερωτήματα (prepared statements) για κάθε πρόσβαση
στη βάση και επικυρώστε την είσοδο βάσει λίστας επιτρεπομένων. Χρησιμοποιήστε
λογαριασμούς βάσης με ελάχιστα δικαιώματα.
''',
  'reflected-xss': '''
---
title: Ανακλώμενο cross-site scripting (XSS)
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

Η είσοδος του χρήστη ανακλάται στην απόκριση χωρίς κατάλληλη κωδικοποίηση εξόδου,
ώστε ένας επιτιθέμενος να μπορεί να εισαγάγει σενάριο που εκτελείται στο
πρόγραμμα περιήγησης του θύματος.

## Confirmation (reproduction)

Δώστε ένα ωφέλιμο φορτίο στην επηρεαζόμενη παράμετρο και παρατηρήστε την εκτέλεσή
του στην αποδοθείσα σελίδα.

## Possible impact

Παραβίαση συνεδρίας, κλοπή διαπιστευτηρίων και ενέργειες που εκτελούνται εκ μέρους
του θύματος εντός της εφαρμογής.

## Recommendation

Κωδικοποίηση εξόδου με επίγνωση του περιβάλλοντος για όλα τα δεδομένα που ελέγχει
ο χρήστης, αυστηρή Content Security Policy και αυτόματη διαφυγή από το πλαίσιο.
''',
  'weak-password-policy': '''
---
title: Αδύναμη πολιτική κωδικών πρόσβασης
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

Η εφαρμογή δέχεται αδύναμους κωδικούς πρόσβασης (σύντομους, κοινούς ή χωρίς
απαιτήσεις πολυπλοκότητας), καθιστώντας τους λογαριασμούς ευκολότερα μαντεύσιμους.

## Confirmation (reproduction)

Εγγραφείτε ή αλλάξτε έναν κωδικό πρόσβασης σε σύντομη, κοινή τιμή και διαπιστώστε
ότι γίνεται δεκτή.

## Possible impact

Αυξημένη πιθανότητα κατάληψης λογαριασμού μέσω επιθέσεων ωμής βίας ή credential
stuffing.

## Recommendation

Επιβάλετε ελάχιστο μήκος, ελέγξτε έναντι λιστών παραβιασμένων κωδικών και
υποστηρίξτε έλεγχο ταυτότητας πολλαπλών παραγόντων.
''',
};
