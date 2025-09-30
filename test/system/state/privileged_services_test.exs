defmodule System.State.PrivilegedServicesTest do
  alias Codec.JsonEncoder
  alias System.State.PrivilegedServices
  use ExUnit.Case
  import Codec.Encoder
  import Jamixir.Factory

  describe "decode/1" do
    test "decode smoke test" do
      ps = build(:privileged_services)

      assert PrivilegedServices.decode(e(ps)) == {ps, <<>>}
    end
  end

  describe "to_json/1" do
    test "encodes a privileged services to json" do
      ps = build(:privileged_services)

      assert JsonEncoder.encode(ps) == %{
               chi_m: ps.manager,
               chi_a: ps.assigners,
               chi_v: ps.delegator,
               chi_r: ps.registrar,
               chi_g: [
                 %{service: 1, gas: 1000},
                 %{service: 2, gas: 2000},
                 %{service: 3, gas: 3000},
                 %{service: 4, gas: 4000}
               ]
             }
    end
  end
end
