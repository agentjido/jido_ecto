defmodule Jido.Ecto.TestRepo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :jido_ecto,
    adapter: Ecto.Adapters.SQLite3
end
