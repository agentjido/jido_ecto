defmodule Jido.Ecto.Migrations do
  @moduledoc """
  Migration helpers for `jido_ecto`.

  ## Example

      defmodule MyApp.Repo.Migrations.CreateJidoStorage do
        use Ecto.Migration

        def change do
          require Jido.Ecto.Migrations
          Jido.Ecto.Migrations.create_storage_tables()
        end
      end

  ## Options

  - `:prefix` - database prefix or schema name passed through to Ecto
  """

  @doc """
  Creates the storage tables used by `Jido.Ecto.Storage`.
  """
  @spec create_storage_tables(keyword()) :: Macro.t()
  defmacro create_storage_tables(opts \\ []) do
    prefix = Keyword.get(opts, :prefix)

    quote bind_quoted: [prefix: prefix] do
      create table(:jido_checkpoints, primary_key: false, prefix: prefix) do
        add(:key_hash, :string, primary_key: true)
        add(:key_term, :binary, null: false)
        add(:value, :binary, null: false)
      end

      create table(:jido_threads, primary_key: false, prefix: prefix) do
        add(:thread_id, :string, primary_key: true)
        add(:rev, :integer, null: false, default: 0)
        add(:created_at_ms, :bigint, null: false)
        add(:updated_at_ms, :bigint, null: false)
        add(:metadata, :binary, null: false)
      end

      create table(:jido_thread_entries, primary_key: false, prefix: prefix) do
        add(
          :thread_id,
          references(:jido_threads,
            column: :thread_id,
            type: :string,
            on_delete: :delete_all,
            prefix: prefix
          ),
          null: false
        )

        add(:seq, :integer, null: false)
        add(:entry_id, :string, null: false)
        add(:at_ms, :bigint, null: false)
        add(:kind, :string, null: false)
        add(:data, :binary, null: false)
      end

      create(unique_index(:jido_thread_entries, [:thread_id, :seq], prefix: prefix))
      create(index(:jido_thread_entries, [:thread_id], prefix: prefix))
    end
  end
end
