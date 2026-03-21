# Getting Started with Jido Ecto

`jido_ecto` provides an Ecto-backed `Jido.Storage` adapter and a migration
helper for provisioning the required tables.

## 1. Add dependency

Until the first Hex release, depend on GitHub:

```elixir
def deps do
  [
    {:jido_ecto, github: "agentjido/jido_ecto", branch: "main"}
  ]
end
```

## 2. Add the storage tables

Create a repo migration that provisions the checkpoint, thread, and thread
entry tables:

```elixir
defmodule MyApp.Repo.Migrations.CreateJidoStorage do
  use Ecto.Migration

  def change do
    require Jido.Ecto.Migrations
    Jido.Ecto.Migrations.create_storage_tables(version: 1)
  end
end
```

Pass an explicit schema version so the migration remains reproducible even if
future package releases add newer storage layouts.

## 3. Configure Jido storage

Point your Jido instance at an `Ecto.Repo`:

```elixir
defmodule MyApp.Jido do
  use Jido,
    otp_app: :my_app,
    storage: {Jido.Ecto.Storage, repo: MyApp.Repo}
end
```

## 4. Persist with Jido.Persist

Explicit persistence flows use the same storage tuple:

```elixir
Jido.Persist.hibernate({Jido.Ecto.Storage, repo: MyApp.Repo}, agent)
```

## 5. Concurrency semantics

`append_thread/3` supports `:expected_rev` for optimistic concurrency. When the
expected revision does not match the stored revision, the adapter returns
`{:error, :conflict}`.
