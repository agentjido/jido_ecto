defmodule Jido.Ecto.TestRepo do
  @moduledoc false

  @adapter Application.compile_env(:jido_ecto, [__MODULE__, :adapter], Ecto.Adapters.SQLite3)

  use Ecto.Repo,
    otp_app: :jido_ecto,
    adapter: @adapter
end
