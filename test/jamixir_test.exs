defmodule JamixirTest do
  use ExUnit.Case
  doctest Jamixir

  test "greets the world" do
    assert Jamixir.hello() == :world
  end
end
