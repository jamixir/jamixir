defmodule System.State.AccumulationTest do
  use ExUnit.Case
  import Mox

  setup :verify_on_exit!

  alias System.State.Accumulation
  alias System.AccumulationState
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Block.Extrinsic.Guarantee.WorkResult
  alias Block.Extrinsic.AvailabilitySpecification
  alias System.State.PrivilegedServices

  import Jamixir.Factory

  describe "validate_services/2" do
    test "returns :ok when all indices exist" do
      state = %AccumulationState{services: %{1 => :service1, 2 => :service2, 3 => :service3}}
      assert :ok == Accumulation.validate_services(state, MapSet.new([1, 2, 3]))
    end

    test "returns error when any index is missing" do
      state = %AccumulationState{services: %{1 => :service1, 2 => :service2}}

      assert {:error, :invalid_service} ==
               Accumulation.validate_services(state, MapSet.new([1, 2, 3]))
    end
  end

  describe "calculate_i/2" do
    setup do
      work_reports = [
        %WorkReport{results: [%{gas_ratio: 10}]},
        %WorkReport{results: [%{gas_ratio: 20}]},
        %WorkReport{results: [%{gas_ratio: 30}]},
        %WorkReport{results: [%{gas_ratio: 40}]}
      ]

      {:ok, work_reports: work_reports}
    end

    test "returns correct i when gas limit is reached in the middle", %{
      work_reports: work_reports
    } do
      assert 2 == Accumulation.calculate_i(work_reports, 35)
    end

    test "returns length - 1 when all work reports can be included", %{work_reports: work_reports} do
      assert 4 == Accumulation.calculate_i(work_reports, 100)
    end

    test "returns 0 when no work reports can be included", %{work_reports: work_reports} do
      assert 0 == Accumulation.calculate_i(work_reports, 5)
    end
  end

  describe "collect_services/2" do
    test "returns a MapSet with keys from both inputs" do
      work_reports = [
        %WorkReport{results: [%{service: 1}, %{service: 2}]},
        %WorkReport{results: [%{service: 3}]}
      ]

      always_acc_services = %{4 => 100, 5 => 200}

      assert MapSet.new([1, 2, 3, 4, 5]) ==
               Accumulation.collect_services(work_reports, always_acc_services)
    end

    test "handles one or both inputs being empty" do
      assert MapSet.new([1, 2]) == Accumulation.collect_services([], %{1 => 100, 2 => 200})

      assert MapSet.new([3, 4]) ==
               Accumulation.collect_services(
                 [%WorkReport{results: [%{service: 3}, %{service: 4}]}],
                 %{}
               )

      assert MapSet.new() == Accumulation.collect_services([], %{})
    end

    test "handles key collisions correctly" do
      work_reports = [%WorkReport{results: [%{service: 1}, %{service: 2}]}]
      always_acc_services = %{2 => 100, 3 => 200}

      assert MapSet.new([1, 2, 3]) ==
               Accumulation.collect_services(work_reports, always_acc_services)
    end
  end

  setup_all do
    service = 1
    base_work_result = build(:work_result, service: service, gas_ratio: 0)
    base_work_report = build(:work_report, results: [base_work_result])

    {:ok,
     service: service, base_work_result: base_work_result, base_work_report: base_work_report}
  end

  describe "pre_single_accumulation/3" do
    test "initial_g from service_dict", %{service: service} do
      service_dict = %{1 => 100}
      work_reports = []

      assert {100, []} ==
               Accumulation.pre_single_accumulation(work_reports, service_dict, service)
    end

    test "initial_g is 0 when service not in service_dict", %{service: service} do
      service_dict = %{2 => 100}
      work_reports = []

      assert {0, []} ==
               Accumulation.pre_single_accumulation(work_reports, service_dict, service)
    end

    test "g is sum of all gas_ratio values for the service", %{
      service: service,
      base_work_report: base_wr,
      base_work_result: base_wr_result
    } do
      service_dict = %{}

      work_reports = [
        %{
          base_wr
          | results: [
              put_in(base_wr_result.gas_ratio, 10),
              put_in(base_wr_result.gas_ratio, 20)
            ]
        },
        %{base_wr | results: [put_in(base_wr_result.gas_ratio, 30)]},
        # Should be ignored
        %{base_wr | results: [%{base_wr_result | gas_ratio: 40, service: 2}]}
      ]

      {g, _p} = Accumulation.pre_single_accumulation(work_reports, service_dict, service)
      assert g == 60
    end

    test "p contains correct o_tuples", %{
      service: service,
      base_work_report: base_wr,
      base_work_result: base_wr_result
    } do
      service_dict = %{}

      work_reports = [
        %WorkReport{
          base_wr
          | results: [
              %WorkResult{
                base_wr_result
                | gas_ratio: 10,
                  result: "result1",
                  payload_hash: "hash1"
              },
              %WorkResult{
                base_wr_result
                | gas_ratio: 20,
                  result: "result2",
                  payload_hash: "hash2"
              }
            ],
            output: "output1",
            specification: %AvailabilitySpecification{work_package_hash: "wph1"}
        },
        %WorkReport{
          base_wr
          | results: [
              %WorkResult{
                base_wr_result
                | gas_ratio: 30,
                  result: "result3",
                  payload_hash: "hash3"
              }
            ],
            output: "output2",
            specification: %AvailabilitySpecification{work_package_hash: "wph2"}
        }
      ]

      {g, p} = Accumulation.pre_single_accumulation(work_reports, service_dict, service)
      assert g == 60
      assert length(p) == 3
      assert Enum.all?(p, fn %{o: _, l: _, a: _, k: _} -> true end)

      assert p == [
               %{o: "result3", l: "hash3", a: "output2", k: "wph2"},
               %{o: "result2", l: "hash2", a: "output1", k: "wph1"},
               %{o: "result1", l: "hash1", a: "output1", k: "wph1"}
             ]
    end

    test "handles empty work_reports", %{service: service} do
      service_dict = %{1 => 100}
      work_reports = []

      assert {100, []} ==
               Accumulation.pre_single_accumulation(work_reports, service_dict, service)
    end

    test "handles service not present in any WorkReport", %{
      service: service,
      base_work_report: base_wr,
      base_work_result: base_wr_result
    } do
      service_dict = %{}

      work_reports = [
        %{base_wr |
          results: [
            %{base_wr_result |
              service: 2,
              gas_ratio: 10
            },
            %{base_wr_result |
              service: 2,
              gas_ratio: 20
            }
          ]
        }
      ]

      assert {0, []} ==
               Accumulation.pre_single_accumulation(work_reports, service_dict, service)
    end
  end

  describe "update_accumulation_state/4" do
    test "updates state correctly" do
      initial_state = %AccumulationState{
        privileged_services: %PrivilegedServices{
          manager_service: 1,
          alter_authorizer_service: 2,
          alter_validator_service: 3
        },
        services: %{1 => :service1, 2 => :service2, 3 => :service3}
      }

      work_reports = []
      always_acc_services = %{}
      s = MapSet.new([1, 2, 3])

      # Set up expectations for single_accumulation calls
      MockAccumulation
      |> expect(:single_accumulation, fn ^initial_state, ^work_reports, ^always_acc_services, 1 ->
        %AccumulationResult{
          state: %AccumulationState{privileged_services: %PrivilegedServices{manager_service: 11}}
        }
      end)
      |> expect(:single_accumulation, fn ^initial_state, ^work_reports, ^always_acc_services, 2 ->
        %AccumulationResult{
          state: %AccumulationState{privileged_services: %PrivilegedServices{alter_authorizer_service: 22}}
        }
      end)
      |> expect(:single_accumulation, fn ^initial_state, ^work_reports, ^always_acc_services, 3 ->
        %AccumulationResult{
          state: %AccumulationState{privileged_services: %PrivilegedServices{alter_validator_service: 33}}
        }
      end)
      |> expect(:single_accumulation, 3, fn ^initial_state, ^work_reports, ^always_acc_services, service ->
        %AccumulationResult{state: %AccumulationState{services: %{service => :updated_service}}}
      end)

      updated_state = Accumulation.update_accumulation_state(initial_state, work_reports, always_acc_services, s)

      assert updated_state.privileged_services == %PrivilegedServices{
        manager_service: 11,
        alter_authorizer_service: 22,
        alter_validator_service: 33
      }
      assert updated_state.services == %{1 => :updated_service, 2 => :updated_service, 3 => :updated_service}
    end
  end
end
