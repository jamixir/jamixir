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

      
      assert {<<>>, []} = PVM.refine(params, services)
    end

    test "test-ecall-1" do
      program = <<op(:ecalli), 18, op(:fallthrough), op(:ecalli), 0, op(:fallthrough)>>

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
      r = PVM.refine(params, services)

      assert r == {<<>>, []}
    end

    test "executes all host functions" do
      # Program that exercises all refine host calls
      program =
        <<
          # historical_lookup
          op(:ecalli),
          15,
          op(:fallthrough),
          # import
          op(:ecalli),
          16,
          op(:fallthrough),
          # export
          op(:ecalli),
          17,
          op(:fallthrough),
          # machine
          op(:ecalli),
          18,
          op(:fallthrough),
          # peek
          op(:ecalli),
          19,
          op(:fallthrough),
          # poke
          op(:ecalli),
          20,
          op(:fallthrough),
          # zero
          op(:ecalli),
          21,
          op(:fallthrough),
          # void
          op(:ecalli),
          22,
          op(:fallthrough),
          # invoke
          op(:ecalli),
          23,
          op(:fallthrough),
          # expunge
          op(:ecalli),
          24,
          op(:fallthrough),
          # other
          op(:ecalli),
          89,
          op(:fallthrough)
        >>

      bitmask =
        <<1, 0, 1>> <>
          <<1, 0, 1>> <>
          <<1, 0, 1>> <>
          <<1, 0, 1>> <>
          <<1, 0, 1>> <>
          <<1, 0, 1>> <>
          <<1, 0, 1>> <>
          <<1, 0, 1>> <>
          <<1, 0, 1>> <>
          <<1, 0, 1>> <>
          <<1, 0, 1>>

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
        extrinsic_data: [],
        import_segments: [],
        export_offset: 0
      }

      services = %{1 => service_account}

      {result, exports} = PVM.refine(params, services)

      assert result == <<>>
      assert exports == []
    end
  end
end
