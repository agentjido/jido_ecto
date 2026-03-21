defmodule Jido.Ecto.MigrationsTest do
  use ExUnit.Case, async: true

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
end
