defmodule Jido.Ecto.Storage do
  @moduledoc """
  Planned Ecto-backed `Jido.Storage` adapter.

  The MVP implementation will persist checkpoints and thread journals through
  an `Ecto.Repo` while preserving the ordering and optimistic concurrency
  guarantees expected by `Jido.Storage` and `Jido.Persist`.
  """
end
