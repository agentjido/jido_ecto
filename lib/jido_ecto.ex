defmodule Jido.Ecto do
  @moduledoc """
  Ecto-backed storage package for Jido.

  This repository is currently in its package-bootstrap phase. The MVP will add
  an Ecto-backed `Jido.Storage` adapter and the persistence plumbing required
  for `Jido.Persist` hibernate and thaw flows.

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
