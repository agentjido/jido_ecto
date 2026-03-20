# Getting Started with Jido Ecto

`jido_ecto` is the package scaffold for an Ecto-backed Jido storage adapter.

## Current Status

This guide describes the intended integration shape. The runtime adapter is not
implemented yet.

## 1. Add dependency

Until the first Hex release, depend on GitHub:

```elixir
def deps do
  [
    {:jido_ecto, github: "agentjido/jido_ecto", branch: "main"}
  ]
end
```

## 2. Plan an Ecto repo

The MVP will target an `Ecto.Repo` that owns the tables for checkpoints and
thread journal entries.

## 3. Configure Jido storage

The intended integration shape is:

```elixir
defmodule MyApp.Jido do
  use Jido,
    otp_app: :my_app,
    storage: {Jido.Ecto.Storage, repo: MyApp.Repo}
end
```

## 4. Persist with Jido.Persist

Explicit persistence flows are expected to work with the same storage config:

```elixir
Jido.Persist.hibernate({Jido.Ecto.Storage, repo: MyApp.Repo}, agent)
```
