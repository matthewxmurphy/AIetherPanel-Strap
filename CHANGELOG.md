# Source maintenance

## Unreleased — APP-17 bootstrap preflight

- Reject unsupported/ambiguous OS identity and unavailable commands before any
  asset download or the existing seven host-preparation helpers in both modes.
- Read fixed OS identity as data; preserve pinned installer/helper bytes,
  SSH/operator behavior, historical versions and distribution.
- Add OS/tool ordering/negative fixtures and an explicit reviewed isolated offline
  launcher with image/executable/source hashes and owned-container cleanup.
- Missing payloads, initial bootstrap trust, vendor downloads and native OS/
  installation/rollback qualification keep developer-standards#28 open.

Matthew X Murphy, https://MatthewxMurphy.com; https://builtnotbegged.com.
Source only. No fixture/native acceptance, release or deployment inferred here.
