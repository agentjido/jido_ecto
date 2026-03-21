# Jido Ecto

`jido_ecto` provides an Ecto-backed storage package for Jido runtimes.

## Alpha Status

`jido_ecto` now ships a working `Jido.Ecto.Storage` adapter and migration
helper, but it is still early and should be treated as alpha-quality.

- Do not rely on this package in production yet.
- The schema shape and installation flow may still change.
- The adapter currently focuses on correctness and Jido compatibility before
  broader operational tuning.

## Features

- `Jido.Ecto.Storage` implementing `Jido.Storage`
- `Jido.Ecto.Migrations.create_storage_tables/1` for provisioning storage tables
- Ecto-backed checkpoints and ordered thread journals
- Thread snapshots stored alongside the append-only journal for faster loads
- `Jido.Persist` compatibility for hibernate/thaw flows
- Optimistic concurrency for thread appends via `:expected_rev`
- Tested against SQLite and PostgreSQL repos

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

## Database Migration

Create the required tables in one of your repo migrations:

```elixir
defmodule MyApp.Repo.Migrations.CreateJidoStorage do
  use Ecto.Migration

  def change do
    require Jido.Ecto.Migrations
    Jido.Ecto.Migrations.create_storage_tables(version: 1)
  end
end
```

`version: 1` is required so consuming apps freeze the emitted DDL in their own
migration history.

## Installation via Igniter

`jido_ecto` does not yet provide an Igniter installer module.

## Quick Start

Configure Jido to use the Ecto storage adapter:

```elixir
defmodule MyApp.Jido do
  use Jido,
    otp_app: :my_app,
    storage: {Jido.Ecto.Storage, repo: MyApp.Repo}
end
```

The same storage config works with `Jido.Persist`:

```elixir
Jido.Persist.hibernate({Jido.Ecto.Storage, repo: MyApp.Repo}, agent)
```

Thread metadata is stored only when a thread is first created. Subsequent
appends preserve the existing metadata and advance `rev` atomically. The thread
row stores the latest serialized snapshot, while `jido_thread_entries` remains
an ordered append-only journal.

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
