defmodule Jido.Ecto do
  @moduledoc """
  Ecto-backed storage package for Jido.

  `jido_ecto` provides:

  - `Jido.Ecto.Storage` for `Jido.Storage`
  - `Jido.Ecto.Migrations` for provisioning the required tables

  The adapter stores checkpoints as opaque Erlang terms and persists thread
  journals as ordered entry rows plus thread metadata. That keeps the storage
  semantics aligned with `Jido.Storage` and allows `Jido.Persist` to hibernate
  and thaw agents without a separate persistence adapter module.

  ## Examples

      iex> Jido.Ecto.capabilities()
      [:storage, :persist]
  """

  @type capability() :: :storage | :persist

  @doc """
  Returns the Jido integration surfaces targeted by this package.
  """
  @spec capabilities() :: [capability()]
  def capabilities, do: [:storage, :persist]
end
