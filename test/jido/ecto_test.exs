defmodule Jido.EctoTest do
  use ExUnit.Case, async: true

  doctest Jido.Ecto

  test "declares the planned integration surfaces" do
    assert Jido.Ecto.capabilities() == [:storage, :persist]
  end
end
