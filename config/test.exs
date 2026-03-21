import Config

config :logger, level: :warning

test_db = System.get_env("JIDO_ECTO_TEST_DB", "sqlite")

config :jido_ecto, ecto_repos: [Jido.Ecto.TestRepo]

case test_db do
  "postgres" ->
    config :jido_ecto, Jido.Ecto.TestRepo,
      adapter: Ecto.Adapters.Postgres,
      username: System.get_env("PGUSER", "postgres"),
      password: System.get_env("PGPASSWORD", "postgres"),
      hostname: System.get_env("PGHOST", "127.0.0.1"),
      port: String.to_integer(System.get_env("PGPORT", "5432")),
      database: System.get_env("PGDATABASE", "jido_ecto_test"),
      pool_size: 1

  _ ->
    config :jido_ecto, Jido.Ecto.TestRepo,
      adapter: Ecto.Adapters.SQLite3,
      database: Path.expand("../tmp/jido_ecto_test.sqlite3", __DIR__),
      pool_size: 1,
      busy_timeout: 5_000,
      journal_mode: :wal,
      temp_store: :memory
end
