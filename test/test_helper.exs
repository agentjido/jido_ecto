ExUnit.start()

conformance_root =
  System.get_env("JIDO_STORAGE_CONFORMANCE_ROOT") ||
    Path.expand("../../jido/test/support", __DIR__)

conformance_files = [
  "storage_checkpoint_conformance.ex",
  "storage_thread_conformance.ex"
]

Enum.each(conformance_files, fn filename ->
  path = Path.join(conformance_root, filename)

  unless File.exists?(path) do
    raise """
    Missing Jido storage conformance support: #{path}

    Set JIDO_STORAGE_CONFORMANCE_ROOT to the Jido checkout's test/support directory,
    or check out Jido as a sibling repository at ../jido before running tests.
    """
  end

  Code.require_file(path)
end)

repo_config = Application.fetch_env!(:jido_ecto, Jido.Ecto.TestRepo)

if repo_config[:adapter] == Ecto.Adapters.SQLite3 do
  db_path = Keyword.fetch!(repo_config, :database)
  File.mkdir_p!(Path.dirname(db_path))
  File.rm(db_path)
end

{:ok, _pid} = Jido.Ecto.TestRepo.start_link()

if repo_config[:adapter] == Ecto.Adapters.Postgres do
  for statement <- [
        "DROP TABLE IF EXISTS schema_migrations",
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
