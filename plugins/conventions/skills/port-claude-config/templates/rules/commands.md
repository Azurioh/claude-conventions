---
paths:
  - "<app-path>/**"
---

# <app> — commands

Verification (CI parity, run from the repo root, in this order):

    <command 1> && <command 2> && <command 3>

- <Why the order matters: which step generates an input the next one needs.>
  Zero errors and zero warnings before "done".
- <Env-dependent step>: `<command>` (needs `<VAR>`). Without `<VAR>` it
  <skips silently / fails> — export it before running.
- Dev / build / start: `<command>`.
