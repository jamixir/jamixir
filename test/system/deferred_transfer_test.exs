defmodule System.DeferredTransferTest do
  alias System.DeferredTransfer
  use ExUnit.Case
  import Codec.Encoder

  test "encode and decode deferred transfer" do
    dt = %DeferredTransfer{
      sender: 123,
      receiver: 456,
      amount: 1_000_000,
      memo: String.duplicate("x", Constants.memo_size()),
      gas_limit: 50_000
    }

    {decoded, <<>>} = DeferredTransfer.decode(e(dt))

    assert dt == decoded
  end
end
