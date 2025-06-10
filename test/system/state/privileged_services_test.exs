defmodule System.State.PrivilegedServicesTest do
  alias System.State.PrivilegedServices
  alias Codec.JsonEncoder
  use ExUnit.Case
  import Codec.Encoder
  import Jamixir.Factory

  describe "encode/1" do
    test "encode smoke test" do
      assert Codec.Encoder.encode(build(:privileged_services)) ==
        <<1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0, 4, 0, 0, 0, 4, 1, 131, 232, 2,
        135, 208, 3, 139, 184, 4, 143, 160>>
    end
  end

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
               chi_v: ps.next_validators_service,
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
