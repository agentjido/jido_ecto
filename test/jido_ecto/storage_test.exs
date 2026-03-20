defmodule Jido.Ecto.StorageTest do
  use Jido.Ecto.Case, async: false

  alias Jido.Ecto.Storage.{ThreadEntryRecord, ThreadRecord}
  alias Jido.Ecto.Support.{OrphanedEntriesRepo, RaisingRepo, RetryRepo, TransactionErrorRepo}
  alias Jido.Thread.Entry

  test "checkpoint operations round-trip arbitrary terms", %{storage_opts: storage_opts} do
    key = {:agent, unique_id("checkpoint")}
    data = %{state: %{count: 1}, tags: [:ecto, :storage]}

    assert :not_found = Storage.get_checkpoint(key, storage_opts)
    assert :ok = Storage.put_checkpoint(key, data, storage_opts)
    assert {:ok, ^data} = Storage.get_checkpoint(key, storage_opts)
    assert :ok = Storage.delete_checkpoint(key, storage_opts)
    assert :not_found = Storage.get_checkpoint(key, storage_opts)
  end

  test "returns config errors for missing repo" do
    assert {:error, :missing_repo} = Storage.get_checkpoint(:foo, [])
    assert {:error, :missing_repo} = Storage.put_checkpoint(:foo, :bar, [])
    assert {:error, :missing_repo} = Storage.load_thread("thread-1", [])
  end

  test "returns repo loading and validation errors" do
    pid = self()

    assert {:error, {:repo_not_loaded, Jido.Ecto.Support.MissingRepo}} =
             Storage.get_checkpoint(:foo, repo: Jido.Ecto.Support.MissingRepo)

    assert {:error, {:invalid_repo, ^pid}} = Storage.get_checkpoint(:foo, repo: pid)
  end

  test "surfaces raised repo errors" do
    assert {:error, %RuntimeError{message: "boom"}} = Storage.get_checkpoint(:foo, repo: RaisingRepo)
  end

  test "surfaces transaction failures from the repo" do
    assert {:error, :db_down} = Storage.load_thread("thread-1", repo: TransactionErrorRepo)
    assert {:error, :db_down} = Storage.delete_thread("thread-1", repo: TransactionErrorRepo)
  end

  test "retries append when the repo reports a transient retry" do
    assert :ok = RetryRepo.reset!()
    assert {:ok, thread} = Storage.append_thread("retry-thread", [], repo: RetryRepo)
    assert thread.id == "retry-thread"
  end

  test "append_thread creates and loads a thread with metadata", %{storage_opts: storage_opts} do
    thread_id = unique_id("thread")

    assert {:ok, created} =
             Storage.append_thread(
               thread_id,
               [
                 %{kind: :note, payload: %{n: 1}},
                 %{kind: :message, payload: %{text: "hi"}}
               ],
               Keyword.put(storage_opts, :metadata, %{source: "test"})
             )

    assert created.id == thread_id
    assert created.rev == 2
    assert created.metadata == %{source: "test"}
    assert Enum.map(created.entries, & &1.seq) == [0, 1]

    assert {:ok, loaded} = Storage.load_thread(thread_id, storage_opts)
    assert loaded.rev == 2
    assert loaded.metadata == %{source: "test"}
    assert Enum.map(loaded.entries, & &1.kind) == [:note, :message]

    assert {:ok, appended} =
             Storage.append_thread(
               thread_id,
               [%{kind: :note, payload: %{n: 3}}],
               Keyword.put(storage_opts, :metadata, %{source: "ignored"})
             )

    assert appended.rev == 3
    assert appended.metadata == %{source: "test"}
    assert Enum.map(appended.entries, & &1.seq) == [0, 1, 2]
  end

  test "expected_rev conflict rolls back entry inserts", %{storage_opts: storage_opts} do
    thread_id = unique_id("conflict-thread")

    assert {:ok, thread} =
             Storage.append_thread(
               thread_id,
               [%{kind: :note, payload: %{n: 1}}],
               Keyword.put(storage_opts, :expected_rev, 0)
             )

    assert thread.rev == 1

    assert {:error, :conflict} =
             Storage.append_thread(
               thread_id,
               [%{kind: :note, payload: %{n: 2}}],
               Keyword.put(storage_opts, :expected_rev, 0)
             )

    assert {:ok, loaded} = Storage.load_thread(thread_id, storage_opts)
    assert loaded.rev == 1
    assert Enum.map(loaded.entries, & &1.payload.n) == [1]
    assert TestRepo.aggregate(ThreadEntryRecord, :count, :thread_id) == 1
  end

  test "empty append creates metadata but load_thread still reports not found", %{storage_opts: storage_opts} do
    thread_id = unique_id("empty-thread")

    assert {:ok, thread} =
             Storage.append_thread(
               thread_id,
               [],
               Keyword.put(storage_opts, :metadata, %{kind: "empty"})
             )

    assert thread.rev == 0
    assert thread.metadata == %{kind: "empty"}
    assert :not_found = Storage.load_thread(thread_id, storage_opts)
  end

  test "delete_thread clears meta and entry rows", %{storage_opts: storage_opts} do
    thread_id = unique_id("delete-thread")

    assert {:ok, _thread} =
             Storage.append_thread(
               thread_id,
               [%{kind: :note, payload: %{n: 1}}],
               Keyword.put(storage_opts, :metadata, %{scope: "delete"})
             )

    assert TestRepo.aggregate(ThreadRecord, :count, :thread_id) == 1
    assert TestRepo.aggregate(ThreadEntryRecord, :count, :thread_id) == 1

    assert :ok = Storage.delete_thread(thread_id, storage_opts)
    assert :not_found = Storage.load_thread(thread_id, storage_opts)
    assert TestRepo.aggregate(ThreadRecord, :count, :thread_id) == 0
    assert TestRepo.aggregate(ThreadEntryRecord, :count, :thread_id) == 0
  end

  test "load_thread reports invalid persisted entry state", %{storage_opts: storage_opts} do
    thread_id = unique_id("invalid-thread")

    _record =
      TestRepo.insert!(%ThreadRecord{
        thread_id: thread_id,
        rev: 1,
        created_at_ms: 1,
        updated_at_ms: 1,
        metadata: :erlang.term_to_binary(%{})
      })

    _entry =
      TestRepo.insert!(%ThreadEntryRecord{
        thread_id: thread_id,
        seq: 0,
        entry_id: "entry-1",
        at_ms: 1,
        kind: "note",
        data: :erlang.term_to_binary(%{bad: :entry})
      })

    assert {:error, :invalid_thread_entry} = Storage.load_thread(thread_id, storage_opts)
  end

  test "load_thread reports orphaned entry rows" do
    assert {:error, :orphaned_thread_entries} =
             Storage.load_thread("orphan-thread", repo: OrphanedEntriesRepo)
  end

  test "load_thread reports invalid thread revision", %{storage_opts: storage_opts} do
    thread_id = unique_id("revision-thread")
    entry = %Entry{id: "entry-1", seq: 0, at: 1, kind: :note, payload: %{}, refs: %{}}

    _record =
      TestRepo.insert!(%ThreadRecord{
        thread_id: thread_id,
        rev: 2,
        created_at_ms: 1,
        updated_at_ms: 1,
        metadata: :erlang.term_to_binary(%{})
      })

    _entry =
      TestRepo.insert!(%ThreadEntryRecord{
        thread_id: thread_id,
        seq: 0,
        entry_id: entry.id,
        at_ms: entry.at,
        kind: "note",
        data: :erlang.term_to_binary(entry)
      })

    assert {:error, :invalid_thread_revision} = Storage.load_thread(thread_id, storage_opts)
  end

  test "load_thread reports invalid thread metadata", %{storage_opts: storage_opts} do
    thread_id = unique_id("metadata-thread")

    _record =
      TestRepo.insert!(%ThreadRecord{
        thread_id: thread_id,
        rev: 0,
        created_at_ms: 1,
        updated_at_ms: 1,
        metadata: :erlang.term_to_binary(:not_a_map)
      })

    assert {:error, :invalid_thread_metadata} = Storage.load_thread(thread_id, storage_opts)
  end

  test "load_thread normalizes stored map entries", %{storage_opts: storage_opts} do
    thread_id = unique_id("map-thread")

    _record =
      TestRepo.insert!(%ThreadRecord{
        thread_id: thread_id,
        rev: 1,
        created_at_ms: 1,
        updated_at_ms: 1,
        metadata: :erlang.term_to_binary(%{})
      })

    _entry =
      TestRepo.insert!(%ThreadEntryRecord{
        thread_id: thread_id,
        seq: 0,
        entry_id: "entry-1",
        at_ms: 1,
        kind: "note",
        data:
          :erlang.term_to_binary(%{
            id: "entry-1",
            seq: 0,
            at: 1,
            kind: :note,
            payload: %{n: 1},
            refs: %{}
          })
      })

    assert {:ok, loaded} = Storage.load_thread(thread_id, storage_opts)
    assert [%Entry{} = entry] = loaded.entries
    assert entry.payload == %{n: 1}
  end

  test "load_thread rejects mismatched stored entry columns", %{storage_opts: storage_opts} do
    thread_id = unique_id("mismatch-thread")
    entry = %Entry{id: "entry-1", seq: 0, at: 1, kind: :note, payload: %{}, refs: %{}}

    _record =
      TestRepo.insert!(%ThreadRecord{
        thread_id: thread_id,
        rev: 1,
        created_at_ms: 1,
        updated_at_ms: 1,
        metadata: :erlang.term_to_binary(%{})
      })

    _entry =
      TestRepo.insert!(%ThreadEntryRecord{
        thread_id: thread_id,
        seq: 0,
        entry_id: entry.id,
        at_ms: entry.at,
        kind: "message",
        data: :erlang.term_to_binary(entry)
      })

    assert {:error, :invalid_thread_entry} = Storage.load_thread(thread_id, storage_opts)
  end

  test "load_thread rejects non-contiguous entry sequences", %{storage_opts: storage_opts} do
    thread_id = unique_id("sequence-thread")
    entry = %Entry{id: "entry-1", seq: 1, at: 1, kind: :note, payload: %{}, refs: %{}}

    _record =
      TestRepo.insert!(%ThreadRecord{
        thread_id: thread_id,
        rev: 1,
        created_at_ms: 1,
        updated_at_ms: 1,
        metadata: :erlang.term_to_binary(%{})
      })

    _entry =
      TestRepo.insert!(%ThreadEntryRecord{
        thread_id: thread_id,
        seq: 1,
        entry_id: entry.id,
        at_ms: entry.at,
        kind: "note",
        data: :erlang.term_to_binary(entry)
      })

    assert {:error, :invalid_thread_entry} = Storage.load_thread(thread_id, storage_opts)
  end

  test "get_checkpoint detects key collisions and invalid terms", %{storage_opts: storage_opts} do
    key = {:agent, unique_id("corrupt-checkpoint")}

    key_hash =
      key
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.url_encode64(padding: false)

    _collision =
      TestRepo.insert!(%Jido.Ecto.Storage.CheckpointRecord{
        key_hash: key_hash,
        key_term: :erlang.term_to_binary(:other_key),
        value: :erlang.term_to_binary(%{ok: true})
      })

    assert {:error, :checkpoint_hash_collision} = Storage.get_checkpoint(key, storage_opts)

    TestRepo.delete_all(Jido.Ecto.Storage.CheckpointRecord)

    _invalid =
      TestRepo.insert!(%Jido.Ecto.Storage.CheckpointRecord{
        key_hash: key_hash,
        key_term: :erlang.term_to_binary(key),
        value: <<0, 1, 2>>
      })

    assert {:error, :invalid_term} = Storage.get_checkpoint(key, storage_opts)
  end
end
