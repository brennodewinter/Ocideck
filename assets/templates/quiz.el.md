---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Διαδραστικό κουίζ
language: el
---

<!-- _class: title -->

# Διαδραστικό κουίζ

---

# Σχετικά με αυτό το κουίζ

- Τρεις ερωτήσεις, τρεις μορφές ερωτήσεων
- Απαντήστε μόνοι σας πρώτα, μετά συζητάμε μαζί
- Το βάλατε λάθος; Έτσι ακριβώς μαθαίνουμε

---

<!-- _class: question -->

# Ερώτηση 1: πολλαπλής επιλογής

```question
{
  "kind": "multipleChoice",
  "prompt": "Αντικαταστήστε το με τη δική σας ερώτηση πολλαπλής επιλογής.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Η σωστή απάντηση",
      "correct": true
    },
    {
      "text": "Μια λάθος απάντηση",
      "correct": false
    },
    {
      "text": "Άλλη λάθος απάντηση",
      "correct": false
    },
    {
      "text": "Ακόμη μια λάθος απάντηση",
      "correct": false
    }
  ]
}
```

---

# Εξηγώντας την απάντηση

- Γιατί αυτή είναι η σωστή απάντηση: …
- Συνήθης παρανόηση: …

---

<!-- _class: question -->

# Ερώτηση 2: αληθές ή ψευδές

```question
{
  "kind": "trueFalse",
  "prompt": "Αντικαταστήστε το με μια πρόταση που είναι αληθής ή ψευδής.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "statementIsTrue": true,
  "answers": []
}
```

---

<!-- _class: question -->

# Ερώτηση 3: πολλαπλές σωστές απαντήσεις

```question
{
  "kind": "multipleCorrect",
  "prompt": "Αντικαταστήστε το με μια ερώτηση που έχει πολλαπλές σωστές απαντήσεις.",
  "optionCount": 4,
  "timeLimitSeconds": 0,
  "onWrong": "retry",
  "answers": [
    {
      "text": "Σωστή απάντηση 1",
      "correct": true
    },
    {
      "text": "Σωστή απάντηση 2",
      "correct": true
    },
    {
      "text": "Λάθος απάντηση 1",
      "correct": false
    },
    {
      "text": "Λάθος απάντηση 2",
      "correct": false
    }
  ]
}
```

---

# Στοχασμός και συζήτηση

- Ποια ερώτηση ήταν η πιο δύσκολη — και γιατί;
- Τι θα κρατήσετε από αυτό;

---

<!-- _class: section -->

# Κλείσιμο
