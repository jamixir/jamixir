defmodule PVM.RefineIntegrationTest do
  use ExUnit.Case
  alias Block.Extrinsic.{WorkItem, WorkPackage}
  alias System.State.ServiceAccount
  alias Util.Hash
  import Mox
  use PVM.Instructions
  import PVM.Constants.HostCallId

  setup :verify_on_exit!

  def make_executable_work_package(bin, service_account_index \\ 0) do
    code_hash = Hash.default(bin)
    auth_code = Hash.two()
    auth_code_hash = Hash.default(auth_code)

    service_account = %ServiceAccount{
      preimage_storage_p: %{code_hash => bin, auth_code_hash => auth_code},
      preimage_storage_l: %{
        {code_hash, byte_size(bin)} => [0],
        {auth_code_hash, byte_size(auth_code)} => [0]
      }
    }

    services = %{service_account_index => service_account}

    work_item = %WorkItem{
      code_hash: code_hash,
      service: service_account_index,
      refine_gas_limit: 1000
    }

    work_package = %WorkPackage{
      work_items: [work_item],
      service: service_account_index,
      authorization_code_hash: auth_code_hash
    }

    %{services: services, work_package: work_package}
  end

  describe "refine/2" do
    @tag :skip
    test "successfully processes a valid program" do
      program = <<op(:ecalli), 18, op(:fallthrough)>>

      bitmask = <<1, 0, 1>>
      binary = PVM.Helper.init(program, bitmask)

      %{services: services, work_package: work_package} = make_executable_work_package(binary)

      assert {<<>>, []} = PVM.refine(0, work_package, <<>>, [], 0, services, %{})
    end

    test "test-ecall-1" do
      program =
        <<op(:ecalli), host(:machine), op(:fallthrough), op(:ecalli), host(:gas),
          op(:fallthrough)>>

      bitmask = <<1, 0, 1, 1, 0, 1>>
      binary = PVM.Helper.init(program, bitmask)

      hash = Hash.default(binary)
      auth_code = Hash.two()
      auth_code_hash = Hash.default(auth_code)

      service_account = %ServiceAccount{
        preimage_storage_p: %{hash => binary, auth_code_hash => auth_code},
        preimage_storage_l: %{
          {hash, byte_size(binary)} => [0],
          {auth_code_hash, byte_size(auth_code)} => [0]
        }
      }

      services = %{1 => service_account}

      w = %WorkItem{
        service: 1,
        refine_gas_limit: 1000,
        code_hash: hash
      }

      wp = %WorkPackage{
        work_items: [w],
        service: 1,
        authorization_code_hash: auth_code_hash
      }

      r = PVM.refine(0, wp, <<>>, [], 0, services, %{})

      assert r == {<<>>, []}
    end

    @tag :skip
    test "executes all host functions" do
      # Program that exercises all refine host calls
      program =
        <<
          # historical_lookup
          op(:ecalli),
          host(:historical_lookup),
          op(:fallthrough),
          # import
          op(:ecalli),
          host(:fetch),
          op(:fallthrough),
          # export
          op(:ecalli),
          host(:export),
          op(:fallthrough),
          # machine
          op(:ecalli),
          host(:machine),
          op(:fallthrough),
          # peek
          op(:ecalli),
          host(:peek),
          op(:fallthrough),
          # poke
          op(:ecalli),
          host(:poke),
          op(:fallthrough),
          # zero
          op(:ecalli),
          host(:zero),
          op(:fallthrough),
          # void
          op(:ecalli),
          host(:void),
          op(:fallthrough),
          # invoke
          op(:ecalli),
          host(:invoke),
          op(:fallthrough),
          # expunge
          op(:ecalli),
          host(:expunge),
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
      auth_code = Hash.two()
      auth_code_hash = Hash.default(auth_code)

      service_account = %ServiceAccount{
        preimage_storage_p: %{hash => binary, auth_code_hash => auth_code},
        preimage_storage_l: %{
          {hash, byte_size(binary)} => [0],
          {auth_code_hash, byte_size(auth_code)} => [0]
        }
      }

      services = %{1 => service_account}

      w = %WorkItem{
        service: 1,
        refine_gas_limit: 1000,
        code_hash: hash
      }

      wp = %WorkPackage{
        work_items: [w],
        service: 1,
        authorization_code_hash: auth_code_hash
      }

      {result, exports} = PVM.refine(0, wp, <<>>, [], 0, services, %{})

      assert result == <<>>
      assert exports == []
    end
  end
end
