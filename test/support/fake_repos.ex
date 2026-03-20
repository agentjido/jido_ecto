defmodule Jido.Ecto.Support.RaisingRepo do
  @moduledoc false

  def get(_schema, _id, _opts) do
    raise "boom"
  end
end

defmodule Jido.Ecto.Support.TransactionErrorRepo do
  @moduledoc false

  def transaction(_fun, _opts), do: {:error, :db_down}
end

defmodule Jido.Ecto.Support.RetryRepo do
  @moduledoc false

  alias Jido.Thread

  @spec reset!() :: :ok
  def reset! do
    Process.delete(key())
    :ok
  end

  def transaction(_fun, _opts) do
    case Process.get(key(), 0) do
      0 ->
        Process.put(key(), 1)
        {:error, :retry}

      _ ->
        {:ok,
         %Thread{
           id: "retry-thread",
           rev: 0,
           entries: [],
           created_at: 0,
           updated_at: 0,
           metadata: %{},
           stats: %{entry_count: 0}
         }}
    end
  end

  defp key, do: {__MODULE__, :calls}
end

defmodule Jido.Ecto.Support.OrphanedEntriesRepo do
  @moduledoc false

  alias Jido.Ecto.Storage.ThreadEntryRecord
  alias Jido.Thread.Entry

  def transaction(fun, _opts), do: {:ok, fun.()}

  def get(_schema, _id, _opts), do: nil

  def all(_query, _opts) do
    entry = %Entry{id: "entry-1", seq: 0, at: 1, kind: :note, payload: %{}, refs: %{}}

    [
      %ThreadEntryRecord{
        thread_id: "orphan-thread",
        seq: 0,
        entry_id: entry.id,
        at_ms: entry.at,
        kind: "note",
        data: :erlang.term_to_binary(entry)
      }
    ]
  end
end
