defmodule System.State.ServicesTest do
  use ExUnit.Case
  alias System.State.PrivilegedServices
  alias System.State.{Services, ServiceAccount, CoreReport}
  alias Block.Extrinsic.{Assurance, Preimage}
  alias Block.Extrinsic.Guarantee.{WorkReport, WorkResult}

  defmodule ConstantsMock do
    def validator_count, do: 3
    def core_count, do: 3
    def gas_accumulation, do: 1000
  end

  setup_all do
    Application.put_env(:jamixir, Constants, ConstantsMock)

    on_exit(fn ->
      Application.delete_env(:jamixir, Constants)
    end)

    # only core index 0 will be considered available (reported availble by more then 2/3 validator set)
    assurances = [
      # Assuring for all three cores
      %Assurance{assurance_values: <<0b111::3>>, validator_index: 0},
      # Assuring for first two cores
      %Assurance{assurance_values: <<0b110::3>>, validator_index: 1},
      # Assuring for first and third cores
      %Assurance{assurance_values: <<0b101::3>>, validator_index: 2}
    ]

    {:ok, assurances: assurances}
  end

  describe "process_preimages/3" do
    test "processes preimages correctly" do
      init_services = %{1 => %ServiceAccount{}, 2 => %ServiceAccount{}}

      preimages = [
        %Preimage{service_index: 1, data: <<1, 2, 3>>},
        %Preimage{service_index: 3, data: <<4, 5, 6>>}
      ]

      ts = 100

      updated = Services.process_preimages(init_services, preimages, ts)

      assert map_size(updated) == 3
      # Service index 2 is not affected
      assert updated[2] == init_services[2]

      # Service index 1 and 3 are updated
      for {idx, data} <- [{1, <<1, 2, 3>>}, {3, <<4, 5, 6>>}] do
        hash = Util.Hash.default(data)
        assert updated[idx].preimage_storage_p[hash] == data
        assert updated[idx].preimage_storage_l[{hash, 3}] == [ts]
      end
    end
  end

  describe "service_index_set/3" do
    test "returns correct set of service indices", %{assurances: assurances} do
      # only core index 0 will be considered available (reported availble by more then 2/3 validator set)
      core_reports = [
        %CoreReport{
          work_report: %WorkReport{work_results: [%{service_index: 1}, %{service_index: 2}]}
        },
        %CoreReport{work_report: %WorkReport{work_results: [%{service_index: 3}]}},
        %CoreReport{work_report: %WorkReport{work_results: [%{service_index: 4}]}}
      ]

      privileged_services = %PrivilegedServices{
        manager_service: 5,
        alter_authorizer_service: 6,
        alter_validator_service: 7
      }

      result =
        Services.service_index_set(assurances, core_reports, privileged_services)

      assert result == MapSet.new([1, 2, 5, 6, 7])
    end

    test "handles empty assurances" do
      assurances = []
      core_reports = []

      privileged_services = %PrivilegedServices{
        manager_service: 1,
        alter_authorizer_service: 2,
        alter_validator_service: 3
      }

      result =
        Services.service_index_set(assurances, core_reports, privileged_services)

      assert result == MapSet.new([1, 2, 3])
    end
  end

  describe "gas_attributable_for_service/4" do
    test "test 1", %{assurances: assurances} do
      # only core index 0 will be considered available (reported availble by more then 2/3 validator set)

      core_reports = [
        %CoreReport{
          work_report: %WorkReport{
            core_index: 0,
            work_results: [
              %WorkResult{service_index: 1, gas_prioritization_ratio: 0},
              %WorkResult{service_index: 2, gas_prioritization_ratio: 1}
            ]
          }
        }
      ]

      # which will give service index 1 and 2
      # Service Accounts 3 and 4 will not be considered
      services_intermediate = %{
        1 => %ServiceAccount{gas_limit_g: 5},
        2 => %ServiceAccount{gas_limit_g: 2},
        3 => %ServiceAccount{gas_limit_g: 150},
        4 => %ServiceAccount{gas_limit_g: 300}
      }

      result_for_service_1 =
        Services.gas_attributable_for_service(1, assurances, core_reports, services_intermediate)

      # Expected calculation:
      # total_gas_limit = 5 + 2  = 7
      # service_gas_limit = 5
      # total_prioritization = 0 + 1 = 1
      # gas share = 0 * div((1000 - 7), 1) + 1 * div((1000 - 7), 1) = 1000 -7 = 993
      # gas_attributable = 5 + 993 = 998
      assert result_for_service_1 == 998

      result_for_service_2 =
        Services.gas_attributable_for_service(2, assurances, core_reports, services_intermediate)

      # Expected calculation:
      # total_gas_limit = 5 + 2  = 7
      # service_gas_limit = 2 / total_prioritization = 1
      # gas share = 1 * div((1000 - 7), 1) = 993
      # gas_attributable = 2 + 993 = 995
      assert result_for_service_2 == 995
    end

    test "test 2", %{assurances: [a1, a2, _]} do
      assurances = [a1, a2, %Assurance{assurance_values: <<0b011::3>>, validator_index: 2}]

      # only core index 1 will be considered available (reported availble by more then 2/3 validator set)

      core_reports = [
        %CoreReport{
          work_report: %WorkReport{
            core_index: 0,
            work_results: [
              %WorkResult{service_index: 1, gas_prioritization_ratio: 2},
              %WorkResult{service_index: 2, gas_prioritization_ratio: 1}
            ]
          }
        },
        %CoreReport{
          work_report: %WorkReport{
            core_index: 0,
            work_results: [
              %WorkResult{service_index: 3, gas_prioritization_ratio: 2}
            ]
          }
        }
      ]

      # which will give service index 3
      services_intermediate = %{
        1 => %ServiceAccount{gas_limit_g: 200},
        2 => %ServiceAccount{gas_limit_g: 100},
        3 => %ServiceAccount{gas_limit_g: 150}
      }

      result_1 =
        Services.gas_attributable_for_service(1, assurances, core_reports, services_intermediate)

      # Expected calculation:
      # total_gas_limit = 150 / service_gas_limit = 0 / total_prioritization = 2
      # gas share = 2 * div((1000 - 150), 2) = 2 * 425 = 850
      # gas_attributable = 0 + 850 = 850
      assert result_1 == 850

      result_3 =
        Services.gas_attributable_for_service(3, assurances, core_reports, services_intermediate)

      # Expected calculation:
      # total_gas_limit = 150 / service_gas_limit = 150 / total_prioritization = 2
      # gas share = 2 * div((1000 - 150), 2) = 2 * 425 = 850
      # gas_attributable = 150 + 850 = 1000
      assert result_3 == 1000
    end
  end
end
