defmodule PVM.ServicesTest do
  alias PVM.ArgInvoc
  alias PVM.Host.Refine
  alias PVM.Accumulate
  alias System.State.{Accumulation, ServiceAccount}
  import Codec.Encoder
  use ExUnit.Case

  import PVM.Utils.AddInstruction

  def make_accumulate_args(bin) do
    code_hash = Util.Hash.default(bin)

    mock_metadata = <<1, 2, 3>>
    bin_with_metadata = e(vs(mock_metadata)) <> bin

    accumulation = %Accumulation{
      services: %{
        0 => %ServiceAccount{
          code_hash: code_hash,
          preimage_storage_p: %{code_hash => bin_with_metadata},
          storage:
            HashedKeysMap.new(%{{code_hash, byte_size(bin_with_metadata)} => bin_with_metadata})
        }
      }
    }

    # Return tuple with all necessary args in order
    {
      # accumulation_state
      accumulation,
      # timeslot
      1,
      # service_index
      0,
      # gas
      10000,
      # operands
      [],
      # extra_args
      %{n0_: Util.Hash.one()}
    }
  end

  describe "ArgInvoke/3" do
    test "smoke" do
      bin = PVM.Helper.init_bin(Services.Fibonacci.program())

      opts =
        case System.get_env("PVM_TRACE") do
          "true" -> Keyword.put([], :trace, true)
          _ -> []
        end

      f = fn n ->
        IO.puts("n: #{n}")
      end

      {_gas_, memory_read, _context_} =
        ArgInvoc.execute(bin, 0, 10000, <<>>, f, %Refine.Context{}, opts)

      assert memory_read == <<>>
    end
  end

  test "accumulate execution" do
    bin =
      Services.Fibonacci.program()
      |> :binary.bin_to_list()
      |> insert_instruction(2, [0, 0, 0, 0, 0], [0, 0, 0, 0, 0])
      |> PVM.Helper.init_bin()

    {accumulation, timeslot, service_index, gas, operands, extra_args} = make_accumulate_args(bin)
    result = Accumulate.execute(accumulation, timeslot, service_index, gas, operands, extra_args)
    assert match?({^accumulation, [], nil, _gas, []}, result)
  end
end
