defmodule System.StateTransition.AuthorizerPoolTest do
  use ExUnit.Case

  alias Block.Extrinsic.Guarantee
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Constants
  alias System.State

  setup do
    authorizer_queue_ =
      for i <- 1..Constants.core_count() do
        for j <- 1..Constants.max_authorization_queue_items() do
          "queue#{i}_#{j}"
        end
      end

    authorizer_pools =
      for i <- 1..Constants.core_count() do
        for j <- 1..Constants.max_authorizations_items() do
          "auth#{i}_#{j}"
        end
      end

    timeslot = 2

    {:ok,
     %{
       authorizer_queue_: authorizer_queue_,
       authorizer_pools: authorizer_pools,
       timeslot: timeslot
     }}
  end

  test "removing no authorizer from pool works", %{
    authorizer_queue_: authorizer_queue_,
    authorizer_pools: authorizer_pools,
    timeslot: timeslot
  } do
    guarantees = []

    result =
      State.calculate_authorizer_pool_(
        guarantees,
        authorizer_queue_,
        authorizer_pools,
        timeslot
      )

    expected_result =
      for i <- 1..Constants.core_count() do
        [
          "auth#{i}_2",
          "auth#{i}_3",
          "auth#{i}_4",
          "auth#{i}_5",
          "auth#{i}_6",
          "auth#{i}_7",
          "auth#{i}_8",
          "queue#{i}_3"
        ]
      end

    assert result == expected_result
  end

  test "removing third authorizer from each core works", %{
    authorizer_queue_: authorizer_queue_,
    authorizer_pools: authorizer_pools,
    timeslot: timeslot
  } do
    guarantees =
      for i <- 1..Constants.core_count() do
        %Guarantee{work_report: %WorkReport{core_index: i - 1, authorizer_hash: "auth#{i}_3"}}
      end

    result =
      State.calculate_authorizer_pool_(guarantees, authorizer_queue_, authorizer_pools, timeslot)

    expected_result =
      for i <- 1..Constants.core_count() do
        [
          "auth#{i}_1",
          "auth#{i}_2",
          "auth#{i}_4",
          "auth#{i}_5",
          "auth#{i}_6",
          "auth#{i}_7",
          "auth#{i}_8",
          "queue#{i}_3"
        ]
      end

    assert result == expected_result
  end

  test "partially filled authorizer pools work", %{
    authorizer_queue_: authorizer_queue_,
    timeslot: timeslot
  } do
    guarantees = []

    authorizer_pools =
      Enum.map(1..Constants.core_count(), fn i ->
        Enum.map(1..(Constants.max_authorizations_items() - 3), fn j -> "auth#{i}_#{j}" end)
      end)

    result =
      State.calculate_authorizer_pool_(guarantees, authorizer_queue_, authorizer_pools, timeslot)

    expected_result =
      Enum.map(1..Constants.core_count(), fn i ->
        Enum.concat(Enum.at(authorizer_pools, i - 1), ["queue#{i}_3"])
      end)

    assert result == expected_result
  end
end
