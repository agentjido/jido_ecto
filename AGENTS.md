# Jido Ecto Agent Guide

## Commands

- `mix setup` - install dependencies and git hooks
- `mix test` - run the test suite
- `mix coveralls` - run tests with coverage checks
- `mix quality` - run formatter, compile, credo, dialyzer, and doctor
- `mix docs` - build docs

## Standards

- Follow the canonical package baseline at `https://jido.run/docs/contributors/package-quality-standards`.
- Target Elixir `~> 1.18`.
- Add `@moduledoc` for public modules.
- Add `@doc` and `@spec` for public functions.
- Preserve `Jido.Storage` and `Jido.Persist` invariants.
- Keep adapter behavior deterministic, explicit, and testable.
- Prefer explicit repo and schema options over application-global configuration.

## Testing

- Unit tests should mirror `lib/` structure.
- Keep adapter tests Ecto sandbox-friendly.
- Add coverage for optimistic concurrency, transaction rollback, and not-found semantics.

## Commit Style

Use Conventional Commits, for example:

- `feat(storage): add ecto-backed checkpoint schema`
- `fix(storage): normalize thread conflict handling`
- `test(persist): add hibernate and thaw coverage`

## Release Hygiene

- Do not modify `CHANGELOG.md`; release notes are generated from Git history during release, so keep changes focused on proper Conventional Commits.
