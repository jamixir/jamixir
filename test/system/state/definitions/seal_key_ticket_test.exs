defmodule System.State.SealKeyTicketTest do
  alias System.State.SealKeyTicket
  use ExUnit.Case
  import Codec.Encoder
  import Jamixir.Factory

  describe "encode/1" do
    test "encode smoke test" do
      ticket = build(:single_seal_key_ticket)
      {decoded, _} = SealKeyTicket.decode(e(ticket))
      assert decoded == ticket
    end

    test "encode ticket with big attempt" do
      ticket = build(:single_seal_key_ticket, attempt: 255)
      {decoded, _} = SealKeyTicket.decode(e(ticket))
      assert decoded == ticket
    end
  end
end
