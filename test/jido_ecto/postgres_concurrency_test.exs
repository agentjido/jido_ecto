if Application.compile_env(:jido_ecto, [Jido.Ecto.TestRepo, :adapter]) == Ecto.Adapters.Postgres do
  defmodule Jido.Ecto.PostgresConcurrencyTest do
    use Jido.Ecto.Case, async: false

    import Ecto.Query, only: [from: 2]

    alias Jido.Ecto.Storage.{ThreadEntryRecord, ThreadRecord}
    alias Jido.Thread.Entry

    @append_count 24
    @repeat_count 3
    @task_timeout 30_000

    test "concurrent appends without expected_rev commit a complete journal repeatedly", %{
      storage_opts: storage_opts
    } do
      for iteration <- 1..@repeat_count do
        thread_id = unique_id("postgres-concurrent-#{iteration}")

        assert {:ok, _} = Storage.append_thread(thread_id, [%{kind: :note, payload: %{n: 0}}], storage_opts)

        results = concurrent_appends(thread_id, storage_opts, @append_count)

        assert Enum.all?(results, &match?({:ok, _}, &1)), inspect(results)
        assert {:ok, thread} = Storage.load_thread(thread_id, storage_opts)
        assert thread.rev == @append_count + 1
        assert Enum.map(thread.entries, & &1.seq) == Enum.to_list(0..@append_count)

        assert Enum.map(thread.entries, & &1.payload.n) |> Enum.sort() ==
                 Enum.to_list(0..@append_count)

        assert_journal_is_complete!(thread_id, @append_count + 1)
      end
    end

    test "concurrent first appends retry and create a complete journal", %{
      storage_opts: storage_opts
    } do
      thread_id = unique_id("postgres-concurrent-first-write")

      results = concurrent_appends(thread_id, storage_opts, @append_count)

      assert Enum.all?(results, &match?({:ok, _}, &1)), inspect(results)
      assert {:ok, thread} = Storage.load_thread(thread_id, storage_opts)
      assert thread.rev == @append_count
      assert Enum.map(thread.entries, & &1.seq) == Enum.to_list(0..(@append_count - 1))
      assert Enum.map(thread.entries, & &1.payload.n) |> Enum.sort() == Enum.to_list(1..@append_count)
      assert_journal_is_complete!(thread_id, @append_count)
    end

    test "concurrent writers with identical expected_rev have exactly one winner", %{
      storage_opts: storage_opts
    } do
      thread_id = unique_id("postgres-concurrent-expected")

      assert {:ok, first} =
               Storage.append_thread(thread_id, [%{kind: :note, payload: %{n: 0}}], storage_opts)

      results =
        synchronized_tasks(2, fn index ->
          Storage.append_thread(
            thread_id,
            [%{kind: :note, payload: %{n: index}}],
            Keyword.put(storage_opts, :expected_rev, first.rev)
          )
        end)

      assert Enum.count(results, &match?({:ok, _}, &1)) == 1, inspect(results)
      assert Enum.count(results, &(&1 == {:error, :conflict})) == 1, inspect(results)
      assert {:ok, thread} = Storage.load_thread(thread_id, storage_opts)
      assert thread.rev == 2
      assert Enum.map(thread.entries, & &1.seq) == [0, 1]
      assert_journal_is_complete!(thread_id, 2)
    end

    defp concurrent_appends(thread_id, storage_opts, count) do
      synchronized_tasks(count, fn index ->
        Storage.append_thread(
          thread_id,
          [%{kind: :note, payload: %{n: index}}],
          storage_opts
        )
      end)
    end

    defp synchronized_tasks(count, fun) do
      barrier = start_barrier(count)

      tasks =
        Enum.map(1..count, fn index ->
          Task.async(fn ->
            send(barrier, {:ready, self()})

            receive do
              :go -> fun.(index)
            after
              @task_timeout -> exit(:barrier_timeout)
            end
          end)
        end)

      try do
        await_barrier(barrier, count)
        send(barrier, :release)

        Enum.map(tasks, &Task.await(&1, @task_timeout))
      after
        stop_barrier(barrier)
      end
    end

    defp start_barrier(count) do
      parent = self()

      spawn(fn ->
        ready =
          Enum.map(1..count, fn _ ->
            receive do
              {:ready, pid} -> pid
            after
              @task_timeout -> exit({:barrier_timeout, count})
            end
          end)

        send(parent, {:barrier_ready, self()})

        receive do
          :release -> Enum.each(ready, &send(&1, :go))
        after
          @task_timeout -> exit(:barrier_release_timeout)
        end
      end)
    end

    defp await_barrier(barrier, count) do
      receive do
        {:barrier_ready, ^barrier} -> :ok
      after
        @task_timeout -> flunk("concurrent test barrier did not release #{count} writers")
      end
    end

    defp stop_barrier(barrier) when is_pid(barrier), do: Process.exit(barrier, :kill)
    defp stop_barrier(_barrier), do: :ok

    defp assert_journal_is_complete!(thread_id, expected_count) do
      assert TestRepo.aggregate(ThreadRecord, :count, :thread_id) >= 1

      rows =
        from(e in ThreadEntryRecord,
          where: e.thread_id == ^thread_id,
          order_by: [asc: e.seq],
          select: {e.seq, e.data}
        )
        |> TestRepo.all()

      assert length(rows) == expected_count
      assert Enum.map(rows, &elem(&1, 0)) == Enum.to_list(0..(expected_count - 1))

      assert Enum.all?(rows, fn {seq, data} ->
               %Entry{seq: ^seq} = :erlang.binary_to_term(data, [:safe])
               true
             end)
    end
  end
end
