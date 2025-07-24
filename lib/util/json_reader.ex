defmodule JsonReader do
  def read(file) do
    File.read!(file)
    |> Jason.decode!()
    |> Utils.atomize_keys()
  end
end
