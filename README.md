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

Your host app must already have:

- an `Ecto.Repo`
- `:ecto_sql`
- the database adapter for that repo, for example `:postgrex` or `:ecto_sqlite3`

`jido_ecto` uses your existing repo. It does not create or supervise one.

## Setup

### 1. Create the storage migration

Generate a migration in your application:

```bash
mix ecto.gen.migration create_jido_storage
```

Then create the required tables in that migration:

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

If you want the tables in a database prefix or schema:

```elixir
def change do
  require Jido.Ecto.Migrations
  Jido.Ecto.Migrations.create_storage_tables(version: 1, prefix: "jido")
end
```

For PostgreSQL, `jido_ecto` creates the schema if it does not already exist.

### 2. Run the migration

```bash
mix ecto.migrate
```

### 3. Configure Jido storage

Point Jido at your repo:

```elixir
defmodule MyApp.Jido do
  use Jido,
    otp_app: :my_app,
    storage: {Jido.Ecto.Storage, repo: MyApp.Repo}
end
```

You can also keep the tuple in config and pass it anywhere Jido expects a
storage adapter:

```elixir
config :my_app, :jido_storage, {Jido.Ecto.Storage, repo: MyApp.Repo}
```

### 4. Use it with `Jido.Persist`

The same storage tuple works for explicit persistence flows:

```elixir
storage = {Jido.Ecto.Storage, repo: MyApp.Repo}

:ok = Jido.Persist.hibernate(storage, agent)
{:ok, restored_agent} = Jido.Persist.thaw(storage, MyAgent, agent.id)
```

## Setup Reference

### Tables created by `version: 1`

- `jido_checkpoints`
- `jido_threads`
- `jido_thread_entries`

`jido_threads` stores the latest serialized thread snapshot. `jido_thread_entries`
remains the ordered append-only journal.

### Adapter options

Required:

- `:repo` - your `Ecto.Repo` module

Optional query and transaction passthrough options:

- `:prefix`
- `:timeout`
- `:log`
- `:telemetry_event`
- `:telemetry_options`

`append_thread/3` also accepts:

- `:expected_rev` - optimistic concurrency guard
- `:metadata` - initial metadata for a new thread

### Minimal smoke test

After migrating, confirm the adapter works against your repo:

```elixir
storage = [repo: MyApp.Repo]

{:ok, thread} =
  Jido.Ecto.Storage.append_thread(
    "thread-1",
    [%{kind: :note, payload: %{message: "hello"}}],
    storage
  )

{:ok, loaded} = Jido.Ecto.Storage.load_thread("thread-1", storage)
thread.rev == loaded.rev
```

## Database Notes

- PostgreSQL and SQLite are exercised in this package's test matrix.
- The package uses portable Ecto APIs and should work with other SQL adapters
  that support the schema types used here.
- Thread appends use optimistic concurrency through `:expected_rev`.

## Installation via Igniter

`jido_ecto` does not yet provide an Igniter installer module.

## Quick Start

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
