defmodule PVM.RefineIntegrationTest do
  use ExUnit.Case
  alias System.State.ServiceAccount
  alias Util.Hash
  alias PVM.RefineParams
  import Mox

  setup :verify_on_exit!

  describe "refine/2" do
    @tag :skip
    # test not ready yet
    test "successfully processes a valid program" do
      # Mock ServiceAccount.historical_lookup to return a valid binary

      # Create a valid program binary with an ecall instruction
      page_size = 4096
      # 10 is the opcode for ecall, 19 is the opcode for peek
      program = <<0, 1, 2, 10, 19, 1, 0>>
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
        byte_size(program)::little-size(32),
        # c
        program::binary
      >>

      hash = Hash.default(binary)

      service_account = %ServiceAccount{
        preimage_storage_p: %{hash => binary},
        preimage_storage_l: %{{hash, byte_size(binary)} => [0]}
      }

      # Define parameters for refine
      params = %RefineParams{
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

      # Call refine and assert the result
      assert {:ok, _result} = PVM.refine(params, services)
    end
  end
end
