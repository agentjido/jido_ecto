# Contributing

Thank you for contributing to `jido_ecto`.

## Development

```bash
mix setup
mix quality
mix test
```

## Requirements

- Elixir `~> 1.18`
- OTP 27+

## Guidelines

- Keep public APIs documented with `@doc` and `@spec`.
- Add tests for behavior, edge cases, and conflict handling.
- Preserve `Jido.Storage` ordering and `Jido.Persist` checkpoint invariants.
- Use Conventional Commits.

## Release

Releases are driven from `.github/workflows/release.yml` in GitHub Actions.
Do not publish from ad hoc local commands.
