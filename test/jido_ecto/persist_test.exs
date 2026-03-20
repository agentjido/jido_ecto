defmodule Jido.Ecto.PersistTest do
  use Jido.Ecto.Case, async: false

  alias Jido.Ecto.Support.DummyAgent

  test "hibernate stores a checkpoint and thaw rehydrates the thread", %{storage_opts: storage_opts} do
    thread_id = unique_id("persist-thread")

    thread =
      Thread.new(id: thread_id, metadata: %{scope: "persist"})
      |> Thread.append([
        %{kind: :note, payload: %{n: 1}},
        %{kind: :message, payload: %{text: "hello"}}
      ])

    agent = %DummyAgent{
      id: unique_id("agent"),
      agent_module: DummyAgent,
      state: %{count: 1, __thread__: thread}
    }

    assert :ok = Jido.Persist.hibernate({Storage, storage_opts}, agent)

    checkpoint_key = {DummyAgent, agent.id}
    assert {:ok, checkpoint} = Storage.get_checkpoint(checkpoint_key, storage_opts)
    assert checkpoint.thread == %{id: thread_id, rev: 2}
    assert checkpoint.state == %{count: 1}

    assert {:ok, thawed} = Jido.Persist.thaw({Storage, storage_opts}, DummyAgent, agent.id)
    assert thawed.id == agent.id
    assert thawed.state.count == 1
    assert thawed.state.__thread__.id == thread_id
    assert thawed.state.__thread__.rev == 2
    assert Enum.map(thawed.state.__thread__.entries, & &1.kind) == [:note, :message]
  end

  test "hibernate flushes only missing thread entries on subsequent writes", %{storage_opts: storage_opts} do
    thread_id = unique_id("incremental-thread")
    agent_id = unique_id("agent")

    thread =
      Thread.new(id: thread_id, metadata: %{topic: "incremental"})
      |> Thread.append([%{kind: :note, payload: %{n: 1}}, %{kind: :note, payload: %{n: 2}}])

    first_agent = %DummyAgent{id: agent_id, agent_module: DummyAgent, state: %{version: 1, __thread__: thread}}

    assert :ok = Jido.Persist.hibernate({Storage, storage_opts}, first_agent)

    next_thread = Thread.append(thread, [%{kind: :note, payload: %{n: 3}}])

    second_agent = %DummyAgent{
      id: agent_id,
      agent_module: DummyAgent,
      state: %{version: 2, __thread__: next_thread}
    }

    assert :ok = Jido.Persist.hibernate({Storage, storage_opts}, second_agent)

    assert {:ok, stored_thread} = Storage.load_thread(thread_id, storage_opts)
    assert stored_thread.rev == 3
    assert Enum.map(stored_thread.entries, & &1.payload.n) == [1, 2, 3]

    assert {:ok, thawed} = Jido.Persist.thaw({Storage, storage_opts}, DummyAgent, agent_id)
    assert thawed.state.version == 2
    assert thawed.state.__thread__.rev == 3
    assert Enum.map(thawed.state.__thread__.entries, & &1.payload.n) == [1, 2, 3]
  end
end
