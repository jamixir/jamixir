defmodule RingVRF.RingCommitment do
  @enforce_keys [:points, :ring_selector]
  defstruct points: [], ring_selector: nil

  @element_size 48

  def encode(%__MODULE__{points: [p1, p2], ring_selector: rs}) do
    p1_bin = :erlang.list_to_binary(p1)
    p2_bin = :erlang.list_to_binary(p2)
    rs_bin = :erlang.list_to_binary(rs)
    <<p1_bin::binary, p2_bin::binary, rs_bin::binary>>
  end

  def decode(
        <<p1::binary-size(@element_size), p2::binary-size(@element_size),
          rs::binary-size(@element_size)>>
      ) do
    %__MODULE__{
      points: [:erlang.binary_to_list(p1), :erlang.binary_to_list(p2)],
      ring_selector: [:erlang.binary_to_list(rs)]
    }
  end
end
