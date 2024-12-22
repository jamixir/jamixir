defmodule PVM.RefineIntegrationTest do
  use ExUnit.Case
  alias System.State.ServiceAccount
  alias Util.Hash
  alias PVM.Refine.Params
  import Mox
  use PVM.Instructions
  alias PVM.Utils.ProgramUtils

  setup :verify_on_exit!

  describe "refine/2" do
    # @tag :skip
    # test not ready yet
    test "successfully processes a valid program" do
      # Mock ServiceAccount.historical_lookup to return a valid binary

      # Create a valid program binary with an ecall instruction
      page_size = 32
      # 10 is the opcode for ecall, 19 is the opcode for peek
      program = <<op(:ecalli), 18, op(:fallthrough)>>

      bitmask = <<1, 0, 1>>
      {program, bitmask} = ProgramUtils.append_halt(program, bitmask)
      z = 1
      jump_table = []
      p = <<length(jump_table), z, byte_size(program)>> <> program <> bitmask
      test_pattern = :binary.copy(<<65>>, page_size)

      binary = <<
        # o_size
        page_size::little-size(24),
        # w_size
        page_size::little-size(24),
        # z
        1::little-size(16),
        # s
        1::little-size(24),
        # o
        test_pattern::binary,
        # w
        test_pattern::binary,
        # c_size
        byte_size(p)::little-size(32),
        # c
        p::binary
      >>

      hash = Hash.default(binary)

      service_account = %ServiceAccount{
        preimage_storage_p: %{hash => binary},
        preimage_storage_l: %{{hash, byte_size(binary)} => [0]}
      }

      # Define parameters for refine
      params = %Params{
        service: 1,
        gas: 1000,
        service_code: hash,
        payload: <<>>,
        work_package_hash: <<>>,
        refinement_context: %RefinementContext{},
        authorizer_hash: <<>>,
        output: <<>>,
        extrinsic_data: []
      }

      services = %{1 => service_account}

      assert {<<>>, []} = PVM.Refine.execute(params, services)
    end
  end
end
