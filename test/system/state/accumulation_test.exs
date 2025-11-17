defmodule System.State.AccumulationTest do
  alias System.DeferredTransfer
  alias Block.Extrinsic.Preimage
  alias Block.Extrinsic.AvailabilitySpecification
  alias Block.Extrinsic.Guarantee.{WorkDigest, WorkReport}
  alias PVM.Accumulate
  alias System.AccumulationResult
  alias System.State
  alias System.State.{Accumulation, PrivilegedServices, Ready, ServiceAccount}
  alias System.State.RecentHistory.AccumulationOutput
  import Jamixir.Factory
  import Mox
  import Util.Hash
  import Codec.Encoder
  use ExUnit.Case
  setup :verify_on_exit!

  defp setup_mock_accumulation do
    Application.put_env(:jamixir, :accumulation_module, MockAccumulation)
    Mox.set_mox_global()

    on_exit(fn ->
      Application.put_env(:jamixir, :accumulation_module, System.State.Accumulation)
      Mox.set_mox_private()
    end)

    :ok
  end

  defp base_accumulation_state(overrides) do
    base = %Accumulation{
      manager: 1,
      assigners: [99, 100],
      delegator: 101,
      next_validators: [<<1>>, <<2>>],
      authorizer_queue: [[<<0, 0>>, <<0, 1>>], [<<1, 0>>, <<1, 1>>]],
      services: %{4 => :service4, 5 => :service5, 6 => :service6}
    }

    Map.merge(base, overrides)
  end

  defp base_extra_args(overrides \\ %{}) do
    base = %{
      timeslot_: Enum.random(1..1000),
      n0_: Util.Hash.one()
    }

    Map.merge(base, overrides)
  end

  defp simple_work_report(service, gas_ratio) do
    %WorkReport{digests: [%WorkDigest{service: service, gas_ratio: gas_ratio}]}
  end

  setup_all do
    service = 1
    base_work_digest = build(:work_digest, service: service, gas_ratio: 0)
    base_work_report = build(:work_report, digests: [base_work_digest])

    {:ok,
     service: service, base_work_digest: base_work_digest, base_work_report: base_work_report}
  end

  describe "number_of_work_reports_to_accumumulate/2" do
    setup do
      work_reports = [
        %WorkReport{digests: [%{gas_ratio: 10}]},
        %WorkReport{digests: [%{gas_ratio: 20}]},
        %WorkReport{digests: [%{gas_ratio: 30}]},
        %WorkReport{digests: [%{gas_ratio: 40}]}
      ]

      {:ok, work_reports: work_reports}
    end

    test "returns correct i when gas limit is reached in the middle", %{
      work_reports: work_reports
    } do
      assert 2 == Accumulation.number_of_work_reports_to_accumumulate(work_reports, 35)
    end

    test "returns length - 1 when all work reports can be included", %{work_reports: work_reports} do
      assert 4 == Accumulation.number_of_work_reports_to_accumumulate(work_reports, 100)
    end

    test "returns 0 when no work reports can be included", %{work_reports: work_reports} do
      assert 0 == Accumulation.number_of_work_reports_to_accumumulate(work_reports, 5)
    end
  end

  describe "collect_services/2" do
    test "returns a MapSet with keys from both inputs" do
      work_reports = [
        %WorkReport{digests: [%{service: 1}, %{service: 2}]},
        %WorkReport{digests: [%{service: 3}]}
      ]

      always_acc_services = %{4 => 100, 5 => 200}

      assert MapSet.new([1, 2, 3, 4, 5]) ==
               Accumulation.collect_services(work_reports, always_acc_services, [])
    end

    test "handles one or both inputs being empty" do
      assert MapSet.new([1, 2]) == Accumulation.collect_services([], %{1 => 100, 2 => 200}, [])

      assert MapSet.new([3, 4]) ==
               Accumulation.collect_services(
                 [%WorkReport{digests: [%{service: 3}, %{service: 4}]}],
                 %{},
                 []
               )

      assert MapSet.new() == Accumulation.collect_services([], %{}, [])
    end

    test "handles key collisions correctly" do
      work_reports = [%WorkReport{digests: [%{service: 1}, %{service: 2}]}]
      always_acc_services = %{2 => 100, 3 => 200}

      assert MapSet.new([1, 2, 3]) ==
               Accumulation.collect_services(work_reports, always_acc_services, [])
    end

    test "handles deferred transfers correctly" do
      work_reports = [%WorkReport{digests: [%{service: 1}, %{service: 2}]}]
      always_acc_services = %{3 => 100}
      deferred_transfers = [%DeferredTransfer{receiver: 4}, %DeferredTransfer{receiver: 5}]

      assert MapSet.new([1, 2, 3, 4, 5]) ==
               Accumulation.collect_services(
                 work_reports,
                 always_acc_services,
                 deferred_transfers
               )
    end
  end

  describe "pre_single_accumulation/3" do
    test "initial_g from service_dict", %{service: service} do
      service_dict = %{1 => 100}
      work_reports = []

      assert {100, []} ==
               Accumulation.pre_single_accumulation(work_reports, [], service_dict, service)
    end

    test "initial_g is 0 when service not in service_dict", %{service: service} do
      service_dict = %{2 => 100}
      work_reports = []

      assert {0, []} ==
               Accumulation.pre_single_accumulation(work_reports, [], service_dict, service)
    end

    test "filters only transfer for service", %{service: service} do
      service_dict = %{2 => 100}
      [t1, t2] = [%DeferredTransfer{amount: 10, receiver: service}, %DeferredTransfer{amount: 20}]

      assert {0, [t1]} ==
               Accumulation.pre_single_accumulation([], [t1, t2], service_dict, service)
    end

    test "g is sum of all gas_ratio values for the service", %{
      service: service,
      base_work_report: base_wr,
      base_work_digest: base_wr_digest
    } do
      service_dict = %{}

      work_reports = [
        %{
          base_wr
          | digests: [
              put_in(base_wr_digest.gas_ratio, 10),
              put_in(base_wr_digest.gas_ratio, 20)
            ]
        },
        %{base_wr | digests: [put_in(base_wr_digest.gas_ratio, 30)]},
        # Should be ignored
        %{base_wr | digests: [%{base_wr_digest | gas_ratio: 40, service: 2}]}
      ]

      {g, _p} = Accumulation.pre_single_accumulation(work_reports, [], service_dict, service)
      assert g == 60
    end

    test "p contains correct o_tuples", %{
      service: service,
      base_work_report: base_wr,
      base_work_digest: base_wr_digest
    } do
      service_dict = %{}

      work_reports = [
        %WorkReport{
          base_wr
          | digests: [
              %WorkDigest{
                base_wr_digest
                | gas_ratio: 10,
                  result: "result1",
                  payload_hash: "hash1"
              },
              %WorkDigest{
                base_wr_digest
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
          | digests: [
              %WorkDigest{
                base_wr_digest
                | gas_ratio: 30,
                  result: "result3",
                  payload_hash: "hash3"
              }
            ],
            output: "output2",
            specification: %AvailabilitySpecification{work_package_hash: "wph2"}
        }
      ]

      {g, p} = Accumulation.pre_single_accumulation(work_reports, [], service_dict, service)
      assert g == 60

      assert p == [
               %Accumulate.Operand{
                 output: "output1",
                 data: "result1",
                 segment_root: zero(),
                 authorizer: two(),
                 payload_hash: "hash1",
                 package_hash: "wph1",
                 gas_limit: 10
               },
               %Accumulate.Operand{
                 output: "output1",
                 data: "result2",
                 segment_root: zero(),
                 authorizer: two(),
                 payload_hash: "hash2",
                 package_hash: "wph1",
                 gas_limit: 20
               },
               %Accumulate.Operand{
                 output: "output2",
                 data: "result3",
                 segment_root: zero(),
                 authorizer: two(),
                 payload_hash: "hash3",
                 package_hash: "wph2",
                 gas_limit: 30
               }
             ]
    end

    test "handles empty work_reports", %{service: service} do
      service_dict = %{1 => 100}
      work_reports = []

      assert {100, []} ==
               Accumulation.pre_single_accumulation(work_reports, [], service_dict, service)
    end

    test "handles service not present in any WorkReport", %{
      service: service,
      base_work_report: base_wr,
      base_work_digest: base_wr_digest
    } do
      service_dict = %{}

      work_reports = [
        %{
          base_wr
          | digests: [
              %{base_wr_digest | service: 2, gas_ratio: 10},
              %{base_wr_digest | service: 2, gas_ratio: 20}
            ]
        }
      ]

      assert {0, []} ==
               Accumulation.pre_single_accumulation(work_reports, [], service_dict, service)
    end
  end

  describe "parallelized_accumulation/3" do
    setup do
      setup_mock_accumulation()

      :ok
    end

    test "performs parallelized_accumulation correctly" do
      # Setup test data
      services = %{4 => :service4, 5 => :service5}
      always_acc_services = %{6 => 30}

      initial_state = base_accumulation_state(%{services: services})

      work_reports = [simple_work_report(4, 10), simple_work_report(5, 20)]

      extra_args = base_extra_args(%{timeslot_: 100})

      # Mock accumulation behavior
      MockAccumulation
      |> stub(:single_accumulation, fn _, _, _, _, service, _ ->
        case service do
          # Regular services return updated state + outputs
          s when s in [4, 5] ->
            %AccumulationResult{
              state: %{initial_state | services: %{service => :"updated_service#{service}"}},
              transfers: [%{amount: service * 10}],
              output: "output#{service}",
              gas_used: service * 10
            }

          # Manager updates privileged services
          1 ->
            %AccumulationResult{
              state: %{
                initial_state
                | manager: 2,
                  assigners: [99, 100],
                  delegator: 101,
                  always_accumulated: %{6 => 130}
              }
            }

          # Privileged services update their respective fields
          s when s in [99, 100] ->
            %AccumulationResult{
              state: %{
                initial_state
                | assigners: [10_001, 10_002],
                  authorizer_queue: [[<<0, 0, 100>>, <<0, 1, 100>>]]
              }
            }

          101 ->
            %AccumulationResult{
              state: %{initial_state | delegator: 2004, next_validators: :updated_next_validators}
            }

          _ ->
            %AccumulationResult{state: initial_state}
        end
      end)

      # Execute and verify results
      {updated_state, transfers, outputs, total_gas} =
        Accumulation.parallelized_accumulation(
          initial_state,
          [],
          work_reports,
          always_acc_services,
          extra_args
        )

      # Verify gas usage
      assert total_gas == [{4, 40}, {5, 50}, {6, 0}]

      # Verify state updates
      assert updated_state.manager == 2
      assert updated_state.assigners == [10_001, 10_002]
      assert updated_state.delegator == 2004
      assert updated_state.always_accumulated == %{6 => 130}
      assert updated_state.next_validators == :updated_next_validators
      assert updated_state.authorizer_queue == [[<<0, 0, 100>>, <<0, 1, 100>>], nil]

      # Verify transfers and outputs
      assert transfers == [%{amount: 40}, %{amount: 50}]
      assert length(outputs) == 2
      assert Enum.member?(outputs, %AccumulationOutput{service: 4, accumulated_output: "output4"})
      assert Enum.member?(outputs, %AccumulationOutput{service: 5, accumulated_output: "output5"})
    end

    test "correctly handles n (new services) and m (removed services)" do
      extra_args = base_extra_args()

      # Initial state with services 1, 2, 3
      initial_state =
        base_accumulation_state(%{
          services: %{
            4 => %ServiceAccount{balance: 100},
            5 => %ServiceAccount{balance: 200},
            6 => %ServiceAccount{balance: 300}
          },
          assigners: [3]
        })

      work_reports = [
        simple_work_report(4, 10),
        simple_work_report(5, 20)
      ]

      always_acc_services = %{}

      # Mock all services with a comprehensive stub to avoid conflicts
      MockAccumulation
      |> stub(:single_accumulation, fn acc_state, _, _, _, service, _ ->
        case service do
          # Manager service (1) - returns updated privileged services
          1 ->
            %AccumulationResult{
              state: %{
                acc_state
                | manager: :updated_manager,
                  assigners: [99, 100],
                  delegator: 101,
                  always_accumulated: :updated_always_accumulated
              }
            }

          # Original assigners service (3)
          3 ->
            %AccumulationResult{state: acc_state}

          # Original delegator service (2)
          2 ->
            %AccumulationResult{state: acc_state}

          # Assigners star services (99, 100)
          s when s in [99, 100] ->
            %AccumulationResult{
              state: %{acc_state | assigners: [:assigner_result_1, :assigner_result_2]}
            }

          # Delegator star service (101)
          101 ->
            %AccumulationResult{
              state: %{acc_state | delegator: :updated_delegator}
            }

          # Service 4: Updates service 4, removes service 6, adds service 7
          4 ->
            updated_services = %{
              4 => %ServiceAccount{balance: 150},
              5 => acc_state.services[5],
              7 => %ServiceAccount{balance: 400}
            }

            %AccumulationResult{
              state: %{acc_state | services: updated_services},
              transfers: [%{amount: 10}],
              output: "output4",
              gas_used: 10
            }

          # Service 5: Updates service 5, adds service 8
          5 ->
            updated_services =
              acc_state.services
              |> Map.put(5, %ServiceAccount{balance: 250})
              |> Map.put(8, %ServiceAccount{balance: 500})

            %AccumulationResult{
              state: %{acc_state | services: updated_services},
              transfers: [%{amount: 20}],
              output: "output5",
              gas_used: 20
            }

          # Default case
          _ ->
            %AccumulationResult{state: acc_state}
        end
      end)

      {updated_state, transfers, outputs, total_gas} =
        Accumulation.parallelized_accumulation(
          initial_state,
          [],
          work_reports,
          always_acc_services,
          extra_args
        )

      # Verify gas used
      assert total_gas == [{4, 10}, {5, 20}]

      # Verify services map contains the right services
      assert map_size(updated_state.services) == 4

      # Service 4 and 5 should be updated
      assert updated_state.services[4].balance == 150
      assert updated_state.services[5].balance == 250

      # Service 6 should be removed (in m)
      refute Map.has_key?(updated_state.services, 6)

      # Service 7 and 8 should be added (in n)
      assert updated_state.services[7].balance == 400
      assert updated_state.services[8].balance == 500

      # Verify transfers
      assert length(transfers) == 2
      assert Enum.sum(for t <- transfers, do: t.amount) == 30

      # Verify outputs
      assert length(outputs) == 2
      assert Enum.member?(outputs, %AccumulationOutput{service: 4, accumulated_output: "output4"})
      assert Enum.member?(outputs, %AccumulationOutput{service: 5, accumulated_output: "output5"})

      # Verify transfers are ordered by source service executions
      # First all transfers from service 4, then service 5
      assert transfers == [
               # From service 4
               %{amount: 10},
               # From service 5
               %{amount: 20}
             ]
    end
  end

  describe "sequential_accumulation/4" do
    setup do
      setup_mock_accumulation()

      :ok
    end

    test "performs basic outer accumulation correctly" do
      gas_limit = 100

      extra_args = base_extra_args()

      initial_state = base_accumulation_state(%{assigners: [2]})

      work_reports = [
        simple_work_report(4, 30),
        simple_work_report(5, 40),
        simple_work_report(4, 50)
      ]

      always_acc_services = %{6 => 20}

      # Mock single_accumulation
      MockAccumulation
      |> stub(:single_accumulation, fn acc_state, _, _, _, service, _ ->
        gas_map = %{4 => 30, 5 => 40, 6 => 20}
        gas_used = Map.get(gas_map, service, 0)

        %AccumulationResult{
          state: acc_state,
          transfers: [],
          output: "output#{service}",
          gas_used: gas_used
        }
      end)

      result =
        Accumulation.sequential_accumulation(
          gas_limit,
          [],
          work_reports,
          initial_state,
          always_acc_services,
          extra_args
        )

      assert {total_i, final_state, all_outputs, service_gas} = result
      # Only two work reports should be processed due to gas limit
      assert total_i == 2
      assert service_gas == [{4, 30}, {5, 40}, {6, 20}]
      assert final_state.services == %{4 => :service4, 5 => :service5, 6 => :service6}

      # (30 + 40 + 20)
      assert Enum.all?([4, 5, 6], fn i ->
               Enum.member?(all_outputs, %AccumulationOutput{
                 service: i,
                 accumulated_output: "output#{i}"
               })
             end)
    end
  end

  describe "calculate_posterior_services/2" do
    test "applies transfers correctly" do
      services_intermediate_2 = %{
        1 => %ServiceAccount{balance: 100},
        2 => %ServiceAccount{balance: 200},
        3 => %ServiceAccount{balance: 300}
      }

      accumualted_services_keys = Map.keys(services_intermediate_2) |> MapSet.new()

      %{1 => s1, 2 => s2, 3 => s3} =
        Accumulation.apply_last_accumulation(
          services_intermediate_2,
          1,
          accumualted_services_keys
        )

      assert s1.last_accumulation_slot == 1
      assert s2.last_accumulation_slot == 1
      assert s3.last_accumulation_slot == 1
    end

    test "handles empty transfers" do
      services_intermediate_2 = %{
        1 => %ServiceAccount{balance: 100},
        2 => %ServiceAccount{balance: 200}
      }

      accumualted_services_keys = Map.keys(services_intermediate_2) |> MapSet.new()

      %{1 => s1, 2 => s2} =
        Accumulation.apply_last_accumulation(
          services_intermediate_2,
          0,
          accumualted_services_keys
        )

      assert s1.balance == 100
      assert s2.balance == 200
    end

    test "transfers to non-existent services is a noop" do
      services_intermediate_2 = %{
        1 => %ServiceAccount{balance: 100},
        2 => %ServiceAccount{balance: 200}
      }

      accumualted_services_keys = Map.keys(services_intermediate_2) |> MapSet.new()

      %{1 => s1, 2 => s2} =
        Accumulation.apply_last_accumulation(
          services_intermediate_2,
          0,
          accumualted_services_keys
        )

      assert s1.balance == 100
      assert s2.balance == 200
    end

    test "updates last_accumulation_slot, but only to accumulated_services" do
      services_intermediate_2 = %{
        1 => %ServiceAccount{balance: 100, last_accumulation_slot: 1},
        2 => %ServiceAccount{balance: 200, last_accumulation_slot: 2}
      }

      accumualted_services_keys = MapSet.new([1])
      timeslot = 100

      %{1 => s1, 2 => s2} =
        Accumulation.apply_last_accumulation(
          services_intermediate_2,
          timeslot,
          accumualted_services_keys
        )

      assert s1.last_accumulation_slot == timeslot
      assert s2.last_accumulation_slot == 2
    end
  end

  describe "build_ready_to_accumulate/6" do
    setup do
      ready_to_accumulate = [
        [
          %Ready{
            work_report: %WorkReport{
              specification: %{work_package_hash: "hash1", exports_root: "root1"}
            }
          },
          %Ready{
            work_report: %WorkReport{
              specification: %{work_package_hash: "hash2", exports_root: "root2"}
            }
          }
        ],
        [
          %Ready{
            work_report: %WorkReport{
              specification: %{work_package_hash: "hash3", exports_root: "root3"}
            }
          },
          %Ready{
            work_report: %WorkReport{
              specification: %{work_package_hash: "hash4", exports_root: "root4"}
            }
          }
        ],
        [
          %Ready{
            work_report: %WorkReport{
              specification: %{work_package_hash: "hash5", exports_root: "root5"}
            }
          },
          %Ready{
            work_report: %WorkReport{
              specification: %{work_package_hash: "hash6", exports_root: "root6"}
            }
          }
        ]
      ]

      w_star = []
      work_package_hashes = WorkReport.work_package_hashes(w_star)

      w_q = [
        {%WorkReport{specification: %{work_package_hash: "wph3", exports_root: "root3"}},
         MapSet.new(["hash7"])},
        {%WorkReport{specification: %{work_package_hash: "wph4", exports_root: "root4"}},
         MapSet.new(["hash8"])}
      ]

      {:ok,
       ready_to_accumulate: ready_to_accumulate,
       work_package_hashes: work_package_hashes,
       w_q: w_q}
    end

    test "builds ready_to_accumulate correctly", %{
      ready_to_accumulate: ready_to_accumulate,
      work_package_hashes: work_package_hashes,
      w_q: w_q
    } do
      header_timeslot = 5
      state_timeslot = 3

      result =
        Accumulation.build_ready_to_accumulate_(
          ready_to_accumulate,
          work_package_hashes,
          w_q,
          header_timeslot,
          state_timeslot
        )

      [r0, r1, [r2_0, r2_1]] = result
      assert [^r0 | _] = ready_to_accumulate
      assert r1 == []
      assert r2_0.work_report == elem(Enum.at(w_q, 0), 0)
      assert r2_1.work_report == elem(Enum.at(w_q, 1), 0)
    end

    test "handles empty inputs" do
      result = Accumulation.build_ready_to_accumulate_([], [], [], 1, 1)

      assert result == []
    end

    test "handles large timeslot difference", %{ready_to_accumulate: ready_to_accumulate} do
      result = Accumulation.build_ready_to_accumulate_(ready_to_accumulate, [], [], 10, 1)

      assert result == [[], [], []]
    end
  end

  describe "accumulate/4" do
    setup do
      state = %State{
        privileged_services: %PrivilegedServices{
          manager: 1,
          assigners: [2],
          always_accumulated: %{1 => 100, 2 => 100}
        },
        timeslot: 3,
        services: %{
          1 => build(:service_account, balance: 1000),
          2 => build(:service_account, balance: 1000)
        }
      }

      n0_ = :crypto.strong_rand_bytes(32)

      # Set the mock module for accumulation
      setup_mock_accumulation()

      %{
        timeslot: 5,
        state: state,
        n0_: n0_
      }
    end

    test "smoke test successfully accumulates valid work reports", %{
      timeslot: timeslot,
      state: state,
      n0_: n0_
    } do
      work_reports = [
        build(:work_report,
          digests: [build(:work_digest, service: 1, gas_ratio: 10)],
          segment_root_lookup: %{}
        ),
        build(:work_report,
          digests: [build(:work_digest, service: 2, gas_ratio: 20)],
          segment_root_lookup: %{}
        )
      ]

      # Set up expectations for the mock
      MockAccumulation
      |> stub(:single_accumulation, fn _, _, _, _, _, _ ->
        %AccumulationResult{}
      end)

      Accumulation.transition(work_reports, timeslot, n0_, state)
    end
  end

  # Add this describe block in the AccumulationTest module
  describe "accumulate_statistics/1" do
    test "returns empty map for empty work reports" do
      result = Accumulation.accumulate_statistics([], [])
      assert result == %{}
    end

    test "aggregates single service with single result" do
      work_reports = [
        %WorkReport{digests: [%WorkDigest{service: 1, gas_used: 100}]}
      ]

      u = [{1, 100}]

      result = Accumulation.accumulate_statistics(work_reports, u)
      assert result == %{1 => {1, 100}}
    end

    test "service without work report but with gas" do
      work_reports = []

      u = [{1, 250}]

      result = Accumulation.accumulate_statistics(work_reports, u)
      assert result == %{1 => {0, 250}}
    end

    test "do not include services with zero stats" do
      work_reports = []

      u = [{1, 0}]

      result = Accumulation.accumulate_statistics(work_reports, u)
      assert result == %{}
    end

    test "aggregates multiple services across multiple work reports" do
      work_reports = [
        %WorkReport{
          digests: [%WorkDigest{service: 1}, %WorkDigest{service: 2}]
        },
        %WorkReport{
          digests: [%WorkDigest{service: 1}, %WorkDigest{service: 3}]
        }
      ]

      u = [{1, 100}, {1, 100}, {2, 500}, {3, 400}]
      result = Accumulation.accumulate_statistics(work_reports, u)

      assert result == %{
               # Total gas: 100 + 100, Count: 2
               1 => {2, 200},
               # Total gas: 200, Count: 1
               2 => {1, 500},
               # Total gas: 400, Count: 1
               3 => {1, 400}
             }
    end
  end

  describe "integrate_preimages/3" do
    setup do
      services = %{
        1 => build(:service_account),
        2 => build(:service_account)
      }

      {:ok, services: services}
    end

    test "return services dict when no preimages in list", %{services: services} do
      assert Accumulation.integrate_preimages(services, [], 9) == services
    end

    test "return service dict when added preimage is not in services", %{services: services} do
      assert Accumulation.integrate_preimages(services, [{3, "hash1"}], 9) == services
    end

    test "dont update when preimage_storage_l alread exists", %{services: services} do
      new_services = put_in(services, [1, :storage, {h("hash1"), 5}], [9])
      updated_services = Accumulation.integrate_preimages(new_services, [{1, "hash1"}], 9)

      assert new_services == updated_services
    end

    test "add preimage hash to service account", %{services: services} do
      preimages = [%Preimage{service: 1, blob: "hash1"}, %Preimage{service: 2, blob: "hash2"}]

      services = put_in(services, [1, :storage, {h("hash1"), 5}], [])
      services = put_in(services, [2, :storage, {h("hash2"), 5}], [])

      updated_services = Accumulation.integrate_preimages(services, preimages, 9)

      expected_services = put_in(services, [1, :storage, {h("hash1"), 5}], [9])
      expected_services = put_in(expected_services, [1, :preimage_storage_p, h("hash1")], "hash1")

      expected_services =
        put_in(expected_services, [2, :storage, {h("hash2"), 5}], [9])

      expected_services = put_in(expected_services, [2, :preimage_storage_p, h("hash2")], "hash2")

      assert updated_services == expected_services
    end
  end
end
