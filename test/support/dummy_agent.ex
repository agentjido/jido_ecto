defmodule Jido.Ecto.Support.DummyAgent do
  @moduledoc false

  defstruct [:id, :agent_module, state: %{}]

  @spec new(keyword()) :: __MODULE__.t()
  def new(opts \\ []) do
    %__MODULE__{
      id: Keyword.fetch!(opts, :id),
      agent_module: __MODULE__,
      state: %{}
    }
  end

  @type t :: %__MODULE__{
          id: term(),
          agent_module: module(),
          state: map()
        }
end
