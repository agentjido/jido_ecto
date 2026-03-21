defmodule Jido.Ecto.Storage do
  @moduledoc """
  Ecto-backed `Jido.Storage` adapter.

  The adapter persists three logical records:

  - checkpoints in `jido_checkpoints`
  - thread state snapshots in `jido_threads`
  - ordered thread journal entries in `jido_thread_entries`

  Create those tables with `Jido.Ecto.Migrations.create_storage_tables/1`.

  Required options:

  - `:repo` - an `Ecto.Repo` module

  Optional repo options passed through to queries:

  - `:prefix`
  - `:timeout`
  - `:log`
  - `:telemetry_event`
  - `:telemetry_options`

  `append_thread/3` also accepts:

  - `:expected_rev` - optimistic concurrency guard
  - `:metadata` - thread metadata used only when the thread is first created
  """

  @behaviour Jido.Storage

  import Ecto.Query, only: [from: 2]

  alias Jido.Ecto.Storage.{CheckpointRecord, ThreadEntryRecord, ThreadRecord}
  alias Jido.Thread
  alias Jido.Thread.Entry
  alias Jido.Thread.EntryNormalizer

  @max_append_retries 5
  @query_opt_keys [:prefix, :timeout, :log, :telemetry_event, :telemetry_options]
  @transaction_opt_keys [:timeout, :log, :telemetry_event, :telemetry_options]

  @type thread_state :: %{
          rev: non_neg_integer(),
          created_at_ms: integer(),
          updated_at_ms: integer(),
          persisted?: boolean(),
          metadata: map(),
          entries: [Entry.t()]
        }

  @impl true
  @spec get_checkpoint(term(), keyword()) :: {:ok, term()} | :not_found | {:error, term()}
  def get_checkpoint(key, opts) do
    execute(opts, fn repo, query_opts, _transaction_opts ->
      case repo.get(CheckpointRecord, checkpoint_hash(key), query_opts) do
        nil ->
          :not_found

        %CheckpointRecord{} = record ->
          with {:ok, stored_key} <- decode_term(record.key_term),
               :ok <- validate_checkpoint_key(stored_key, key),
               {:ok, value} <- decode_term(record.value) do
            {:ok, value}
          end
      end
    end)
  end

  @impl true
  @spec put_checkpoint(term(), term(), keyword()) :: :ok | {:error, term()}
  def put_checkpoint(key, data, opts) do
    execute(opts, fn repo, query_opts, _transaction_opts ->
      encoded_key = encode_term(key)
      encoded_value = encode_term(data)

      repo.insert_all(
        CheckpointRecord,
        [
          %{
            key_hash: checkpoint_hash(key),
            key_term: encoded_key,
            value: encoded_value
          }
        ],
        Keyword.merge(
          query_opts,
          on_conflict: [set: [key_term: encoded_key, value: encoded_value]],
          conflict_target: [:key_hash]
        )
      )

      :ok
    end)
  end

  @impl true
  @spec delete_checkpoint(term(), keyword()) :: :ok | {:error, term()}
  def delete_checkpoint(key, opts) do
    execute(opts, fn repo, query_opts, _transaction_opts ->
      from(c in CheckpointRecord, where: c.key_hash == ^checkpoint_hash(key))
      |> repo.delete_all(query_opts)

      :ok
    end)
  end

  @impl true
  @spec load_thread(String.t(), keyword()) :: {:ok, Thread.t()} | :not_found | {:error, term()}
  def load_thread(thread_id, opts) do
    execute(opts, fn repo, query_opts, transaction_opts ->
      case transact(repo, fn -> load_thread_tx(repo, query_opts, thread_id) end, transaction_opts) do
        {:ok, result} -> result
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  @impl true
  @spec append_thread(String.t(), [Entry.t() | map()], keyword()) :: {:ok, Thread.t()} | {:error, term()}
  def append_thread(thread_id, entries, opts) do
    execute(opts, fn repo, query_opts, transaction_opts ->
      append_thread_with_retry(
        repo,
        query_opts,
        transaction_opts,
        thread_id,
        List.wrap(entries),
        Keyword.get(opts, :expected_rev),
        Keyword.get(opts, :metadata, %{}),
        @max_append_retries
      )
    end)
  end

  @impl true
  @spec delete_thread(String.t(), keyword()) :: :ok | {:error, term()}
  def delete_thread(thread_id, opts) do
    execute(opts, fn repo, query_opts, transaction_opts ->
      case transact(repo, fn -> delete_thread_tx(repo, query_opts, thread_id) end, transaction_opts) do
        {:ok, :ok} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  @spec append_thread_with_retry(
          module(),
          keyword(),
          keyword(),
          String.t(),
          [Entry.t() | map()],
          integer() | nil,
          map(),
          non_neg_integer()
        ) :: {:ok, Thread.t()} | {:error, term()}
  defp append_thread_with_retry(
         repo,
         query_opts,
         transaction_opts,
         thread_id,
         entries,
         expected_rev,
         metadata,
         attempts_remaining
       ) do
    case transact(
           repo,
           fn -> append_thread_tx(repo, query_opts, thread_id, entries, expected_rev, metadata) end,
           transaction_opts
         ) do
      {:ok, %Thread{} = thread} ->
        {:ok, thread}

      {:error, :retry} when is_nil(expected_rev) and attempts_remaining > 1 ->
        append_thread_with_retry(
          repo,
          query_opts,
          transaction_opts,
          thread_id,
          entries,
          expected_rev,
          metadata,
          attempts_remaining - 1
        )

      {:error, :retry} ->
        {:error, :conflict}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec append_thread_tx(module(), keyword(), String.t(), [Entry.t() | map()], integer() | nil, map()) ::
          Thread.t() | no_return()
  defp append_thread_tx(repo, query_opts, thread_id, entries, expected_rev, initial_metadata) do
    now = now_ms()

    with {:ok, state} <- load_thread_state(repo, query_opts, thread_id),
         :ok <- validate_expected_rev(expected_rev, state.rev) do
      prepared_entries = EntryNormalizer.normalize_many(entries, state.rev, now)
      next_entries = state.entries ++ prepared_entries
      metadata = if state.persisted?, do: state.metadata, else: initial_metadata

      with :ok <- maybe_create_thread_record(repo, query_opts, thread_id, state, next_entries, now, metadata),
           :ok <- insert_thread_entries(repo, query_opts, thread_id, prepared_entries),
           :ok <- maybe_update_thread_record(repo, query_opts, thread_id, state, next_entries, now) do
        reconstruct_thread(
          thread_id,
          length(next_entries),
          state.created_at_ms,
          now,
          metadata,
          next_entries
        )
      else
        {:error, :conflict} when is_nil(expected_rev) -> rollback(repo, :retry)
        {:error, :conflict} -> rollback(repo, :conflict)
      end
    else
      {:error, :conflict} -> rollback(repo, :conflict)
      {:error, reason} -> rollback(repo, reason)
    end
  end

  @spec load_thread_tx(module(), keyword(), String.t()) :: {:ok, Thread.t()} | :not_found | {:error, term()}
  defp load_thread_tx(repo, query_opts, thread_id) do
    with {:ok, state} <- load_thread_state(repo, query_opts, thread_id) do
      if state.entries == [] do
        :not_found
      else
        {:ok,
         reconstruct_thread(
           thread_id,
           state.rev,
           state.created_at_ms,
           state.updated_at_ms,
           state.metadata,
           state.entries
         )}
      end
    end
  end

  @spec delete_thread_tx(module(), keyword(), String.t()) :: :ok
  defp delete_thread_tx(repo, query_opts, thread_id) do
    from(e in ThreadEntryRecord, where: e.thread_id == ^thread_id)
    |> repo.delete_all(query_opts)

    from(t in ThreadRecord, where: t.thread_id == ^thread_id)
    |> repo.delete_all(query_opts)

    :ok
  end

  @spec load_thread_state(module(), keyword(), String.t()) :: {:ok, thread_state()} | {:error, term()}
  defp load_thread_state(repo, query_opts, thread_id) do
    record = repo.get(ThreadRecord, thread_id, query_opts)

    case record do
      nil ->
        if thread_entries_exist?(repo, query_opts, thread_id) do
          {:error, :orphaned_thread_entries}
        else
          now = now_ms()

          {:ok,
           %{
             rev: 0,
             created_at_ms: now,
             updated_at_ms: now,
             persisted?: false,
             metadata: %{},
             entries: []
           }}
        end

      %ThreadRecord{} = record ->
        with {:ok, metadata} <- decode_thread_metadata(record.metadata),
             {:ok, entries} <- decode_thread_entries_term(record.entries),
             :ok <- validate_thread_revision(record.rev, entries) do
          {:ok,
           %{
             rev: record.rev,
             created_at_ms: record.created_at_ms,
             updated_at_ms: record.updated_at_ms,
             persisted?: true,
             metadata: metadata,
             entries: entries
           }}
        end
    end
  end

  @spec thread_entries_exist?(module(), keyword(), String.t()) :: boolean()
  defp thread_entries_exist?(repo, query_opts, thread_id) do
    query =
      from(e in ThreadEntryRecord,
        where: e.thread_id == ^thread_id,
        select: e.thread_id,
        limit: 1
      )

    repo.all(query, query_opts) != []
  end

  @spec maybe_create_thread_record(module(), keyword(), String.t(), thread_state(), [Entry.t()], integer(), map()) ::
          :ok | {:error, :conflict}
  defp maybe_create_thread_record(repo, query_opts, thread_id, state, entries, now, metadata) do
    if state.persisted? do
      :ok
    else
      case repo.insert_all(
             ThreadRecord,
             [
               %{
                 thread_id: thread_id,
                 rev: length(entries),
                 created_at_ms: state.created_at_ms,
                 updated_at_ms: now,
                 metadata: encode_term(metadata),
                 entries: encode_term(entries)
               }
             ],
             Keyword.merge(query_opts, on_conflict: :nothing, conflict_target: [:thread_id])
           ) do
        {1, _rows} -> :ok
        {_count, _rows} -> {:error, :conflict}
      end
    end
  end

  @spec maybe_update_thread_record(module(), keyword(), String.t(), thread_state(), [Entry.t()], integer()) ::
          :ok | {:error, :conflict}
  defp maybe_update_thread_record(repo, query_opts, thread_id, state, entries, now) do
    if state.persisted? do
      query =
        from(t in ThreadRecord,
          where: t.thread_id == ^thread_id and t.rev == ^state.rev
        )

      case repo.update_all(
             query,
             [set: [rev: length(entries), updated_at_ms: now, entries: encode_term(entries)]],
             query_opts
           ) do
        {1, _rows} -> :ok
        {_count, _rows} -> {:error, :conflict}
      end
    else
      :ok
    end
  end

  @spec insert_thread_entries(module(), keyword(), String.t(), [Entry.t()]) :: :ok | {:error, :conflict}
  defp insert_thread_entries(_repo, _query_opts, _thread_id, []), do: :ok

  defp insert_thread_entries(repo, query_opts, thread_id, entries) do
    rows =
      Enum.map(entries, fn %Entry{} = entry ->
        %{
          thread_id: thread_id,
          seq: entry.seq,
          entry_id: entry.id,
          at_ms: entry.at,
          kind: Atom.to_string(entry.kind),
          data: encode_term(entry)
        }
      end)

    case repo.insert_all(
           ThreadEntryRecord,
           rows,
           Keyword.merge(query_opts, on_conflict: :nothing, conflict_target: [:thread_id, :seq])
         ) do
      {count, _rows} when count == length(rows) -> :ok
      {_count, _rows} -> {:error, :conflict}
    end
  end

  @spec validate_expected_rev(integer() | nil, non_neg_integer()) :: :ok | {:error, :conflict}
  defp validate_expected_rev(nil, _current_rev), do: :ok
  defp validate_expected_rev(expected_rev, expected_rev), do: :ok
  defp validate_expected_rev(_expected_rev, _current_rev), do: {:error, :conflict}

  @spec validate_thread_revision(non_neg_integer(), [Entry.t()]) :: :ok | {:error, :invalid_thread_revision}
  defp validate_thread_revision(rev, entries) when rev == length(entries), do: :ok
  defp validate_thread_revision(_rev, _entries), do: {:error, :invalid_thread_revision}

  @spec decode_thread_entries_term(binary()) :: {:ok, [Entry.t()]} | {:error, :invalid_thread_entry}
  defp decode_thread_entries_term(binary) do
    with {:ok, decoded} <- decode_term(binary),
         {:ok, entries} <- normalize_stored_entries(decoded) do
      {:ok, entries}
    end
  end

  @spec normalize_stored_entries(term()) :: {:ok, [Entry.t()]} | {:error, :invalid_thread_entry}
  defp normalize_stored_entries(entries) when is_list(entries) do
    entries
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {entry, expected_seq}, {:ok, acc} ->
      with {:ok, normalized} <- normalize_stored_entry(entry),
           :ok <- validate_entry_seq(normalized, expected_seq) do
        {:cont, {:ok, [normalized | acc]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, normalized_entries} -> {:ok, Enum.reverse(normalized_entries)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_stored_entries(_other), do: {:error, :invalid_thread_entry}

  @spec validate_entry_seq(Entry.t(), non_neg_integer()) :: :ok | {:error, :invalid_thread_entry}
  defp validate_entry_seq(%Entry{seq: seq}, expected_seq) when seq == expected_seq, do: :ok
  defp validate_entry_seq(_entry, _expected_seq), do: {:error, :invalid_thread_entry}

  @spec normalize_stored_entry(term()) :: {:ok, Entry.t()} | {:error, :invalid_thread_entry}
  defp normalize_stored_entry(%Entry{} = entry), do: {:ok, entry}

  defp normalize_stored_entry(%{id: id, seq: seq, at: at, kind: kind, payload: payload, refs: refs})
       when is_binary(id) and is_integer(seq) and seq >= 0 and is_integer(at) and is_atom(kind) and
              is_map(payload) and is_map(refs) do
    {:ok, %Entry{id: id, seq: seq, at: at, kind: kind, payload: payload, refs: refs}}
  end

  defp normalize_stored_entry(_other), do: {:error, :invalid_thread_entry}

  @spec decode_thread_metadata(binary()) :: {:ok, map()} | {:error, :invalid_thread_metadata}
  defp decode_thread_metadata(binary) do
    case decode_term(binary) do
      {:ok, metadata} when is_map(metadata) -> {:ok, metadata}
      {:ok, _other} -> {:error, :invalid_thread_metadata}
      {:error, _reason} -> {:error, :invalid_thread_metadata}
    end
  end

  @spec reconstruct_thread(String.t(), non_neg_integer(), integer(), integer(), map(), [Entry.t()]) :: Thread.t()
  defp reconstruct_thread(thread_id, rev, created_at_ms, updated_at_ms, metadata, entries) do
    %Thread{
      id: thread_id,
      rev: rev,
      entries: entries,
      created_at: created_at_ms,
      updated_at: updated_at_ms,
      metadata: metadata,
      stats: %{entry_count: length(entries)}
    }
  end

  @spec execute(keyword(), (module(), keyword(), keyword() -> term())) :: term() | {:error, term()}
  defp execute(opts, fun) when is_function(fun, 3) do
    with {:ok, repo} <- fetch_repo(opts) do
      try do
        fun.(repo, query_opts(opts), transaction_opts(opts))
      rescue
        error -> {:error, error}
      end
    end
  end

  @spec fetch_repo(keyword()) :: {:ok, module()} | {:error, term()}
  defp fetch_repo(opts) do
    case Keyword.get(opts, :repo) do
      nil ->
        {:error, :missing_repo}

      repo when is_atom(repo) ->
        if Code.ensure_loaded?(repo) do
          {:ok, repo}
        else
          {:error, {:repo_not_loaded, repo}}
        end

      other ->
        {:error, {:invalid_repo, other}}
    end
  end

  @spec query_opts(keyword()) :: keyword()
  defp query_opts(opts), do: Keyword.take(opts, @query_opt_keys)

  @spec transaction_opts(keyword()) :: keyword()
  defp transaction_opts(opts), do: Keyword.take(opts, @transaction_opt_keys)

  @spec checkpoint_hash(term()) :: String.t()
  defp checkpoint_hash(key) do
    key
    |> encode_term()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end

  @spec validate_checkpoint_key(term(), term()) :: :ok | {:error, :checkpoint_hash_collision}
  defp validate_checkpoint_key(key, key), do: :ok
  defp validate_checkpoint_key(_stored_key, _requested_key), do: {:error, :checkpoint_hash_collision}

  @spec encode_term(term()) :: binary()
  defp encode_term(term), do: :erlang.term_to_binary(term)

  @spec decode_term(binary()) :: {:ok, term()} | {:error, :invalid_term}
  defp decode_term(binary) do
    {:ok, :erlang.binary_to_term(binary, [:safe])}
  rescue
    ArgumentError ->
      {:error, :invalid_term}
  end

  @spec now_ms() :: integer()
  defp now_ms, do: System.system_time(:millisecond)

  @spec transact(module(), (-> term()), keyword()) :: {:ok, term()} | {:error, term()}
  defp transact(repo, fun, opts) do
    case repo.transaction(fun, opts) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
      other -> {:ok, other}
    end
  rescue
    error ->
      {:error, error}
  catch
    {module, :rollback, reason} when is_atom(module) ->
      {:error, reason}
  end

  @spec rollback(module(), term()) :: no_return()
  defp rollback(repo, reason) do
    if function_exported?(repo, :rollback, 1) do
      repo.rollback(reason)
    else
      throw({repo, :rollback, reason})
    end
  end
end
