defmodule BlockTest do
  alias Block.Extrinsic.Guarantee
  alias Block.Extrinsic.Disputes
  alias System.State.Ticket
  alias Block.Extrinsic
  use ExUnit.Case
  import TestHelper

  describe "encode/1" do
    test "encode block smoke test" do
      Codec.Encoder.encode(%Block{
        extrinsic: %Extrinsic{
          tickets: [%Ticket{}],
          disputes: %Disputes{},
          preimages: [%{}],
          availability: [%{}],
          guarantees: [%Guarantee{}]
        },
        header: %Block.Header{}
      })
    end
  end
end
