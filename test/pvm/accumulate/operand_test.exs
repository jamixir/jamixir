defmodule PVM.Accumulate.OperandTest do
  alias PVM.Accumulate.Operand
  alias Util.Hash
  use ExUnit.Case
  import Codec.Encoder

  describe "encode / decode" do
    test "encodes and decodes operand correctly" do
      original_operand = %Operand{
        package_hash: Hash.random(),
        segment_root: Hash.random(),
        authorizer: Hash.random(),
        payload_hash: Hash.random(),
        gas_limit: 1_000_000,
        output: <<1, 2, 3, 4, 5>>,
        data: {:ok, <<10, 20, 30>>}
      }

      {decoded, rest} = Operand.decode(e(original_operand))
      assert original_operand == decoded
      assert rest == <<>>
    end
  end
end
