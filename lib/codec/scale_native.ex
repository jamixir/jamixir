defmodule Jamixir.ScaleNative do
  @on_load :load_nifs

  def load_nifs do
    path = :code.priv_dir(:my_scale_project) |> to_string
    :erlang.load_nif("#{path}/native/target/release/libscale_encoder", 0)
  end

  def encode_u32(_number), do: :erlang.nif_error(:nif_not_loaded)
end
