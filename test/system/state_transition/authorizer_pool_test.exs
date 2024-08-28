defmodule System.StateTransition.AuthorizerPoolTest do
  use ExUnit.Case

  alias Block.Extrinsic.Guarantee
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Block.Header
  alias System.State
  alias Constants

  test "removing no authorizer from pool works" do
    # Stub guarantees
    guarantees = []

    # Stub posterior authorizer queue
    posterior_authorizer_queue =
      Enum.map(1..Constants.core_count(), fn i ->
        Enum.map(1..Constants.max_authorization_queue_items(), fn j -> "queue#{i}_#{j}" end)
      end)

    # Stub authorizer pools
    authorizer_pools =
      Enum.map(1..Constants.core_count(), fn i ->
        Enum.map(1..Constants.max_authorizations_items(), fn j -> "auth#{i}_#{j}" end)
      end)

    # Stub block header with timeslot

    # Call the function
    result =
      State.posterior_authorizer_pool(
        guarantees,
        posterior_authorizer_queue,
        authorizer_pools,
        %Header{timeslot: 2}
      )

    # Expected result after processing. Removed
    expected_result =
      Enum.map(1..Constants.core_count(), fn i ->
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
      end)

    # Assert the result matches the expected result
    assert result == expected_result
  end

  test "removing third authorizer from each core works" do
    # Stub guarantees - remove the third authorizer for each core
    guarantees =
      Enum.map(1..Constants.core_count(), fn i ->
        %Guarantee{work_report: %WorkReport{core_index: i - 1, authorizer_hash: "auth#{i}_3"}}
      end)

    # Stub posterior authorizer queue
    posterior_authorizer_queue =
      Enum.map(1..Constants.core_count(), fn i ->
        Enum.map(1..Constants.max_authorization_queue_items(), fn j -> "queue#{i}_#{j}" end)
      end)

    # Stub authorizer pools
    authorizer_pools =
      Enum.map(1..Constants.core_count(), fn i ->
        Enum.map(1..Constants.max_authorizations_items(), fn j -> "auth#{i}_#{j}" end)
      end)

    # Stub block header with timeslot
    block_header = %Header{timeslot: 2}

    # Call the function
    result =
      State.posterior_authorizer_pool(
        guarantees,
        posterior_authorizer_queue,
        authorizer_pools,
        block_header
      )

    # Expected result after processing
    expected_result =
      Enum.map(1..Constants.core_count(), fn i ->
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
      end)

    # Assert the result matches the expected result
    assert result == expected_result
  end

  test "partially filled authorizer pools work" do
    # Stub guarantees - in this case, no authorizers are being removed
    guarantees = []

    # Stub posterior authorizer queue
    posterior_authorizer_queue =
      Enum.map(1..Constants.core_count(), fn i ->
        Enum.map(1..Constants.max_authorization_queue_items(), fn j -> "queue#{i}_#{j}" end)
      end)

    # Stub authorizer pools with varying lengths (partially filled)
    authorizer_pools =
      Enum.map(1..Constants.core_count(), fn i ->
        Enum.map(1..(Constants.max_authorizations_items() - 3), fn j -> "auth#{i}_#{j}" end)
      end)

    # Stub block header with timeslot
    block_header = %Header{timeslot: 2}

    # Call the function
    result =
      State.posterior_authorizer_pool(
        guarantees,
        posterior_authorizer_queue,
        authorizer_pools,
        block_header
      )

    # Expected result after processing
    expected_result =
      Enum.map(1..Constants.core_count(), fn i ->
        Enum.concat(Enum.at(authorizer_pools, i - 1), ["queue#{i}_3"])
      end)

    # Assert the result matches the expected result
    assert result == expected_result
  end
end
