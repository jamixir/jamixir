defmodule PVM.RefineIntegrationTest do
  use ExUnit.Case
  alias System.State.ServiceAccount
  alias Util.Hash
  alias PVM.Refine.Params
  import Mox
  use PVM.Instructions

  setup :verify_on_exit!

  describe "refine/2" do
    test "successfully processes a valid program" do
      # Mock ServiceAccount.historical_lookup to return a valid binary

      # Create a valid program binary with an ecall instruction
      # 10 is the opcode for ecall, 18 is the opcode for machine
      program = <<op(:ecalli), 18, op(:fallthrough)>>

      bitmask = <<1, 0, 1>>
      binary = PVM.Helper.init(program, bitmask)

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

    test "test-ecall-1" do
      # Mock ServiceAccount.historical_lookup to return a valid binary

      # Create a valid program binary with an ecall instruction
      # 10 is the opcode for ecall, 18 is the opcode for machine
      program = <<op(:ecalli), 18, op(:fallthrough), op(:ecalli), 1, op(:fallthrough)>>

      bitmask = <<1, 0, 1, 1, 0, 1>>
      binary = PVM.Helper.init(program, bitmask)

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
      r = PVM.Refine.execute(params, services)

      assert r == {<<>>, []}
    end
  end
end
