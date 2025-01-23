defmodule System.State.AccumulationTest do
  alias Block.Extrinsic.AvailabilitySpecification
  alias Block.Extrinsic.Guarantee.{WorkReport, WorkResult}
  alias System.{AccumulationResult, DeferredTransfer}
  alias PVM.Accumulate
  alias System.State
  alias System.State.{Accumulation, PrivilegedServices, Ready, ServiceAccount}
  import Jamixir.Factory
  import Mox
  use ExUnit.Case
  setup :verify_on_exit!

  setup_all do
    service = 1
    base_work_result = build(:work_result, service: service, gas_ratio: 0)
    base_work_report = build(:work_report, results: [base_work_result])

    {:ok,
     service: service, base_work_result: base_work_result, base_work_report: base_work_report}
  end

  describe "validate_services/2" do
    test "returns :ok when all indices exist" do
      state = %Accumulation{services: %{1 => :service1, 2 => :service2, 3 => :service3}}
      assert :ok == Accumulation.validate_services(state, MapSet.new([1, 2, 3]))
    end

    test "returns error when any index is missing" do
      state = %Accumulation{services: %{1 => :service1, 2 => :service2}}

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
               %Accumulate.Operand{o: "result3", l: "hash3", a: "output2", k: "wph2"},
               %Accumulate.Operand{o: "result2", l: "hash2", a: "output1", k: "wph1"},
               %Accumulate.Operand{o: "result1", l: "hash1", a: "output1", k: "wph1"}
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

  describe "update_accumulation_state/4" do
    setup do
      Application.put_env(:jamixir, :accumulation_module, MockAccumulation)

      on_exit(fn ->
        Application.put_env(:jamixir, :accumulation_module, System.State.Accumulation)
      end)

      :ok
    end

    test "updates state correctly" do
      initial_state = %Accumulation{
        privileged_services: %PrivilegedServices{
          manager_service: 1,
          alter_authorizer_service: 2,
          alter_validator_service: 3
        },
        services: %{1 => :service1, 2 => :service2, 3 => :service3, 4 => :service4},
        next_validators: :initial_next_validators,
        authorizer_queue: :initial_authorizer_queue
      }

      work_reports = []
      always_acc_services = %{}
      s = MapSet.new([1, 2, 3])

      Enum.each(
        [
          {1, :privileged_services, :updated_privileged_services},
          {2, :next_validators, :updated_next_validators},
          {3, :authorizer_queue, :updated_authorizer_queue}
        ],
        fn {service, key, updated_value} ->
          MockAccumulation
          |> expect(:do_single_accumulation, fn ^initial_state,
                                                ^work_reports,
                                                ^always_acc_services,
                                                ^service ->
            %AccumulationResult{
              state: struct(Accumulation, [{key, updated_value}])
            }
          end)
        end
      )

      Enum.each(s, fn service ->
        MockAccumulation
        |> expect(:do_single_accumulation, fn ^initial_state,
                                              ^work_reports,
                                              ^always_acc_services,
                                              ^service ->
          %AccumulationResult{
            state: %Accumulation{
              services: Map.put(%{}, service, :"updated_service#{service}")
            }
          }
        end)
      end)

      updated_state =
        Accumulation.update_accumulation_state(
          initial_state,
          work_reports,
          always_acc_services,
          s
        )

      assert updated_state.privileged_services == :updated_privileged_services
      assert updated_state.next_validators == :updated_next_validators
      assert updated_state.authorizer_queue == :updated_authorizer_queue

      assert updated_state.services == %{
               1 => :updated_service1,
               2 => :updated_service2,
               3 => :updated_service3,
               4 => :service4
             }
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

    test "performs basic accumulation correctly" do
      initial_state = %Accumulation{
        services: %{1 => :service1, 2 => :service2, 3 => :service3},
        privileged_services: %PrivilegedServices{
          manager_service: 1,
          alter_authorizer_service: 2,
          alter_validator_service: 3
        },
        next_validators: :initial_next_validators,
        authorizer_queue: :initial_authorizer_queue
      }

      work_reports = [
        %WorkReport{results: [%WorkResult{service: 1, gas_ratio: 10}]},
        %WorkReport{results: [%WorkResult{service: 2, gas_ratio: 20}]}
      ]

      always_acc_services = %{3 => 30}

      # Mock for accumulate_services (3 calls)
      Enum.each([1, 2, 3], fn service ->
        MockAccumulation
        |> expect(:do_single_accumulation, fn ^initial_state,
                                              ^work_reports,
                                              ^always_acc_services,
                                              ^service ->
          %AccumulationResult{
            state: %{initial_state | services: %{service => :"updated_service#{service}"}},
            transfers: [%{amount: service * 10}],
            output: "output#{service}",
            gas_used: service * 10
          }
        end)
      end)

      # Mock for update_accumulation_state (6 calls)
      # 3 calls for privileged services
      Enum.each([1, 2, 3], fn service ->
        MockAccumulation
        |> expect(:do_single_accumulation, fn ^initial_state,
                                              ^work_reports,
                                              ^always_acc_services,
                                              ^service ->
          %AccumulationResult{
            state: %Accumulation{
              privileged_services:
                if(service == 1,
                  do: :updated_privileged_services,
                  else: initial_state.privileged_services
                ),
              next_validators:
                if(service == 2,
                  do: :updated_next_validators,
                  else: initial_state.next_validators
                ),
              authorizer_queue:
                if(service == 3,
                  do: :updated_authorizer_queue,
                  else: initial_state.authorizer_queue
                )
            }
          }
        end)
      end)

      # 3 more calls for regular services
      Enum.each([1, 2, 3], fn service ->
        MockAccumulation
        |> expect(:do_single_accumulation, fn ^initial_state,
                                              ^work_reports,
                                              ^always_acc_services,
                                              ^service ->
          %AccumulationResult{
            state: %Accumulation{
              services: %{service => :"updated_service#{service}"}
            }
          }
        end)
      end)

      {:ok, result} =
        Accumulation.parallelized_accumulation(initial_state, work_reports, always_acc_services)

      assert {total_gas, updated_state, transfers, outputs} = result
      # 10 + 20 + 30
      assert total_gas == 60

      assert updated_state.services == %{
               1 => :updated_service1,
               2 => :updated_service2,
               3 => :updated_service3
             }

      assert updated_state.privileged_services == :updated_privileged_services
      assert updated_state.next_validators == :updated_next_validators
      assert updated_state.authorizer_queue == :updated_authorizer_queue
      assert transfers == [%{amount: 30}, %{amount: 20}, %{amount: 10}]
      assert MapSet.size(outputs) == 3
      assert Enum.all?(outputs, fn {service, output} -> output == "output#{service}" end)
    end
  end

  describe "outer_accumulation/4" do
    setup do
      Application.put_env(:jamixir, :accumulation_module, MockAccumulation)

      on_exit(fn ->
        Application.put_env(:jamixir, :accumulation_module, System.State.Accumulation)
      end)

      :ok
    end

    test "performs basic outer accumulation correctly" do
      gas_limit = 100

      initial_state = %Accumulation{
        services: %{1 => :service1, 2 => :service2, 3 => :service3},
        privileged_services: %PrivilegedServices{
          manager_service: 1,
          alter_authorizer_service: 2,
          alter_validator_service: 3
        },
        next_validators: :initial_next_validators,
        authorizer_queue: :initial_authorizer_queue
      }

      work_reports = [
        %WorkReport{results: [%WorkResult{service: 1, gas_ratio: 30}]},
        %WorkReport{results: [%WorkResult{service: 2, gas_ratio: 40}]},
        %WorkReport{results: [%WorkResult{service: 1, gas_ratio: 50}]}
      ]

      always_acc_services = %{3 => 20}

      # Mock single_accumulation
      MockAccumulation
      |> expect(:do_single_accumulation, 9, fn acc_state, _work_reports, _service_dict, service ->
        gas_map = %{1 => 30, 2 => 40, 3 => 20}
        gas_used = gas_map[service]

        %AccumulationResult{
          state: acc_state,
          transfers: [%{amount: gas_used}],
          output: "output#{service}",
          gas_used: gas_used
        }
      end)

      result =
        Accumulation.outer_accumulation(
          gas_limit,
          work_reports,
          initial_state,
          always_acc_services
        )

      assert {:ok, {total_i, final_state, all_transfers, all_outputs}} = result
      # Only two work reports should be processed due to gas limit
      assert total_i == 2
      assert final_state.services == %{1 => :service1, 2 => :service2, 3 => :service3}

      # (30 + 40 + 20)
      assert Enum.sum(for t <- all_transfers, do: t.amount) == 90
      assert Enum.all?(1..3, fn i -> MapSet.member?(all_outputs, {i, "output#{i}"}) end)
    end

    test "returns error when encountering an invalid service" do
      gas_limit = 100

      initial_state = %Accumulation{
        services: %{1 => :service1, 2 => :service2},
        privileged_services: %PrivilegedServices{
          manager_service: 1,
          alter_authorizer_service: 2,
          alter_validator_service: 3
        },
        next_validators: :initial_next_validators,
        authorizer_queue: :initial_authorizer_queue
      }

      work_reports = [
        %WorkReport{results: [%WorkResult{service: 1, gas_ratio: 30}]},
        # Invalid service
        %WorkReport{results: [%WorkResult{service: 3, gas_ratio: 40}]},
        %WorkReport{results: [%WorkResult{service: 2, gas_ratio: 50}]}
      ]

      always_acc_services = %{}

      result =
        Accumulation.outer_accumulation(
          gas_limit,
          work_reports,
          initial_state,
          always_acc_services
        )

      assert {:error, :invalid_service} = result
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

      result = Accumulation.calculate_posterior_services(services_intermediate_2, transfers, 0)
      assert result[1].balance == 200
      assert result[2].balance == 250
      assert result[3].balance == 375
    end

    test "handles empty transfers" do
      services_intermediate_2 = %{
        1 => %ServiceAccount{balance: 100},
        2 => %ServiceAccount{balance: 200}
      }

      result = Accumulation.calculate_posterior_services(services_intermediate_2, [], 0)

      assert result == services_intermediate_2
    end

    test "transfers to non-existent services is a noop" do
      services_intermediate_2 = %{
        1 => %ServiceAccount{balance: 100},
        2 => %ServiceAccount{balance: 200}
      }

      transfers = [
        %DeferredTransfer{sender: 1, receiver: 3, amount: 50}
      ]

      result = Accumulation.calculate_posterior_services(services_intermediate_2, transfers, 0)

      assert result == services_intermediate_2
    end
  end

  describe "build_ready_to_accumulate_/6" do
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

      {:ok, ready_to_accumulate: ready_to_accumulate, work_package_hashes: work_package_hashes, w_q: w_q}
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
          manager_service: 1,
          alter_authorizer_service: 2,
          alter_validator_service: 2,
          services_gas: %{1 => 100, 2 => 100}
        },
        timeslot: 3,
        services: %{
          1 => build(:service_account, balance: 1000),
          2 => build(:service_account, balance: 1000)
        }
      }

      # Set the mock module for accumulation
      Application.put_env(:jamixir, :accumulation_module, MockAccumulation)

      on_exit(fn ->
        Application.delete_env(:jamixir, :accumulation_module)
      end)

      %{
        timeslot: 5,
        state: state
      }
    end

    test "successfully accumulates valid work reports", %{
      timeslot: timeslot,
      state: state
    } do
      work_reports = [
        build(:work_report, results: [%{service: 1, gas_ratio: 10}], segment_root_lookup: %{}),
        build(:work_report, results: [%{service: 2, gas_ratio: 20}], segment_root_lookup: %{})
      ]

      # Set up expectations for the mock
      MockAccumulation
      |> stub(:do_single_accumulation, fn _, _, _, _ ->
        %AccumulationResult{}
      end)

      result = Accumulation.transition(work_reports, timeslot, state)

      assert {:ok, _accumulated_state} = result
    end

    test "returns error when encountering an invalid service", %{
      timeslot: timeslot,
      state: state
    } do
      work_reports = [
        build(:work_report, results: [%{service: 1, gas_ratio: 10}], segment_root_lookup: %{}),
        # Invalid service
        build(:work_report, results: [%{service: 3, gas_ratio: 20}], segment_root_lookup: %{})
      ]

      assert {:error, :invalid_service} =
               Accumulation.transition(work_reports, timeslot, state)
    end
  end
end
