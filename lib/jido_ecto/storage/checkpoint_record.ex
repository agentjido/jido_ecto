defmodule Jido.Ecto.Storage.CheckpointRecord do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:key_hash, :string, autogenerate: false}

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          key_hash: String.t() | nil,
          key_term: binary() | nil,
          value: binary() | nil
        }

  schema "jido_checkpoints" do
    field(:key_term, :binary)
    field(:value, :binary)
  end
end
