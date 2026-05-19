defmodule Jido.Ecto.Migrations do
  @moduledoc """
  Migration helpers for `jido_ecto`.

  ## Example

      defmodule MyApp.Repo.Migrations.CreateJidoStorage do
        use Ecto.Migration

        def change do
          require Jido.Ecto.Migrations
          Jido.Ecto.Migrations.create_storage_tables(version: 1)
        end
      end

  ## Options

  - `:version` - required storage schema version
  - `:prefix` - database prefix or schema name passed through to Ecto.
    PostgreSQL schemas are created automatically when a prefix is provided.
  """

  @current_storage_schema_version 1

  @doc """
  Creates the storage tables used by `Jido.Ecto.Storage`.
  """
  @spec create_storage_tables(keyword()) :: Macro.t()
  defmacro create_storage_tables(opts \\ []) do
    version = Keyword.get(opts, :version)
    prefix = Keyword.get(opts, :prefix)

    case version do
      @current_storage_schema_version ->
        :ok

      nil ->
        raise ArgumentError,
              "create_storage_tables/1 requires a :version option. Use version: #{@current_storage_schema_version}."

      other ->
        raise ArgumentError,
              "unsupported jido_ecto storage schema version: #{inspect(other)}"
    end

    quote bind_quoted: [prefix: prefix] do
      if Jido.Ecto.Migrations.prefix?(prefix) do
        execute(
          fn -> Jido.Ecto.Migrations.ensure_prefix_schema!(repo(), prefix) end,
          fn -> :ok end
        )
      end

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
        add(:entries, :binary, null: false)
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

  @doc false
  @spec prefix?(String.t() | atom() | nil) :: boolean()
  def prefix?(prefix), do: prefix not in [nil, ""]

  @doc false
  @spec ensure_prefix_schema!(module(), String.t() | atom() | nil) :: :ok
  def ensure_prefix_schema!(_repo, prefix) when prefix in [nil, ""], do: :ok

  def ensure_prefix_schema!(repo, prefix) do
    if repo.__adapter__() == Ecto.Adapters.Postgres do
      repo.query!("CREATE SCHEMA IF NOT EXISTS #{quote_postgres_identifier(prefix)}", [], log: false)
    end

    :ok
  end

  defp quote_postgres_identifier(prefix) when is_atom(prefix) do
    prefix
    |> Atom.to_string()
    |> quote_postgres_identifier()
  end

  defp quote_postgres_identifier(prefix) when is_binary(prefix) do
    escaped = String.replace(prefix, ~s("), ~s(""))
    ~s("#{escaped}")
  end
end
