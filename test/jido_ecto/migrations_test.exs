defmodule Jido.Ecto.MigrationsTest do
  use ExUnit.Case, async: true

  alias Jido.Ecto.TestRepo

  defmodule PostgresRepo do
    @moduledoc false

    def __adapter__, do: Ecto.Adapters.Postgres

    def query!(sql, params, opts) do
      send(self(), {:query!, sql, params, opts})
      :ok
    end
  end

  defmodule SQLiteRepo do
    @moduledoc false

    def __adapter__, do: Ecto.Adapters.SQLite3
  end

  test "create_storage_tables requires an explicit version" do
    module_name = "Jido.Ecto.DynamicMissingVersion#{System.unique_integer([:positive])}"

    code = """
    defmodule #{module_name} do
      use Ecto.Migration
      require Jido.Ecto.Migrations

      def change do
        Jido.Ecto.Migrations.create_storage_tables()
      end
    end
    """

    assert_raise ArgumentError, ~r/requires a :version option/, fn ->
      Code.compile_string(code)
    end
  end

  test "create_storage_tables rejects unsupported versions" do
    module_name = "Jido.Ecto.DynamicUnsupportedVersion#{System.unique_integer([:positive])}"

    code = """
    defmodule #{module_name} do
      use Ecto.Migration
      require Jido.Ecto.Migrations

      def change do
        Jido.Ecto.Migrations.create_storage_tables(version: 99)
      end
    end
    """

    assert_raise ArgumentError, ~r/unsupported jido_ecto storage schema version/, fn ->
      Code.compile_string(code)
    end
  end

  test "ensure_prefix_schema! creates quoted postgres schema" do
    assert :ok = Jido.Ecto.Migrations.ensure_prefix_schema!(PostgresRepo, ~s(jido"tenant))

    assert_received {:query!, ~s(CREATE SCHEMA IF NOT EXISTS "jido""tenant"), [], [log: false]}
  end

  test "ensure_prefix_schema! ignores non-postgres adapters" do
    assert :ok = Jido.Ecto.Migrations.ensure_prefix_schema!(SQLiteRepo, "jido")
  end

  test "create_storage_tables creates prefixed postgres schema" do
    if apply(TestRepo, :__adapter__, []) == Ecto.Adapters.Postgres do
      Ecto.Adapters.SQL.query!(TestRepo, "DROP SCHEMA IF EXISTS jido_ecto_prefix_test CASCADE", [])

      result =
        Ecto.Migrator.up(
          TestRepo,
          System.unique_integer([:positive]),
          Jido.Ecto.TestRepo.Migrations.CreatePrefixedStorageTables,
          log: false
        )

      assert result in [:ok, :up]

      assert %{rows: [[qualified_name]]} =
               Ecto.Adapters.SQL.query!(
                 TestRepo,
                 "SELECT to_regclass('jido_ecto_prefix_test.jido_threads')::text",
                 []
               )

      assert qualified_name == "jido_ecto_prefix_test.jido_threads"
    end
  end
end
