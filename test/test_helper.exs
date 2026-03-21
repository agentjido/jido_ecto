ExUnit.start()

repo_config = Application.fetch_env!(:jido_ecto, Jido.Ecto.TestRepo)

if repo_config[:adapter] == Ecto.Adapters.SQLite3 do
  db_path = Keyword.fetch!(repo_config, :database)
  File.mkdir_p!(Path.dirname(db_path))
  File.rm(db_path)
end

{:ok, _pid} = Jido.Ecto.TestRepo.start_link()

if repo_config[:adapter] == Ecto.Adapters.Postgres do
  for statement <- [
        "DROP TABLE IF EXISTS jido_thread_entries",
        "DROP TABLE IF EXISTS jido_threads",
        "DROP TABLE IF EXISTS jido_checkpoints"
      ] do
    Ecto.Adapters.SQL.query!(Jido.Ecto.TestRepo, statement, [])
  end
end

{:ok, _migrated, _apps} =
  Ecto.Migrator.with_repo(Jido.Ecto.TestRepo, fn repo ->
    Ecto.Migrator.up(repo, 0, Jido.Ecto.TestRepo.Migrations.CreateStorageTables, log: false)
  end)
