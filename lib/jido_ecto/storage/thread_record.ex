defmodule Jido.Ecto.Storage.ThreadRecord do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:thread_id, :string, autogenerate: false}

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          thread_id: String.t() | nil,
          rev: integer() | nil,
          created_at_ms: integer() | nil,
          updated_at_ms: integer() | nil,
          metadata: binary() | nil
        }

  schema "jido_threads" do
    field(:rev, :integer)
    field(:created_at_ms, :integer)
    field(:updated_at_ms, :integer)
    field(:metadata, :binary)
  end
end
