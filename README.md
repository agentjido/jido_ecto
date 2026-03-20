# Jido Ecto

`jido_ecto` provides an Ecto-backed storage package for Jido runtimes.

## Alpha Status

`jido_ecto` is still pre-MVP. This initial repository setup establishes the
package-quality baseline, contributor docs, CI, and release automation before
the Ecto adapter implementation lands.

- Do not rely on this package in production yet.
- The initial MVP will target `Jido.Storage` and `Jido.Persist` integration.
- The runtime adapter API may change while the schema and transaction model are
  finalized.

## Planned Features

- `Jido.Ecto.Storage` implementing `Jido.Storage`
- Ecto-backed checkpoints and thread journals
- `Jido.Persist` compatibility for hibernate/thaw flows
- Explicit optimistic concurrency for thread appends

## Installation

Until the first Hex release, depend on the GitHub repository directly:

```elixir
def deps do
  [
    {:jido_ecto, github: "agentjido/jido_ecto", branch: "main"}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

## Installation via Igniter

`jido_ecto` does not yet provide an Igniter installer module.

## Quick Start

The adapter implementation is not in place yet. The MVP is intended to support
usage shaped like this:

```elixir
defmodule MyApp.Jido do
  use Jido,
    otp_app: :my_app,
    storage: {Jido.Ecto.Storage, repo: MyApp.Repo}
end
```

And for explicit persistence flows:

```elixir
Jido.Persist.hibernate({Jido.Ecto.Storage, repo: MyApp.Repo}, agent)
```

## Development

```bash
mix setup
mix quality
mix test
```

## Release

Releases are driven from `.github/workflows/release.yml` via GitHub Actions.
Do not publish from ad hoc local commands.

## License

Apache-2.0
