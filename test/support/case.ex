defmodule Jido.Ecto.Case do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Jido.Ecto.Storage.{CheckpointRecord, ThreadEntryRecord, ThreadRecord}
  alias Jido.Ecto.TestRepo

  using do
    quote do
      alias Jido.Ecto.Storage
      alias Jido.Ecto.TestRepo
      alias Jido.Thread
      alias Jido.Thread.Entry

      import Jido.Ecto.Case
    end
  end

  setup tags do
    _ = tags
    clear_storage!()

    {:ok, storage_opts: [repo: TestRepo]}
  end

  @spec clear_storage!() :: :ok
  def clear_storage! do
    TestRepo.delete_all(ThreadEntryRecord)
    TestRepo.delete_all(ThreadRecord)
    TestRepo.delete_all(CheckpointRecord)
    :ok
  end

  @spec unique_id(String.t()) :: String.t()
  def unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive])}"
  end
end
