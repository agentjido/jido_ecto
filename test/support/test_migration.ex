defmodule Jido.Ecto.TestRepo.Migrations.CreateStorageTables do
  @moduledoc false

  use Ecto.Migration

  def change do
    require Jido.Ecto.Migrations
    Jido.Ecto.Migrations.create_storage_tables(version: 1)
  end
end
