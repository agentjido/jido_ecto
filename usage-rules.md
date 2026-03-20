# Usage Rules for LLM Agents

- Keep public APIs documented and note breaking changes explicitly.
- Preserve `Jido.Storage` checkpoint and journal semantics.
- Keep `Jido.Persist` integration explicit; never hide thread or checkpoint invariants.
- Prefer explicit repo, prefix, and schema options over implicit global configuration.
- Add tests for transaction behavior, optimistic concurrency, and not-found cases.
- Do not mix example-only wiring into shipped library code.
