import Config

config :logger, level: :warning

config :jido_ecto, ecto_repos: [Jido.Ecto.TestRepo]

config :jido_ecto, Jido.Ecto.TestRepo,
  database: Path.expand("../tmp/jido_ecto_test.sqlite3", __DIR__),
  pool_size: 1,
  busy_timeout: 5_000,
  journal_mode: :wal,
  temp_store: :memory
