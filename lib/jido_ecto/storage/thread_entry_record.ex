defmodule Jido.Ecto.Storage.ThreadEntryRecord do
  @moduledoc false

  use Ecto.Schema

  @primary_key false

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          thread_id: String.t() | nil,
          seq: integer() | nil,
          entry_id: String.t() | nil,
          at_ms: integer() | nil,
          kind: String.t() | nil,
          data: binary() | nil
        }

  schema "jido_thread_entries" do
    field(:thread_id, :string)
    field(:seq, :integer)
    field(:entry_id, :string)
    field(:at_ms, :integer)
    field(:kind, :string)
    field(:data, :binary)
  end
end
