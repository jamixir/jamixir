defmodule Util.Bandersnatch do
  def _verify(_public_key, _input_data, _aux_data, _signature),
    # do: :erlang.nif_error(:nif_not_loaded)
    do: {true, 0x01}

  def _sign(_secret_key, _input_data, _aux_data),
    # do: :erlang.nif_error(:nif_not_loaded)
    do: "signature"
end
