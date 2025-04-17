defmodule System.State.AccumulationTest do
  alias Block.Extrinsic.AvailabilitySpecification
  alias Block.Extrinsic.Guarantee.{WorkReport, WorkResult}
  alias System.{AccumulationResult, DeferredTransfer}
  alias PVM.Accumulate
  alias System.State
  alias System.State.{Accumulation, PrivilegedServices, Ready, ServiceAccount}
  import Jamixir.Factory
  import Mox
  import Util.Hash
  use ExUnit.Case
  setup :verify_on_exit!

  defp mock_privileged_services(privileged_services) do
    Enum.each(
      [
        {privileged_services.privileged_services_service, :privileged_services,
         :updated_privileged_services},
        {privileged_services.next_validators_service, :next_validators, :updated_next_validators},
        {privileged_services.authorizer_queue_service, :authorizer_queue,
         :updated_authorizer_queue}
      ],
      fn {service, field, value} ->
        MockAccumulation
        |> expect(:do_single_accumulation, fn _, _, _, ^service, _ ->
          %AccumulationResult{
            state: struct(Accumulation, [{field, value}])
          }
        end)
      end
    )
  end

  setup_all do
    service = 1
    base_work_result = build(:work_result, service: service, gas_ratio: 0)
    base_work_report = build(:work_report, results: [base_work_result])

    {:ok,
     service: service, base_work_result: base_work_result, base_work_report: base_work_report}
  end

  describe "number_of_work_reports_to_accumumulate/2" do
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

      assert p == [
               %Accumulate.Operand{
                 o: "output1",
                 d: "result1",
                 e: zero(),
                 a: two(),
                 y: "hash1",
                 h: "wph1"
               },
               %Accumulate.Operand{
                 o: "output1",
                 d: "result2",
                 e: zero(),
                 a: two(),
                 y: "hash2",
                 h: "wph1"
               },
               %Accumulate.Operand{
                 o: "output2",
                 d: "result3",
                 e: zero(),
                 a: two(),
                 y: "hash3",
                 h: "wph2"
               }
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
        %{
          base_wr
          | results: [
              %{base_wr_result | service: 2, gas_ratio: 10},
              %{base_wr_result | service: 2, gas_ratio: 20}
            ]
        }
      ]

      assert {0, []} ==
               Accumulation.pre_single_accumulation(work_reports, service_dict, service)
    end
  end

  describe "accumulates privileged services/4" do
    setup do
      Application.put_env(:jamixir, :accumulation_module, MockAccumulation)

      on_exit(fn ->
        Application.put_env(:jamixir, :accumulation_module, System.State.Accumulation)
      end)

      :ok
    end

    test "accumulates privileged services correctly" do
      ctx = %{
        timeslot: Enum.random(1..1000),
        ctx_init_fn: fn _, _ -> %PVM.Host.Accumulate.Context{} end
      }

      initial_state = %Accumulation{
        privileged_services: %PrivilegedServices{
          privileged_services_service: 1,
          authorizer_queue_service: 3,
          next_validators_service: 2
        },
        services: %{1 => :service1, 2 => :service2, 3 => :service3, 4 => :service4},
        next_validators: :initial_next_validators,
        authorizer_queue: :initial_authorizer_queue
      }

      work_reports = []
      always_acc_services = %{}

      mock_privileged_services(initial_state.privileged_services)

      assert {:updated_privileged_services, :updated_next_validators, :updated_authorizer_queue} =
               Accumulation.accumulate_privileged_services(
                 initial_state,
                 work_reports,
                 always_acc_services,
                 ctx
               )
    end
  end

  describe "parallelized_accumulation/3" do
    setup do
      Application.put_env(:jamixir, :accumulation_module, MockAccumulation)

      on_exit(fn ->
        Application.put_env(:jamixir, :accumulation_module, System.State.Accumulation)
      end)

      :ok
    end

    test "performs parallelized_accumulation correctly" do
      ctx = %{
        timeslot: Enum.random(1..1000),
        ctx_init_fn: fn _, _ -> %PVM.Host.Accumulate.Context{} end
      }

      initial_state = %Accumulation{
        services: %{4 => :service4, 5 => :service5, 6 => :service6},
        privileged_services: %PrivilegedServices{
          privileged_services_service: 1,
          next_validators_service: 2,
          authorizer_queue_service: 3
        },
        next_validators: :initial_next_validators,
        authorizer_queue: :initial_authorizer_queue
      }

      work_reports = [
        %WorkReport{results: [%WorkResult{service: 4, gas_ratio: 10}]},
        %WorkReport{results: [%WorkResult{service: 5, gas_ratio: 20}]}
      ]

      always_acc_services = %{6 => 30}

      mock_privileged_services(initial_state.privileged_services)

      # Mock for accumulate_services (regular services)
      Enum.each([4, 5, 6], fn service ->
        MockAccumulation
        |> expect(:do_single_accumulation, fn _, _, _, ^service, _ ->
          %AccumulationResult{
            state: %{initial_state | services: %{service => :"updated_service#{service}"}},
            transfers: [%{amount: service * 10}],
            output: "output#{service}",
            gas_used: service * 10
          }
        end)
      end)

      result =
        Accumulation.parallelized_accumulation(
          initial_state,
          work_reports,
          always_acc_services,
          ctx
        )

      assert {updated_state, transfers, outputs, total_gas} = result

      assert total_gas == [{4, 40}, {5, 50}, {6, 60}]

      assert updated_state.privileged_services == :updated_privileged_services
      assert updated_state.next_validators == :updated_next_validators
      assert updated_state.authorizer_queue == :updated_authorizer_queue
      assert transfers == [%{amount: 40}, %{amount: 50}, %{amount: 60}]
      assert MapSet.size(outputs) == 3

      assert Enum.all?([4, 5, 6], fn service ->
               MapSet.member?(outputs, {service, "output#{service}"})
             end)
    end

    test "correctly handles n (new services) and m (removed services)" do
      ctx = %{
        timeslot: Enum.random(1..1000),
        ctx_init_fn: fn _, _ -> %PVM.Host.Accumulate.Context{} end
      }

      # Initial state with services 1, 2, 3
      initial_state = %Accumulation{
        services: %{
          4 => %ServiceAccount{balance: 100},
          5 => %ServiceAccount{balance: 200},
          6 => %ServiceAccount{balance: 300}
        },
        privileged_services: %PrivilegedServices{
          privileged_services_service: 1,
          next_validators_service: 2,
          authorizer_queue_service: 3
        },
        next_validators: :initial_next_validators,
        authorizer_queue: :initial_authorizer_queue
      }

      work_reports = [
        %WorkReport{results: [%WorkResult{service: 4, gas_ratio: 10}]},
        %WorkReport{results: [%WorkResult{service: 5, gas_ratio: 20}]}
      ]

      always_acc_services = %{}

      mock_privileged_services(initial_state.privileged_services)

      # Mock for service 4: Updates service 4, removes service 6, adds service 7
      MockAccumulation
      |> expect(:do_single_accumulation, fn acc_state, _, _, 4, _ ->
        # Create a new services map that:
        # 1. Updates service 4
        # 2. Keeps service 5 unchanged
        # 3. Omits service 6 (to be removed)
        # 4. Adds service 7 (new service)
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
      end)

      # Mock for service 5: Updates service 5, adds service 8
      MockAccumulation
      |> expect(:do_single_accumulation, fn acc_state, _, _, 5, _ ->
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
      end)

      {updated_state, transfers, outputs, total_gas} =
        Accumulation.parallelized_accumulation(
          initial_state,
          work_reports,
          always_acc_services,
          ctx
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
      assert MapSet.size(outputs) == 2

      assert Enum.all?([4, 5], fn service ->
               MapSet.member?(outputs, {service, "output#{service}"})
             end)

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
      Application.put_env(:jamixir, :accumulation_module, MockAccumulation)

      on_exit(fn ->
        Application.put_env(:jamixir, :accumulation_module, System.State.Accumulation)
      end)

      :ok
    end

    test "performs basic outer accumulation correctly" do
      gas_limit = 100

      ctx = %{
        timeslot: Enum.random(1..1000),
        ctx_init_fn: fn _, _ -> %PVM.Host.Accumulate.Context{} end
      }

      initial_state = %Accumulation{
        services: %{4 => :service4, 5 => :service5, 6 => :service6},
        privileged_services: %PrivilegedServices{
          privileged_services_service: 1,
          authorizer_queue_service: 2,
          next_validators_service: 3
        },
        next_validators: :initial_next_validators,
        authorizer_queue: :initial_authorizer_queue
      }

      work_reports = [
        %WorkReport{results: [%WorkResult{service: 4, gas_ratio: 30}]},
        %WorkReport{results: [%WorkResult{service: 5, gas_ratio: 40}]},
        %WorkReport{results: [%WorkResult{service: 4, gas_ratio: 50}]}
      ]

      always_acc_services = %{6 => 20}

      # Mock single_accumulation
      MockAccumulation
      |> expect(:do_single_accumulation, 6, fn acc_state, _, _, service, _ ->
        gas_map = %{4 => 30, 5 => 40, 6 => 20}
        gas_used = gas_map[service]

        %AccumulationResult{
          state: acc_state,
          transfers: [%{amount: gas_used}],
          output: "output#{service}",
          gas_used: gas_used
        }
      end)

      result =
        Accumulation.sequential_accumulation(
          gas_limit,
          work_reports,
          initial_state,
          always_acc_services,
          ctx
        )

      assert {total_i, final_state, all_transfers, all_outputs, service_gas} = result
      # Only two work reports should be processed due to gas limit
      assert total_i == 2
      assert service_gas == [{4, 30}, {5, 40}, {6, 20}]
      assert final_state.services == %{4 => :service4, 5 => :service5, 6 => :service6}

      # (30 + 40 + 20)
      assert Enum.all?([4, 5, 6], fn i -> MapSet.member?(all_outputs, {i, "output#{i}"}) end)

      # Verify transfers are ordered by source service executions
      # First all transfers from service 4, then service 5, then service 6
      assert all_transfers == [
               # From service 4
               %{amount: 30},
               # From service 5
               %{amount: 40},
               # From service 6
               %{amount: 20}
             ]
    end
  end

  describe "calculate_posterior_services/2" do
    test "applies transfers correctly" do
      services_intermediate_2 = %{
        1 => %ServiceAccount{balance: 100},
        2 => %ServiceAccount{balance: 200},
        3 => %ServiceAccount{balance: 300}
      }

      transfers = [
        %DeferredTransfer{sender: 1, receiver: 2, amount: 50},
        %DeferredTransfer{sender: 2, receiver: 3, amount: 75},
        %DeferredTransfer{sender: 3, receiver: 1, amount: 100}
      ]

      %{1 => {s1, _}, 2 => {s2, _}, 3 => {s3, _}} =
        Accumulation.apply_transfers(services_intermediate_2, transfers, 0)

      assert s1.balance == 200
      assert s2.balance == 250
      assert s3.balance == 375
    end

    test "handles empty transfers" do
      services_intermediate_2 = %{
        1 => %ServiceAccount{balance: 100},
        2 => %ServiceAccount{balance: 200}
      }

      %{1 => {s1, _}, 2 => {s2, _}} = Accumulation.apply_transfers(services_intermediate_2, [], 0)

      assert s1.balance == 100
      assert s2.balance == 200
    end

    test "transfers to non-existent services is a noop" do
      services_intermediate_2 = %{
        1 => %ServiceAccount{balance: 100},
        2 => %ServiceAccount{balance: 200}
      }

      transfers = [
        %DeferredTransfer{sender: 1, receiver: 3, amount: 50}
      ]

      %{1 => {s1, g1}, 2 => {s2, g2}} =
        Accumulation.apply_transfers(services_intermediate_2, transfers, 0)

      assert s1.balance == 100
      assert s2.balance == 200
      assert g1 == 0
      assert g2 == 0
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
          privileged_services_service: 1,
          authorizer_queue_service: 2,
          next_validators_service: 2,
          services_gas: %{1 => 100, 2 => 100}
        },
        timeslot: 3,
        services: %{
          1 => build(:service_account, balance: 1000),
          2 => build(:service_account, balance: 1000)
        }
      }

      n0_ = :crypto.strong_rand_bytes(32)

      # Set the mock module for accumulation
      Application.put_env(:jamixir, :accumulation_module, MockAccumulation)

      on_exit(fn ->
        Application.delete_env(:jamixir, :accumulation_module)
      end)

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
          results: [build(:work_result, service: 1, gas_ratio: 10)],
          segment_root_lookup: %{}
        ),
        build(:work_report,
          results: [build(:work_result, service: 2, gas_ratio: 20)],
          segment_root_lookup: %{}
        )
      ]

      # Set up expectations for the mock
      MockAccumulation
      |> stub(:do_single_accumulation, fn _, _, _, _, _ ->
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
        %WorkReport{
          results: [
            %WorkResult{service: 1, gas_used: 100}
          ]
        }
      ]

      u = [{1, 100}]

      result = Accumulation.accumulate_statistics(work_reports, u)
      assert result == %{1 => {1, 100}}
    end

    test "aggregates multiple services across multiple work reports" do
      work_reports = [
        %WorkReport{
          results: [
            %WorkResult{service: 1},
            %WorkResult{service: 2}
          ]
        },
        %WorkReport{
          results: [
            %WorkResult{service: 1},
            %WorkResult{service: 3}
          ]
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

  # Add to filepath: /Users/danicuki/dev/jamixir/test/system/state/accumulation_test.exs

  describe "deferred_transfers_stats/1" do
    test "returns empty map for empty transfers" do
      result = Accumulation.deferred_transfers_stats([], %{})
      assert result == %{}
    end

    test "aggregates single transfer" do
      transfers = [
        %DeferredTransfer{receiver: 1, amount: 100}
      ]

      result = Accumulation.deferred_transfers_stats(transfers, %{1 => {nil, 2}})
      assert result == %{1 => {1, 2}}
    end

    test "aggregates multiple transfers to same destination" do
      transfers = [
        %DeferredTransfer{receiver: 1, amount: 100},
        %DeferredTransfer{receiver: 1, amount: 200}
      ]

      result = Accumulation.deferred_transfers_stats(transfers, %{1 => {nil, 777}})
      # count: 2, total_amount: 300
      assert result == %{1 => {2, 777}}
    end

    test "aggregates transfers to multiple destinations" do
      transfers = [
        %DeferredTransfer{receiver: 1, amount: 100},
        %DeferredTransfer{receiver: 2, amount: 200},
        %DeferredTransfer{receiver: 1, amount: 300},
        %DeferredTransfer{receiver: 3, amount: 400}
      ]

      result =
        Accumulation.deferred_transfers_stats(transfers, %{
          1 => {nil, 5},
          2 => {nil, 10},
          3 => {nil, 16}
        })

      assert result == %{
               # count: 2, total_amount: 100 + 300
               1 => {2, 5},
               # count: 1, total_amount: 200
               2 => {1, 10},
               # count: 1, total_amount: 400
               3 => {1, 16}
             }
    end
  end
end
