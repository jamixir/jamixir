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
    test "successfully processes a valid program" do
      program =
        Services.Fibonacci.program()
        |> PVM.Helper.init_bin()

      %{services: services, work_package: work_package} = make_executable_work_package(program)

      assert {<<>>, [], 59} = PVM.refine(0, work_package, <<>>, [], 0, services, %{})
    end

    test "test-ecall-1" do
      program =
        <<op(:ecalli), host(:machine), op(:fallthrough), op(:ecalli), host(:gas),
          op(:fallthrough), op(:fallthrough), op(:fallthrough)>>

      bitmask = <<183>>
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

      assert r == {<<>>, [], 27}
    end
  end
end
