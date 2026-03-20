ExUnit.start()

db_path = Application.fetch_env!(:jido_ecto, Jido.Ecto.TestRepo)[:database]
File.mkdir_p!(Path.dirname(db_path))
File.rm(db_path)

{:ok, _pid} = Jido.Ecto.TestRepo.start_link()

{:ok, _migrated, _apps} =
  Ecto.Migrator.with_repo(Jido.Ecto.TestRepo, fn repo ->
    Ecto.Migrator.up(repo, 0, Jido.Ecto.TestRepo.Migrations.CreateStorageTables, log: false)
  end)
